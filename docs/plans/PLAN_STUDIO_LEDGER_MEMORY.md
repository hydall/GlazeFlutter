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
- Studio Canon State must be swipe-scoped and rollback-safe.
- User corrections and field locks have higher authority than model-written canon state.
- User InfBlocks are visible in panels by default, but are not injected into main generation unless the user explicitly opts in.
- If the user attempts to enable user InfBlock prompt injection while Studio Canon is enabled, show a fullscreen warning that this is not recommended.
- Image generation services and JS runner flows remain allowed; the restriction is about injecting user InfBlocks as prompt context.
- All LLM models used by Studio and post-processing must be configured inside Studio/Post-Building settings, except embedding models.
- Embedding model settings remain in the embedding/vector settings area because they are shared infrastructure for MemoryBook, Lorebook, and raw recall vectors.

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
    "presentEntities": [
      {
        "name": "Lucyna Kushinada",
        "status": "present",
        "confidence": "high"
      },
      {
        "name": "David Martinez",
        "status": "absent_backstory",
        "reason": "Dead/backstory figure; mentioned through memory, not physically present."
      }
    ],
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
  ],
  "ops": [
    {
      "op": "set",
      "key": "arc:david_fate.status",
      "value": "completed",
      "evidence": "Danvi knows Lucy's role in David's fate.",
      "eventState": "completed"
    },
    {
      "op": "append_unique",
      "key": "npc:Lucyna Kushinada.knowledge",
      "value": "Danvi knows Lucy's role in David's fate.",
      "evidence": "The final assistant response treats the revelation as known.",
      "eventState": "completed"
    },
    {
      "op": "set",
      "key": "scene.present_entities",
      "value": "Lucyna Kushinada is present; David Martinez is absent/backstory.",
      "evidence": "Lucy is in the current scene; David is only referenced as past context.",
      "eventState": "completed"
    }
  ]
}
</glaze_memory_export>
```

The structured `ops` list is the authoritative machine export for state writes. Full objects such as `sceneState`, `entities`, and `arcState` are useful for diagnostics and prompt readability, but persistence should prefer validated patch operations so the model cannot accidentally rewrite or drop the whole state tree.

## Pipeline Placement

After final assistant text is settled:

1. Assistant response is saved.
2. POST-cleaner/audit runs if enabled.
3. User auto InfBlocks run if they are configured to auto-run.
4. Studio Ledger runs on the final cleaned text plus user auto InfBlocks as auxiliary evidence.
5. Visible ledger is stored as internal diagnostics.
6. Memory export is parsed and validated.
7. Durable facts are written to MemoryBook.
8. Entity, relationship, arc, world, and scene state is written to tracker namespace.

Ledger must not run on pre-cleaner text.

If user InfBlocks are manual-only, Studio Ledger does not wait for them. It runs immediately after the final cleaned text is available. Manual image generation and manual JS runner flows must not delay canon state writes.

User InfBlocks are auxiliary evidence only. Studio Ledger can read them, but must not promote their contents to canon unless supported by the final assistant text, visible accepted chat, or existing canon.

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

### Snapshots, Swipes, and Rollback

Studio Canon State must be scoped to the same coordinates as accepted assistant output:

```text
sessionId
messageId
swipeId
agentSwipeId
committed
```

Rules:

- State derived from an assistant response is tentative until the user sends the next message or the app otherwise marks that swipe path as accepted.
- Effective canon for generation uses the latest committed state on the selected swipe path.
- If a message, swipe, or agent swipe is deleted/rejected/regenerated, state sourced from it must be removed or ignored.
- Branching a session copies only state sourced from messages included in the branch prefix.
- Manually curated MemoryBook entries without a source message can be copied across branches; model-written entries should remain source-bound.

Every state write and durable MemoryBook write produced by Studio Ledger should include provenance:

```text
sourceMessageId
sourceSwipeId
sourceAgentSwipeId
sourceHash
writer = studio_ledger
createdAt
updatedAt
confidence
```

Without provenance, rollback, debugging, and stale-state pruning are not reliable.

### Manual Overrides and Locks

User corrections must have higher authority than model-written Studio Canon State.

MVP storage can use `tracker_rows` namespace:

```text
canon:npc:Lucyna Kushinada.attitude = wary but familiar
canon_override:npc:Lucyna Kushinada.attitude = hostile; user-corrected
canon_lock:npc:Lucyna Kushinada.attitude = true
```

Effective value rules:

- If `canon_lock:* = true`, Studio Ledger must not update that state key.
- If `canon_override:*` exists, prompt assembly uses the override value.
- `Reset` removes the override and lock, returning control to model-written canon.
- UI should expose edit, lock, unlock, reset, delete, and source-message navigation.

Later, move this to a dedicated override table:

```text
canon_state_overrides:
- sessionId
- stateKey
- overrideValue
- locked
- scope
- updatedAt
```

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

### Present Characters

Scene state must include physically/virtually present entities. Mentioned in memory or backstory is not the same as present.

MVP storage can use `tracker_rows` namespace:

```text
scene.present_entities = Lucyna Kushinada
scene.absent_backstory_entities = David Martinez
```

Prompt injection should make presence explicit:

```text
Present now:
- Lucyna Kushinada

