# Studio Ledger Memory Plan

## Goal

When Studio is enabled, it should maintain a mandatory internal continuity ledger after every final assistant response. The ledger updates MemoryBook and compact entity/relationship state so long-running chats do not reset NPCs to card baseline.

The ledger runs after the canonical assistant text is finalized:

- If POST-cleaner is enabled, after the cleaner finishes.
- If POST-cleaner is disabled, after the main assistant response is saved.

The user should not need to create a chat-specific lorebook. MemoryBooks are the durable chat memory layer.

## Product Decisions

- Studio Ledger is mandatory while Studio is enabled.
- It is internal and cannot be toggled off by user ExtBlock settings.
- It may reuse ExtBlock-like storage/UI mechanics, but it is not a user ExtBlock and must not be injected as one.
- It does not depend on the active extension preset or `extensionsSettings.enabled`.
- User ExtBlocks remain optional and user-owned.
- Consolidation is not part of this design.
- Quests, combat, and persona stats are not mandatory built-in memory domains.
- Relationship/entity state is compact current truth, not an append-only event log.
- Arc/world state is compact session canon. It resolves card hooks without editing the character card.

## Memory Model

### Character Cards

Character cards describe baseline/default traits and initial conditions.

Cards may also describe initial unresolved hooks or multiple possible arcs. Once a chat resolves one of those arcs, session canon must override the card hook instead of letting the model replay it as unresolved.

### MemoryBook

MemoryBook stores durable facts established in this chat.

Examples:

- Lucy accepted a fragile alliance with Danvi.
- Danvi knows Lucy's role in David's fate.
- Lucy no longer treats Danvi as a random newcomer.
- David's yellow jacket remains an emotional anchor.
- Net hunters can burn synapses through ports while targets sleep.

MemoryBook is not the relationship-state table. It stores durable events and facts that may justify current state, but the latest compact truth about an entity or relationship lives in entity/relationship state.

### Studio Ledger

Studio Ledger stores live scene continuity and produces durable-memory exports.

It tracks:

- Current scene continuity.
- NPC state.
- Relationships.
- What NPCs know or believe.
- Promises, debts, obligations.
- Secrets revealed.
- Active threats and boundaries.
- Active, paused, completed, failed, abandoned, or superseded arcs.
- Card hooks that have been resolved by this session.
- Compact world state.
- Durable facts.
- Card baseline overrides.

### Entity State

Entity state stores compact current truth about entities.

MVP storage can use `tracker_rows` with namespaced keys:

```text
npc:Lucyna Kushinada.relationship_to_user
npc:Lucyna Kushinada.attitude_to_user
npc:Lucyna Kushinada.knowledge
npc:Lucyna Kushinada.boundaries
npc:Lucyna Kushinada.card_overrides
scene.location
scene.immediate_thread
scene.active_tensions
```

Later, this can move to a dedicated `memory_entity_state_rows` table if needed.

Entity state must be updated by stable keys with upsert semantics. It must not create one new row per turn for the same entity/aspect.

### Relationship State

Relationship state stores compact current truth about pairs of entities. It is separate from durable MemoryBook events.

MVP storage can use `tracker_rows` with namespaced keys:

```text
relationship:Danvi:Lucyna Kushinada.relationship = fragile alliance
relationship:Danvi:Lucyna Kushinada.attitude = wary but familiar
relationship:Danvi:Lucyna Kushinada.boundaries = Lucy will retaliate if endangered
relationship:Danvi:Lucyna Kushinada.knowledge = Danvi knows Lucy's role in David's fate
relationship:Danvi:Lucyna Kushinada.card_overrides = Danvi is not a random newcomer to Lucy
```

These rows are current-state rows. Each ledger pass may update the value for an existing key, but should not append another copy of the same relationship fact.

Later, this can move to a dedicated table:

```text
memory_relationship_state_rows:
- sessionId
- subjectEntityId
- objectEntityId
- relationType
- stateJson
- sourceMessageId
- sourceHash
- updatedAt
```

### Arc State

Arc state stores the lifecycle of story/world/card hooks. It is not a long summary of chat history. It is the current canon status of arcs that affect future generation.

