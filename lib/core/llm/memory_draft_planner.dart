import '../models/chat_message.dart';
import '../models/memory_book.dart';

class MemoryDraftPlan {
  final List<MemoryDraft> drafts;
  final int stableMessageCount;
  final int eligibleMessageCount;
  final int uncoveredMessageCount;

  const MemoryDraftPlan({
    required this.drafts,
    required this.stableMessageCount,
    required this.eligibleMessageCount,
    required this.uncoveredMessageCount,
  });
}

class MemoryDraftPlanner {
  const MemoryDraftPlanner._();

  static MemoryDraftPlan plan({
    required MemoryBook book,
    required List<ChatMessage> messages,
    required int interval,
    required int lagMessages,
    required String source,
    required int nowMillis,
  }) {
    final stableMessages = messages
        .where((m) => !m.isTyping && (m.role == 'user' || m.role == 'assistant'))
        .toList();
    final normalizedLag = lagMessages < 0 ? 0 : lagMessages;
    final eligibleMessages = stableMessages.length > normalizedLag
        ? stableMessages.take(stableMessages.length - normalizedLag).toList()
        : <ChatMessage>[];

    // Covered-by-manual-scan: only curated/manual entries block the next scan
    // segment. Agentic entries (`source:'agentic'`) are written by the agent
    // write-loop and must NOT suppress a fresh manual scan over the same
    // message range — otherwise the manual planner can never re-summarize a
    // range the agent already touched.
    // Studio Ledger entries (`source:'studio_ledger'`) are legacy durable
    // facts that were removed from the injection pipeline — they must NOT
    // block the manual scan. The manual scan is a complementary summarization
    // layer. Without this skip, legacy durable facts across messages would
    // mask most of the chat from the scanner.
    final coveredIds = <String>{};
    for (final entry in book.entries) {
      if (entry.source == 'agentic' || entry.source == 'studio_ledger') {
        continue;
      }
      coveredIds.addAll(entry.messageIds);
    }
    for (final draft in book.pendingDrafts) {
      coveredIds.addAll(draft.messageIds);
    }

    final uncovered = eligibleMessages
        .where((m) => m.id.isNotEmpty && !coveredIds.contains(m.id))
        .toList();

    // Build segments by stable-message index, not by uncovered-list index.
    // This ensures titles show real chat positions (1-15, 16-30, …) and
    // segments cover contiguous chat ranges even when some messages in the
    // range are already covered by Studio Ledger / agentic entries.
    //
    // Algorithm: walk eligible messages in stable order. Start a segment at
    // the first uncovered message. Accumulate uncovered messages until the
    // segment reaches [segmentSize] uncovered entries OR we run out of
    // eligible messages. The segment's title is the stable index of its
    // first uncovered message → stable index of its last uncovered message.
    final segmentSize = interval < 1 ? 1 : interval;
    final newDrafts = <MemoryDraft>[];
    {
      final eligibleSet = eligibleMessages;
      final uncoveredSet = uncovered.map((m) => m.id).toSet();
      int i = 0; // index into eligibleMessages
      while (i < eligibleSet.length) {
        // Skip covered messages to find the start of the next segment.
        if (!uncoveredSet.contains(eligibleSet[i].id)) {
          i++;
          continue;
        }
        // Start a new segment at position i.
        final segmentMsgs = <ChatMessage>[];
        int j = i;
        while (j < eligibleSet.length && segmentMsgs.length < segmentSize) {
          if (uncoveredSet.contains(eligibleSet[j].id)) {
            segmentMsgs.add(eligibleSet[j]);
          }
          j++;
        }
        if (segmentMsgs.length < segmentSize) {
          // Not enough uncovered messages left for a full segment.
          break;
        }
        final segmentIds =
            segmentMsgs.map((m) => m.id).toList(growable: false);
        final segmentIdSet = segmentIds.toSet();
        final alreadyExists = book.pendingDrafts.any(
          (d) => d.messageIds.toSet().containsAll(segmentIdSet),
        );
        if (!alreadyExists) {
          final firstIdx = stableMessages.indexOf(segmentMsgs.first);
          final lastIdx = stableMessages.indexOf(segmentMsgs.last);
          final uniqueSuffix = segmentIds.join('|').hashCode.abs();
          newDrafts.add(
            MemoryDraft(
              id: 'draft_${nowMillis}_${newDrafts.length}_$uniqueSuffix',
              title: '${firstIdx + 1}-${lastIdx + 1}',
              messageIds: segmentIds,
              messageRange:
                  MessageRange(start: firstIdx + 1, end: lastIdx + 1),
              status: 'pending_generation',
              source: source,
              createdAt: nowMillis,
              updatedAt: nowMillis,
            ),
          );
        }
        i = j;
      }
    }

    return MemoryDraftPlan(
      drafts: newDrafts,
      stableMessageCount: stableMessages.length,
      eligibleMessageCount: eligibleMessages.length,
      uncoveredMessageCount: uncovered.length,
    );
  }
}