Absent/backstory:
- David Martinez

Do not give dialogue/actions to absent characters unless through memory, call, message, hallucination, recording, or explicit scene entry.
```

Ledger prompt rules:

- Do not mark a character absent unless they explicitly leave, die, are left behind, or the scene changes.
- Do not mark a character present only because they are mentioned.
- If uncertain, preserve previous presence state.

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

### Prompt Budget

Prompt assembly should use a priority-based budget allocator, not independent per-feature limits.

Priority tiers:

```text
Tier 0: hard system and preset instructions
Tier 1: safety, role, and user-agency constraints
Tier 2: manual overrides and locked canon values
Tier 3: session canon conflict overrides
Tier 4: active scene/entity/relationship/arc/world state
Tier 5: character card and scenario baseline
Tier 6: MemoryBook durable facts
Tier 7: raw recalled messages
Tier 8: optional user InfBlocks explicitly opted into prompt injection
```

Budget rules:

- Never trim manual overrides, locks, or conflict-preventing canon overrides before raw recall or optional InfBlocks.
- Raw recall and optional user InfBlocks are trimmed first.
- Completed arcs are injected only when mentioned, linked to current entities/topics, or needed to suppress a card-baseline regression.
- `{{arc}}` should have a small bounded budget and render compact arc state, not full history.
- Reserve response output budget before packing optional context.

### Prompt Dedupe

Before rendering prompt context, normalize candidate facts into `CanonClaim` objects:

```text
subject
predicate
object
scope
priority
source
hash
```

Dedupe rules:

- Canonicalize aliases before hashing.
- Normalize case, whitespace, and punctuation noise.
- If duplicate claims exist, keep the highest-authority source.
- If a lower-authority source adds useful evidence, keep it as provenance, not repeated prose.
- Suppress raw recall snippets when their only useful fact is already present in canon state or MemoryBook.

Authority for duplicate claims:

```text
manual override > committed canon state > MemoryBook > card baseline > raw recall > user InfBlock
```

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

User InfBlocks should be visible in panels by default, but not injected into main generation unless the user explicitly opts in.

If Studio Canon is enabled and the user attempts to enable user InfBlock prompt injection, show a fullscreen warning before allowing it:

```text
Not recommended with Studio Canon

User InfBlocks can conflict with Studio Canon State and may cause duplicated, stale, or lower-authority facts to enter the prompt. Studio Canon already tracks scene, entity, relationship, arc, and world state.

Recommended: keep user InfBlocks visible in panels only.

Allowed alternatives: image generation services, JS runner tools, and manual panel workflows.

