import '../models/memory_book.dart';
import '../models/tracker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StudioLedgerPrompt
//
// Builds the prompt for the Studio Ledger LLM call.
// Pure, stateless — all inputs are passed explicitly.
//
// Based on the Studio Ledger prompt contract: the ledger is an internal
// continuity/state extractor that maintains session-canon facts for future
// generations. It does NOT write story prose. It preserves prior state unless
// contradicted, promotes only durable facts, distinguishes event states
// (planned/suggested/threatened/attempted/completed/failed/cancelled/unknown),
// and never converts threats/plans/questions/offers/pending choices into
// completed facts. Returns <studio_ledger> + <glaze_memory_export> JSON,
// preferring patch ops in `ops` for persistence.
// ─────────────────────────────────────────────────────────────────────────────

/// Builds the non-streaming prompt sent to the Studio Ledger model.
class StudioLedgerPrompt {
  const StudioLedgerPrompt();

  /// Build the full ledger prompt from the turn's context.
  ///
  /// [finalAssistantText] — cleaned final assistant response (post-cleaner
  /// output when enabled, raw response otherwise).
  ///
  /// [recentHistoryText] — last ~10 user+assistant turns in plain text,
  /// for scene/entity context.
  ///
  /// [currentTrackers] — current tracker_rows for this session (entity,
  /// relationship, arc, world, scene state written by prior ledger runs).
  ///
  /// [recentMemoryEntries] — up to 20 active MemoryBook entries (title + keys
  /// only, content omitted to keep prompt lean).
  String build({
    required String finalAssistantText,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    required List<MemoryEntry> recentMemoryEntries,
  }) {
    final trackerBlock = _buildTrackerBlock(currentTrackers);
    final memoryBlock = _buildMemoryBlock(recentMemoryEntries);

    return '''$_systemPrompt

<current_state>
$trackerBlock
</current_state>

<existing_memory>
$memoryBlock
</existing_memory>

<recent_chat>
$recentHistoryText
</recent_chat>

<final_assistant_response>
$finalAssistantText
</final_assistant_response>

Now produce the Studio Ledger output. You MUST return BOTH blocks below.
The <glaze_memory_export> block is MANDATORY — even when there is nothing
to write, include it with empty arrays. Do not omit it under any circumstance.

Required response template (follow this exact structure):
<glaze_memory_export>
{"ops":[],"durableFacts":[]}
</glaze_memory_export>
<studio_ledger>
Compact continuity snapshot here.
</studio_ledger>

The <glaze_memory_export> block MUST come first, before <studio_ledger>.
It must contain a single JSON object with "ops" and "durableFacts" arrays.
When there are no state changes or durable facts, output empty arrays —
do NOT skip the block.

Ops format:
{"ops":[{"op":"set","key":"npc:Name.field","value":"…","evidence":"…","eventState":"completed"},…],"durableFacts":[{"title":"…","content":"…","keys":["…"],"entities":["…"]}]}

Allowed namespaces: npc:, relationship:, arc:, world:, scene.
Allowed ops: set, append_unique, delete.
Allowed eventState: planned, suggested, threatened, attempted, completed, failed, cancelled, unknown (or omit).
Max value length: 2000 chars.''';
  }

  String _buildTrackerBlock(List<Tracker> trackers) {
    if (trackers.isEmpty) return '(no prior state)';
    // Show only ledger-scope trackers (entity/relationship/arc/world/scene).
    final ledgerTrackers = trackers
        .where((t) => t.scope == 'ledger' || t.scope == 'chat')
        .where(
          (t) =>
              t.name.startsWith('npc:') ||
              t.name.startsWith('relationship:') ||
              t.name.startsWith('arc:') ||
              t.name.startsWith('world:') ||
              t.name.startsWith('scene.'),
        )
        .toList();
    if (ledgerTrackers.isEmpty) return '(no prior state)';
    return ledgerTrackers
        .map((t) => '${t.name}: ${t.value}')
        .join('\n');
  }

  String _buildMemoryBlock(List<MemoryEntry> entries) {
    if (entries.isEmpty) return '(no existing memory)';
    return entries
        .take(20)
        .map((e) {
          final keys = e.keys.isEmpty ? '' : ' [${e.keys.join(', ')}]';
          final locked = e.locked ? ' [locked]' : '';
          return '- ${e.title.isNotEmpty ? e.title : e.id}$keys$locked';
        })
        .join('\n');
  }

  static const String _systemPrompt = '''You are Studio Ledger, an internal continuity and state extractor.
You do not write story prose.
You maintain session-canon facts for future generations.

Use the final assistant response, latest user message, previous ledger, recent chat, current state, and existing memory.

Rules:
- Preserve prior state unless contradicted by the final response.
- Promote only durable, future-relevant facts into durableFacts.
- Temporary posture/outfit/props stay in the visible ledger unless they became important.
- Do not create quests unless an explicit task/goal exists.
- Do not create persona stats unless already tracked.
- Do not infer romance/trust jumps without evidence in the final response.
- Session state overrides character-card baseline.
- If an arc from the card is resolved in session canon, mark it completed with do_not_reopen=true.
- Never write future events as facts.
- Pending user choices are hooks, not completed events.
- Do not convert threats, plans, questions, offers, or pending choices into completed facts.
- Distinguish planned, suggested, threatened, attempted, completed, failed, cancelled, and unknown event states.
- Do not mark an entity present only because it is mentioned.
- Do not mark an entity absent unless it explicitly leaves, dies, is left behind, or the scene changes.
- Return <studio_ledger> plus <glaze_memory_export> JSON.
- Prefer patch ops in the ops list for persistence. Do not rewrite the whole world state.
- Keep entity/relationship/arc/world state compact. Update current truth; do not create a history log.
- Never output ledger text as story prose or a chat message.
- Entity state keys: npc:Name.relationship_to_user, npc:Name.attitude_to_user, npc:Name.knowledge, npc:Name.boundaries, npc:Name.card_overrides
- Relationship keys: relationship:A:B.relationship, relationship:A:B.attitude, relationship:A:B.knowledge
- Arc keys: arc:id.status, arc:id.summary, arc:id.do_not_reopen, arc:id.card_override
- World/scene keys: world:location, world:time, world:date, world:active_threats, scene.present_entities, scene.absent_backstory_entities''';
}