MVP storage can use `tracker_rows` with namespaced keys:

```text
arc:david_fate.status = completed
arc:david_fate.summary = Danvi knows Lucy's role in David's fate.
arc:david_fate.do_not_reopen = true
arc:david_fate.card_override = Treat David's fate as resolved backstory, not an active hidden secret.
arc:net_hunters.status = active
arc:net_hunters.summary = Net hunters remain a threat if Lucy and Danvi stop moving.
arc:lucy_danvi_alliance.status = active
arc:lucy_danvi_alliance.summary = Fragile practical alliance, wary but familiar.
```

Suggested statuses:

```text
seeded
active
paused
completed
failed
abandoned
superseded
```

`completed` does not mean the arc can never be mentioned. It means it must not be played as unresolved. Completed arcs may appear as backstory, consequences, trauma, or context.

`do_not_reopen` means the model should not reintroduce that hook as a fresh mystery/conflict unless the user explicitly asks or a later session-canon event reopens it.

Later, this can move to a dedicated table:

```text
memory_arc_state_rows:
- sessionId
- arcId
- title
- status
- summary
- entitiesJson
- topicsJson
- doNotReopen
- cardOverride
- sourceMessageId
- sourceHash
- updatedAt
```

### World State

World state stores compact current truth about the world that is broader than a single entity or relationship.

MVP storage can use `tracker_rows` with namespaced keys:

```text
world:night_city.net_hunters = active threat; dangerous if targets stop moving
world:date = 16-01-2077
world:time = 00:48
world:location = Watson streets, on Yaiba Kusanagi
```

World state should remain compact. Durable world rules or discoveries that matter outside the current scene can also be written to MemoryBook.

### Growth Control

To avoid unbounded DB growth:

- Canonicalize entity names and aliases before writing state. `Lucyna Kushinada`, `Lucy`, and `Люси` should resolve to one entity id.
- Upsert entity/relationship state by stable key. Do not append a new state row every turn.
- Upsert arc/world state by stable key. Do not append a new arc/world row every turn.
- Only write state when the new value materially changes the prior value.
- Cap each state field by characters and fact count.
- Keep micro-continuity out of durable state unless it becomes important.
- Archive or ignore inactive low-salience entities when they have not appeared for a long span.
- Prefer updating one compact relationship summary over accumulating many near-duplicate facts.
- Prefer updating one compact arc status/summary over accumulating long summaries of the same arc.

Durable historical events may still go to MemoryBook, but only when they are future-relevant enough to justify retrieval.

### Raw Recall

Raw recalled messages remain a fallback for exact old chat fragments. They are not the source of canonical entity truth.

## Authority Rule

Prompt instructions should make this explicit:

```text
Character cards describe baseline/default traits and initial conditions.
MemoryBook entries, Studio Ledger state, entity state, relationship state, arc state, world state, trackers, and visible chat are session canon.
When session canon conflicts with card baseline, follow session canon.
If a card hook is marked completed/resolved in session canon, treat the card hook as backstory, not an active unresolved arc.
```

Example:

```text
Card: Lucy is cold to newcomers.
Memory: Danvi is no longer a newcomer to Lucy.
Result: Lucy remains guarded, but does not reset to stranger-mode.
```

Example:

```text
Card: Lucy hides her role in David's fate.
Arc state: David's fate revelation is completed; Danvi knows Lucy's role.
Result: The story may reference the resolved conversation, but must not replay it as an undiscovered secret.
```

## What Goes Into MemoryBook

Write durable, future-relevant facts:

- Relationship changes.
- Trust, hostility, familiarity, boundaries.
- NPC knowledge and beliefs.
- Promises, debts, obligations.
- Secrets revealed.
- Durable world rules.
- Important item ownership or meaning.
- Facts that override card baseline.

Do not write temporary micro-details unless they become durable:

- Exact hand placement.
- Current pose.
- Current speed.
- Wet sleeve.
- Transient expression.
- Short-lived staging details.

These stay in the visible ledger for near-term continuity.

### MemoryBook Schema MVP

Do not add new `MemoryEntry` fields for the first Studio Ledger implementation unless implementation proves they are necessary.

Use existing fields:

```text
kind = studio_ledger
source = studio_ledger
importance = <ledger-assigned importance>
keys = entity/topic trigger keys
messageIds = final assistant message id
messageRange = final assistant message range when available
sourceHash = normalized fact hash for dedupe
```

Existing `memory_catalog_rows` and `memory_entity_rows` already provide normalized metadata such as entities, topics, locations, aliases, facts, salience, and mention counts. Prefer writing/refreshing those indexes over expanding `MemoryEntry` prematurely.

Possible later `MemoryEntry` fields, only if needed:

```text
entities
topics
locations
canonicalKey
lastMentionedAt
```

If the data describes current entity/relationship truth rather than a durable fact, put it in entity/relationship state instead of MemoryBook.

## Suggested Ledger Output

The Studio Ledger should request both a visible ledger and a machine-readable export.

Visible block:

```xml
<studio_ledger>
...
</studio_ledger>
```

Machine export:

```xml
<glaze_memory_export>
{
  "sceneState": {
    "time": "00:48",
    "date": "16-01-2077",
    "location": "Watson streets, on Yaiba Kusanagi",
    "immediateThread": "Lucy and Danvi are riding without a destination.",
    "activeTensions": [
      "Net hunters are still dangerous if they stop.",
      "Lucy threatened to burn Danvi's optics if he endangers her."
    ]
  },
  "entities": [
    {
      "name": "Lucyna Kushinada",
      "aliases": ["Lucy", "Люси"],
      "type": "npc",
      "relationshipToUser": "fragile alliance; wary but engaged",
      "attitudeToUser": "familiar, not random newcomer",
      "knowledge": [
        "Danvi knows about her role in David's fate"
      ],
      "boundaries": [
        "Will retaliate if Danvi endangers her"
      ],
      "durableFacts": [
        "Lucy accepted a shared ride with Danvi as a practical alliance."
      ],
      "cardOverrides": [
        "Do not treat Danvi as a random newcomer to Lucy."
      ]
    }
  ],
  "arcState": [
    {
      "id": "david_fate",
      "title": "David's fate revelation",
      "status": "completed",
      "summary": "Danvi knows Lucy's role in David's fate.",
      "doNotReopen": true,
      "cardOverride": "Treat David's fate as resolved backstory, not an active hidden secret.",
      "entities": ["Lucyna Kushinada", "Danvi", "David"]
    },
    {
      "id": "net_hunters",
      "title": "Net hunters threat",
      "status": "active",
      "summary": "Net hunters remain dangerous if Lucy and Danvi stop moving.",
      "doNotReopen": false,
      "entities": ["Lucyna Kushinada", "Danvi"]
    }
  ],
  "durableFacts": [
    {
      "title": "Lucy accepts fragile alliance with Danvi",
      "content": "Lucy accepted a shared ride with Danvi despite distrust. She treats him as risky but familiar, not as a random newcomer.",
      "keys": ["Lucy", "Danvi", "alliance", "trust"],
      "entities": ["Lucyna Kushinada", "Danvi"]
    }
  ]
}
</glaze_memory_export>
```

## Pipeline Placement

After final assistant text is settled:

1. Assistant response is saved.
2. POST-cleaner/audit runs if enabled.
3. Studio Ledger runs on the final cleaned text.
4. Visible ledger is stored.
5. Memory export is parsed.
6. Durable facts are written to MemoryBook.
7. Entity, relationship, arc, world, and scene state is written to tracker namespace.

Ledger must not run on pre-cleaner text.

## Persistence MVP

### Visible Ledger

Store as an internal ledger/state row. It may reuse `info_blocks` persistence only if it is explicitly excluded from user ExtBlock injection and normal chat display:

```text
blockName = studio_ledger
blockType = infoblock
internal = true
injectAsExtBlock = false
```

Bind it to the final canonical assistant message/swipe/agentSwipe.

Ledger rows are diagnostics and near-term continuity snapshots. They are not chat messages.

### Durable Facts

Write to MemoryBook via existing repository methods.

Use basic dedupe:

- Normalize title/content/entity/keys.
- Append only genuinely new facts to matching entries.
- Avoid creating a new entry every turn for the same relationship state.