Continue anyway?
```

If the user confirms, inject user InfBlocks only as low-authority hints. They must never outrank Studio Canon State.

The latest user InfBlock outputs can be passed into Studio Ledger as auxiliary evidence, but Studio Ledger must not blindly persist them. It should promote a fact only when supported by final assistant text, visible accepted chat, or existing canon.

Image generation services and JS runner flows remain allowed. The restriction is specifically about prompt injection of user InfBlocks as context.

## Failure Behavior

- Ledger failure must not fail chat generation.
- If ledger fails, keep the previous ledger.
- Do not write empty memory.
- If export parsing fails, store visible ledger if useful and skip memory writes.
- Stop/cancel should cancel ledger if it is still running.
- If the user sends the next message before Ledger finishes, the next generation may wait briefly for the pending Ledger. If it times out, use the previous committed canon.
- A late Ledger result may apply only if its source message/swipe/agentSwipe is still current and valid.
- Malformed or rejected Ledger output is stored only as diagnostics, not applied to MemoryBook or canon state.

## Validation

Studio Ledger output must be treated as untrusted model output until parsed and validated.

Validation rules:

- Reject unknown operations.
- Reject unknown namespaces.
- Reject overlong values or trim them deterministically.
- Reject malformed JSON.
- Reject future facts.
- Reject completion of user actions, choices, threats, plans, or offers without evidence in accepted chat.
- Skip locked fields.
- Ignore empty exports.
- Quarantine bad exports as diagnostics only.

Event state values:

```text
planned
suggested
threatened
attempted
completed
failed
cancelled
unknown
```

Threats, plans, questions, offers, and pending user choices must not be promoted into completed facts.

## Vector Rebuilds

Studio memory depends on vectors from multiple sources. Users need a rebuild control for:

- Chat raw recall vectors.
- MemoryBook vectors.
- Lorebook vectors.

Rebuild UI should support:

- Rebuild all or selected storage.
- Vectors-per-minute rate limit.
- Batch size.
- Pause/resume.
- Cancel.
- Progress and failed item count.
- Provider/profile selection where applicable.

When embedding model or dimensionality changes:

- Mark old vectors stale or skip them during retrieval.
- Do not mix incompatible vector dimensions.
- Offer rebuild before vector search is considered healthy again.

## Model Settings

All LLM model settings required by Studio and post-processing should live inside Studio/Post-Building configuration. Do not require users to hunt through unrelated app settings for Studio agents, cleaner, auditor, classifier, ledger, or write-loop models.

Exception: embedding models. Embeddings are shared vector infrastructure for MemoryBook, Lorebook, and raw chat recall, so embedding configuration stays in the embedding/vector settings area.

Every model field must have helper text that explains:

- What the model is used for.
- Whether a cheaper/smaller model is acceptable.
- What quality problems happen if the model is too weak.
- Whether the field inherits the active chat model when empty.
- Which timeout/token settings apply.

Recommended model quality guidance:

```text
Main responder: strong model recommended; drives final prose and character behavior.
Studio planner/controller: strong or medium model recommended; weak models may create bad briefs and user-agency violations.
Beauty/scene extractors: cheap or medium model acceptable if output is structured and validated.
Classifier: cheap model acceptable; failure should degrade gracefully.
POST-cleaner: medium or strong model recommended; weak models may flatten style or miss continuity issues.
Character auditor/fact checker: cheap or medium model acceptable for simple issue extraction, but weak models may miss subtle card violations.
Studio Ledger: medium model recommended; cheap model may be acceptable only if strict schema validation catches bad output.
Memory write-loop/durable fact extractor: medium model recommended; weak models may hallucinate durable facts.
Embedding model: configured separately; choose by retrieval quality/cost and provider rate limits.
```

Fields that should exist or be reviewed in Studio/Post-Building settings:

```text
Studio section:
- Main responder model/source/endpoint/key if Studio allows an override.
- Shared tracker/controller model/source/endpoint/key.
- Optional per-agent model only if the UI has a concrete use case; otherwise avoid per-shard model sprawl.
- Studio Ledger model/source/endpoint/key.
- Studio Ledger timeout.
- Studio Ledger max tokens.
- Studio Ledger temperature.

Post-Building section:
- POST-cleaner model/source/endpoint/key.
- POST-cleaner timeout/max tokens/temperature.
- Character auditor/fact-checker model/source/endpoint/key.
- Character auditor/fact-checker timeout/max tokens/temperature.
- Classifier model/source/endpoint/key.
- Classifier timeout/max tokens/temperature.
- Memory write-loop model/source/endpoint/key.
- Memory write-loop timeout/max tokens/temperature.

