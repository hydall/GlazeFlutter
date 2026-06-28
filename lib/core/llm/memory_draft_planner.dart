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
    // range the agent already touched. See docs/plans/PLAN_MEMORY_CONTINUITY.md §1.
    final coveredIds = <String>{};
    for (final entry in book.entries) {
      if (entry.source == 'agentic') continue;
      coveredIds.addAll(entry.messageIds);
    }
    for (final draft in book.pendingDrafts) {
      coveredIds.addAll(draft.messageIds);
    }

    final uncovered = eligibleMessages
        .where((m) => m.id.isNotEmpty && !coveredIds.contains(m.id))
        .toList();

    final segmentSize = interval < 1 ? 1 : interval;
    final newDrafts = <MemoryDraft>[];
    for (int i = 0; i + segmentSize <= uncovered.length; i += segmentSize) {
      final segment = uncovered.sublist(i, i + segmentSize);
      final segmentIds = segment.map((m) => m.id).toList(growable: false);
      final segmentIdSet = segmentIds.toSet();
      final alreadyExists = book.pendingDrafts.any(
        (d) => d.messageIds.toSet().containsAll(segmentIdSet),
      );
      if (alreadyExists) continue;

      final firstIdx = stableMessages.indexOf(segment.first);
      final lastIdx = stableMessages.indexOf(segment.last);
      final uniqueSuffix = segmentIds.join('|').hashCode.abs();
      newDrafts.add(
        MemoryDraft(
          id: 'draft_${nowMillis}_${i}_$uniqueSuffix',
          title: '${firstIdx + 1}-${lastIdx + 1}',
          messageIds: segmentIds,
          messageRange: MessageRange(start: firstIdx + 1, end: lastIdx + 1),
          status: 'pending_generation',
          source: source,
          createdAt: nowMillis,
          updatedAt: nowMillis,
        ),
      );
    }

    return MemoryDraftPlan(
      drafts: newDrafts,
      stableMessageCount: stableMessages.length,
      eligibleMessageCount: eligibleMessages.length,
      uncoveredMessageCount: uncovered.length,
    );
  }
}