### Entity State

Use `tracker_rows` namespace for MVP.

Examples:

```text
npc:Lucyna Kushinada.relationship_to_user = fragile alliance
npc:Lucyna Kushinada.attitude_to_user = wary but familiar
npc:Lucyna Kushinada.card_overrides = Danvi is no longer a random newcomer to Lucy
```

Use upsert semantics for `(sessionId, name)`. This keeps one current value per state key.

### Relationship State

Use `tracker_rows` namespace for MVP.

Examples:

```text
relationship:Danvi:Lucyna Kushinada.relationship = fragile alliance
relationship:Danvi:Lucyna Kushinada.attitude = wary but familiar
relationship:Danvi:Lucyna Kushinada.knowledge = Danvi knows Lucy's role in David's fate
```

Use stable canonical subject/object names so aliases do not create duplicate rows.

### Arc State

Use `tracker_rows` namespace for MVP.

Examples:

```text
arc:david_fate.status = completed
arc:david_fate.summary = Danvi knows Lucy's role in David's fate.
arc:david_fate.do_not_reopen = true
arc:david_fate.card_override = Treat David's fate as resolved backstory, not an active hidden secret.
```

Use stable arc ids. Arc ids can be generated from title/entities/topics when first discovered, then reused by later ledger passes.

### World State

Use `tracker_rows` namespace for MVP.

Examples:

```text
world:location = Watson streets, on Yaiba Kusanagi
world:active_threats = Net hunters remain dangerous if Lucy and Danvi stop moving.
world:date = 16-01-2077
world:time = 00:48
```

## Prompt Injection

Future Studio prompt assembly should inject:

1. Latest Studio Ledger for near-term scene continuity.
2. Entity state for mentioned entities.
3. Relationship state for mentioned entity pairs.
4. Arc state for mentioned entities/topics and for card hooks it overrides.
5. World/scene state relevant to the current scene.
6. Normal MemoryBook selected chunks.
7. Raw recalled messages as backup.

This injection is hidden/system prompt context only. Studio Ledger must not appear as an assistant/user chat message and must not be injected through the normal user ExtBlock path.

Minimum injected block:

```xml
<studio_session_state>
These are established facts from this chat. They override character-card baseline when conflicting.

Lucyna Kushinada:
- relationship_to_user: fragile alliance
- attitude_to_user: wary but familiar
- known_fact: Danvi knows her role in David's fate
- override: Danvi is no longer a random newcomer to Lucy

Resolved arcs:
- David's fate revelation is completed. Danvi knows Lucy's role. Treat card hooks about this as backstory, not an unresolved secret.
</studio_session_state>
```

Mentioned entity detection MVP:

- Scan latest user message and recent visible context.
- Match names/aliases from entity state keys and MemoryBook/entity rows.
- If `Lucy` / `Люси` is mentioned, inject Lucy state deterministically.
- If a card hook references an arc that session canon marks completed/resolved, inject that arc override deterministically even if vector recall is empty.
- Do not rely only on vector search.

### `{{arc}}` Macro

The `{{arc}}` macro can be reused as the user-facing injection slot for relevant arc state, but its backing data should change.

Do not keep `{{arc}}` tied to the old consolidation summary rows. The macro should render selected `arc:*` state from Studio Canon State:

```xml
<arc_state>
Session canon overrides character-card baseline when conflicting.

Completed/resolved:
- David's fate revelation is completed. Danvi knows Lucy's role. Treat card hooks about this as backstory, not an unresolved secret.

Active:
- Net hunters remain dangerous if Lucy and Danvi stop moving.
- Lucy and Danvi's fragile alliance is ongoing.
</arc_state>
```

Selection rules:

- Inject arcs linked to entities/topics mentioned in the latest user message or recent visible context.
- Inject arcs that override card hooks present in the active character card.
- Prefer active arcs and completed arcs with `do_not_reopen = true`.
- Omit unrelated completed arcs unless they are needed to prevent card-baseline regression.

This keeps `{{arc}}` useful for presets while changing it from fuzzy consolidation into compact canon-state injection.

## User ExtBlocks

User ExtBlocks remain useful for:

- Custom HUD.
- Custom trackers.
- Slice-of-life state.
- Quests if desired.
- Persona stats if desired.
- Combat if desired.
- Custom visual panels.

Studio Ledger should not depend on them.

Studio Ledger output must not be emitted into the visible chat transcript. It can be shown in diagnostics/panels, but the chat history remains only normal user/assistant messages.

Later, the latest user ExtBlock outputs can be passed into Studio Ledger as auxiliary input, but they are not required for MVP.

## Failure Behavior

- Ledger failure must not fail chat generation.
- If ledger fails, keep the previous ledger.
- Do not write empty memory.
- If export parsing fails, store visible ledger if useful and skip memory writes.
- Stop/cancel should cancel ledger if it is still running.

## Suggested Prompt For Ledger

```text
You are Studio Ledger, an internal continuity/state extractor.
You do not write story prose.
You maintain session-canon facts for future generations.

Use the final assistant response, latest user message, previous ledger, recent chat, current MemoryBook facts, and current entity state.

Rules:
- Preserve prior state unless contradicted.
- Promote only durable facts into durableFacts.
- Temporary posture/outfit/props stay in visible ledger unless they became important.
- Do not create quests unless an explicit task/goal exists.
- Do not create persona stats unless already tracked by the user.
- Do not infer romance/trust jumps without evidence.
- Session state overrides character-card baseline.
- If an arc from the card is resolved in session canon, mark it as resolved backstory instead of active conflict.
- Never write future events as facts.
- Pending user choices are hooks, not completed events.
- Return <studio_ledger> plus <glaze_memory_export> JSON.
- Keep entity/relationship/arc/world state compact. Update current truth; do not create a history log.
- Never output ledger text as story prose or a chat message.
```

## Implementation Steps

1. Add `StudioLedgerService`.
2. Add ledger prompt constant.
3. Add parser for `<glaze_memory_export>`.
4. Add method to store visible `studio_ledger` as `InfoBlock`.
5. Add MemoryBook apply logic with dedupe.
6. Add tracker namespace upserts for entity, relationship, arc, world, and scene state.
7. Hook service into Studio generation pipeline after final cleaned text.
8. Inject latest ledger and mentioned-entity state into future Studio prompts.
9. Add tests.
10. Run targeted analyze/tests.

## Files To Inspect First

- `lib/features/chat/services/generation_pipeline.dart`
- `lib/features/chat/state/post_cleaner_state_provider.dart`
- `lib/features/chat/widgets/studio_status_card.dart`
- `lib/core/db/repositories/memory_book_repo.dart`
- `lib/core/db/repositories/tracker_repo.dart`
- `lib/core/db/repositories/info_blocks_repository.dart`
- `lib/features/extensions/models/info_block.dart`
- `lib/features/extensions/services/info_block_service.dart`
- `lib/features/extensions/services/ext_blocks_prompt_injection.dart`
- `lib/core/llm/prompt_payload_builder.dart`
- `lib/core/llm/prompt_builder.dart`
- `lib/core/llm/studio_prompt_text.dart`

## Required Tests

1. Ledger parser extracts valid JSON from `<glaze_memory_export>`.
2. Malformed export does not crash generation.
3. Durable facts write to MemoryBook.
4. Repeated durable facts are deduped.
5. Entity state writes `npc:*` tracker rows.
6. Relationship state writes `relationship:*` tracker rows with upsert semantics.
7. Arc state writes `arc:*` tracker rows with upsert semantics.
8. Mentioning Lucy after many unrelated messages injects Lucy entity state even if vector recall is empty.
9. A completed card hook is injected as resolved backstory and not active conflict.
10. Prompt contains the session-canon-overrides-card-baseline rule.
11. Ledger failure does not fail generation.
12. Ledger receives cleaned final text, not pre-cleaner text.

## Verification Commands

Use the full Flutter path if needed:

```powershell
& "Z:\GlazeProject\flutter\bin\dart.bat" format <touched files>
& "Z:\GlazeProject\flutter\bin\flutter.bat" analyze <touched files>
& "Z:\GlazeProject\flutter\bin\flutter.bat" test <new/affected tests>
```

Do not run `flutter run`.