Embedding/vector settings:
- Embedding provider/profile/source.
- Embedding endpoint/key/model.
- Embedding dimensions when provider exposes them.
- Vectors-per-minute rebuild rate limit.
- Rebuild batch size.
```

Helper text examples:

```text
Studio Ledger model:
Extracts compact canon state after each final assistant response. Medium models are recommended. Cheap models may work, but bad output will be rejected by schema validation and may reduce continuity.

Character auditor model:
Checks whether the final response violates character card, session canon, or relationship state before cleaner runs. Cheap or medium models are usually acceptable; stronger models catch subtler violations.

POST-cleaner model:
Applies issue fixes to the final assistant response while preserving style and meaning. Medium/strong models are recommended; weak models can flatten prose or introduce drift.

Classifier model:
Classifies generation outcome and routing signals. Cheap models are acceptable because failures should degrade gracefully.

Embedding model:
Used to build vectors for MemoryBook, Lorebook, and raw chat recall. Configure rate limits carefully; changing model/dimensions may require vector rebuild.
```

## Model Cadence

Not every Studio/post-processing model should run every turn. Users need explicit cadence controls so they can trade continuity quality, latency, and cost.

Cadence modes:

```text
every_turn
conditional
interval
manual
disabled
```

Recommended defaults:

```text
Main responder: every_turn, required.
Studio planner/controller: every_turn while Studio is enabled.
Beauty/scene extractors: every_turn only when the feature is enabled; cheap/medium model acceptable.
POST-cleaner: conditional; run only when enabled and response needs post-processing.
Character auditor/fact checker: conditional; run only when cleaner/audit is enabled, before cleaner.
Classifier: conditional or disabled by default unless needed for routing/recovery.
Studio Ledger: every_turn while Studio Canon is enabled; can degrade to interval for low-power mode, but continuity quality will suffer.
Memory write-loop/durable fact extractor: conditional or interval; run when durable changes are likely, or every N assistant turns.
Raw recall embedding: background/read-behind, not blocking every turn.
Vector rebuild: manual/background queue with rate limit.
User auto InfBlocks: user-configured; auto blocks run before Studio Ledger, manual blocks do not block Ledger.
```

User-facing cadence settings should be available per component:

```text
Enabled
Run mode: every turn / conditional / every N assistant turns / manual / disabled
Interval N turns
Run only when mentioned entities changed
Run only when scene changed
Run only when MemoryBook candidates exist
Run in background when possible
Block next generation until complete: yes/no
Timeout
Max tokens
Model/source/endpoint/key
```

Safety rules:

- Required Studio components should not be silently disabled by unrelated toggles.
- If Studio Ledger is set to interval/manual, UI must warn that long-term continuity and card-hook suppression may be weaker.
- If a model is skipped this turn, prompt assembly must use the last committed valid state.
- Late background results may apply only if their source message/swipe/agentSwipe is still current.
- Conditional skips must be deterministic and explainable in diagnostics.

Conditional trigger examples:

```text
POST-cleaner:
- Run when cleaner is enabled.
- Run when auditor reports issues.
- Run when response contains banned words/style violations.

Character auditor:
- Run when audit is enabled.
- Run when mentioned character/card hooks overlap with generated response.

Studio Ledger:
- Default every turn.
- Optional conditional low-power mode: run when assistant response mentions tracked entities, changes scene/location/time, resolves/reopens an arc, changes relationship state, reveals a secret, creates durable world facts, or contains promises/debts/threats.

Memory write-loop:
- Run when Ledger emits durableFacts.
- Run every N assistant turns as backup.
- Skip when no durable facts or state changes are detected.

