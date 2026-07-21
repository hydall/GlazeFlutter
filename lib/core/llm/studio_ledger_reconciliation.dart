import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db/repositories/ledger_reconciliation_checkpoint_repo.dart';
import '../models/chat_message.dart';
import '../models/tracker.dart';

const ledgerReconciliationPromptBlockId = 'ledger_reconciliation_prompt';

class LedgerReconciliationPlan {
  final List<ChatMessage> messages;
  final ChatMessage endMessage;
  final String rangeHash;

  const LedgerReconciliationPlan({
    required this.messages,
    required this.endMessage,
    required this.rangeHash,
  });

  String get startMessageId => messages.first.id;
  List<String> get messageIds => messages.map((message) => message.id).toList();
}

class LedgerReconciliationPlanner {
  static const interval = 6;
  static const maxMessages = 20;

  const LedgerReconciliationPlanner();

  LedgerReconciliationPlan? plan({
    required List<ChatMessage> messages,
    required String currentAssistantMessageId,
    LedgerReconciliationCheckpoint? checkpoint,
  }) {
    final currentIndex = messages.indexWhere(
      (message) => message.id == currentAssistantMessageId,
    );
    if (currentIndex < 0) return null;

    final acceptedAssistants = messages
        .take(currentIndex)
        .where(_isAcceptedAssistant)
        .toList(growable: false);
    if (acceptedAssistants.isEmpty ||
        acceptedAssistants.length % interval != 0) {
      return null;
    }

    // Review boundary N only while N+1 is being generated. A reroll of N+1
    // has the same boundary and is deduplicated by the checkpoint; N+2 must
    // never re-run or rewrite the older boundary.
    final end = acceptedAssistants.last;
    final endIndex = messages.indexWhere((message) => message.id == end.id);
    final startIndex = endIndex + 1 > maxMessages
        ? endIndex + 1 - maxMessages
        : 0;
    final range = messages
        .sublist(startIndex, endIndex + 1)
        .where(_isReviewable)
        .toList(growable: false);
    if (range.isEmpty) return null;

    final hash = sha256
        .convert(
          utf8.encode(
            range
                .map(
                  (message) =>
                      '${message.id}\u001f${message.swipeId}\u001f'
                      '${message.agentSwipeId}\u001f${message.role}\u001f'
                      '${message.content}',
                )
                .join('\u001e'),
          ),
        )
        .toString();
    if (checkpoint?.endMessageId == end.id &&
        checkpoint?.endSwipeId == end.swipeId &&
        checkpoint?.endAgentSwipeId == end.agentSwipeId &&
        checkpoint?.rangeHash == hash) {
      return null;
    }
    return LedgerReconciliationPlan(
      messages: range,
      endMessage: end,
      rangeHash: hash,
    );
  }

  bool _isAcceptedAssistant(ChatMessage message) =>
      message.role == 'assistant' &&
      !message.isTyping &&
      !message.isError &&
      !message.isHidden &&
      message.content.trim().isNotEmpty;

  bool _isReviewable(ChatMessage message) =>
      (message.role == 'assistant' || message.role == 'user') &&
      !message.isTyping &&
      !message.isError &&
      !message.isHidden &&
      message.content.trim().isNotEmpty;
}

class StudioLedgerReconciliationPrompt {
  const StudioLedgerReconciliationPrompt();

  String build({
    required String systemPrompt,
    required LedgerReconciliationPlan plan,
    required List<Tracker> trackers,
  }) {
    final chat = plan.messages
        .map(
          (message) =>
              '${message.role == 'assistant' ? 'Assistant' : 'User'} '
              '[${message.id}]: ${message.content}',
        )
        .join('\n\n');
    final relevant = _relevantTrackers(trackers, chat);
    final state = relevant.isEmpty
        ? '(no committed state)'
        : relevant.map((row) => '${row.name}: ${row.value}').join('\n');
    final keys =
        trackers.where(_isLedgerTracker).map((row) => row.name).toSet().toList()
          ..sort();

    return '''$systemPrompt

<review_range start="${plan.startMessageId}" end="${plan.endMessage.id}">
$chat
</review_range>

<committed_state>
$state
</committed_state>

<existing_keys>
${keys.isEmpty ? '(no keys)' : keys.join('\n')}
</existing_keys>

Return exactly:
<glaze_memory_export>
{"ops":[],"knowledgeFacts":[]}
</glaze_memory_export>

Allowed namespaces: npc:, relationship:, arc:, world:, scene.
Allowed ops: set, delete. Keep set values under 1200 characters.''';
  }

  List<Tracker> _relevantTrackers(List<Tracker> trackers, String chat) {
    final terms = _terms(chat);
    final candidates =
        trackers
            .where(_isLedgerTracker)
            .map((tracker) {
              var score = 0;
              final lower = '${tracker.name} ${tracker.value}'.toLowerCase();
              if (tracker.name.startsWith('scene.') ||
                  tracker.name.startsWith('world:')) {
                score += 100;
              }
              if (_isPlaceholder(lower)) score += 1000;
              score += terms.where(lower.contains).length * 10;
              return (tracker: tracker, score: score);
            })
            .where((item) => item.score > 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    const characterBudget = 60000;
    var used = 0;
    final selected = <Tracker>[];
    for (final item in candidates) {
      final size = item.tracker.name.length + item.tracker.value.length + 2;
      if (used + size > characterBudget) continue;
      selected.add(item.tracker);
      used += size;
    }
    return selected;
  }

  Set<String> _terms(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((term) => term.length >= 4)
      .toSet();

  bool _isPlaceholder(String text) => RegExp(
    r'\b(unknown|unidentified|stranger|неизвестн\p{L}*|незнаком\p{L}*)\b',
    unicode: true,
  ).hasMatch(text);

  bool _isLedgerTracker(Tracker tracker) =>
      (tracker.scope == 'ledger' || tracker.scope == 'chat') &&
      (tracker.name.startsWith('npc:') ||
          tracker.name.startsWith('relationship:') ||
          tracker.name.startsWith('arc:') ||
          tracker.name.startsWith('world:') ||
          tracker.name.startsWith('scene.'));
}

const fallbackLedgerReconciliationPrompt = '''You reconcile the committed
Studio Ledger against a bounded range of accepted chat messages.

Correct current state; do not summarize the conversation. User statements and
explicit corrections have highest priority. Assistant narration is evidence of
what was narrated, not proof of hidden motives, unseen research, ownership,
causation, or off-screen events.

When a placeholder identity is resolved, set the canonical entity keys and
delete obsolete Unknown, Unidentified, Stranger, or equivalent keys in the same
patch. Delete stale current locations after a scene or time advance when the
entity's location is no longer established. Keep current_goal limited to the
immediate active objective, not a backlog. Remove unsupported inference rather
than inventing a replacement fact.

Return only the required JSON export block. Do not emit knowledgeFacts.''';