Raw recall embedding:
- Run in read-behind background after enough eligible messages exist.
- Skip recent active-window messages.
```

Diagnostics should show why a component ran or skipped:

```text
Studio Ledger: ran, every_turn
Memory write-loop: skipped, no durableFacts
Classifier: disabled
Raw recall embedding: queued, 12 vectors remaining, rate limit 30/min
User InfBlocks: manual-only, not waited for
```

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
- Do not convert threats, plans, questions, offers, or pending choices into completed facts.
- Distinguish planned, suggested, threatened, attempted, completed, failed, cancelled, and unknown event states.
- Do not mark an entity present only because it is mentioned.
- Do not mark an entity absent unless it explicitly leaves, dies, is left behind, or the scene changes.
- User InfBlocks are untrusted auxiliary evidence. Do not persist their contents unless supported by final assistant text, visible accepted chat, or existing canon.
- Return <studio_ledger> plus <glaze_memory_export> JSON.
- Prefer patch operations in `ops` for persistence. Do not rewrite the whole world state.
- Keep entity/relationship/arc/world state compact. Update current truth; do not create a history log.
- Never output ledger text as story prose or a chat message.
```

## Implementation Steps

1. Add `StudioLedgerService`.
2. Add ledger prompt constant.
3. Add parser for `<glaze_memory_export>`.
4. Add strict validation for patch operations, namespaces, event states, value caps, and locks.
5. Add method to store visible `studio_ledger` as internal diagnostics.
6. Add MemoryBook apply logic with dedupe and provenance.
7. Add tracker namespace upserts for entity, relationship, arc, world, and scene state.
8. Add manual override/lock handling.
9. Hook service into Studio generation pipeline after final cleaned text and auto user InfBlocks.
10. Inject latest committed canon state into future Studio prompts.
11. Add prompt budget allocator and fact dedupe.
12. Add safe user InfBlock injection settings and fullscreen warning.
13. Add vector rebuild controls with rate limit.
14. Add diagnostics UI in tracker/canon menu.
15. Add tests.
16. Run targeted analyze/tests.

## Files To Inspect First

- `lib/features/chat/services/generation_pipeline.dart`
- `lib/features/chat/state/post_cleaner_state_provider.dart`
- `lib/features/chat/widgets/studio_status_card.dart`
- `lib/core/db/repositories/memory_book_repo.dart`
- `lib/core/db/repositories/tracker_repo.dart`
- `lib/core/db/repositories/info_blocks_repository.dart`
- `lib/core/db/repositories/tracker_snapshot_repo.dart`
- `lib/core/llm/message_recall_service.dart`
- `lib/core/llm/chat_message_embedding_service.dart`
- `lib/core/llm/memory_injection_service.dart`
- `lib/core/llm/prompt_payload_builder.dart`
- `lib/core/llm/prompt_builder.dart`
- `lib/features/extensions/models/info_block.dart`
- `lib/features/extensions/services/info_block_service.dart`
- `lib/features/extensions/services/ext_blocks_prompt_injection.dart`
- `lib/core/llm/studio_prompt_text.dart`
- `lib/features/chat/widgets/post_building_menu_dialog.dart`
- `lib/features/chat/widgets/magic_drawer.dart`
- `lib/features/chat/widgets/tracker_panel.dart`

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
13. Rejected/regenerated swipe state is not effective canon.
14. Deleted source message prunes or invalidates Studio Ledger state and model-written MemoryBook facts.
15. Manual lock prevents Ledger from updating a state key.
16. Manual override outranks model-written canon in prompt assembly.
17. Prompt budget trims raw recall/user InfBlocks before conflict-preventing canon overrides.
18. Prompt dedupe renders duplicate canon facts only once.
19. User InfBlocks are panel-visible but not injected by default when Studio Canon is enabled.
20. Enabling user InfBlock prompt injection under Studio Canon shows a fullscreen warning.
21. Present/absent entities are injected and absent characters are not treated as physically present.
22. Vector rebuild marks incompatible/stale vectors and respects vectors-per-minute rate limits.

## Verification Commands

Use the full Flutter path if needed:

```powershell
& "Z:\GlazeProject\flutter\bin\dart.bat" format <touched files>
& "Z:\GlazeProject\flutter\bin\flutter.bat" analyze <touched files>
& "Z:\GlazeProject\flutter\bin\flutter.bat" test <new/affected tests>
```

Do not run `flutter run`.
