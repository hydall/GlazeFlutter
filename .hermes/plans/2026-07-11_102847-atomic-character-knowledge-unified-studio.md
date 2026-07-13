# Atomic Character State + Direct/Assisted Studio Implementation Plan

> **For Hermes:** Use test-driven-development and subagent-driven-development to implement this plan task-by-task. Do not commit or push unless the user explicitly asks.

**Goal:** Replace lossy `npc:<name>.knowledge` strings with swipe-safe, append-oriented character knowledge/development facts that prevent an NPC from reverting to the baseline card after 1,000+ messages, and ship a Direct Studio mode in which a strong final model receives one complete Loom-like preset without pre-generation controllers. Keep a two-controller Assisted mode as an optional fallback for weaker models.

**Architecture:** Keep the existing post-turn Studio Ledger call, committed tracker snapshots, MemoryBook recall, provenance anchors, and manual canon controls. Extend the ledger export with normalized character knowledge/development facts stored in a new atomic-fact table, plus an immutable per-session card-baseline record used only for versioning and optional pinning; do not add a periodic card-rewrite or session-lorebook LLM call. Treat tracker snapshots as compact current-scene state, MemoryBooks as episodic history, and the fact table as durable character delta over the selected baseline/source card. For every active NPC, inject a mandatory bounded current-state packet by entity identity; then add a smaller scene-relevant fact shortlist. Direct Studio sends this context pack plus one complete adapted Loom preset straight to FINAL, with optional post-checker and cleaner, followed by the existing Ledger extraction. Assisted Studio may run Continuity plus Scene Director before FINAL. Existing multi-agent Studio remains available only for compatibility and A/B testing.

**Tech Stack:** Flutter/Dart, Riverpod, Drift/SQLite (current schema v67), existing Studio Ledger/MemoryBook/message-recall services, existing Studio preset JSON storage, Flutter test.

---

## Reference findings and what to copy

### Marinara Engine

Source inspected at commit `f257b4b`.

- `packages/server/src/services/memory-recall.ts`
  - Useful: read-behind storage excludes messages still in the active prompt (`readBehindMessageCount`); visible material is not recalled twice.
  - Useful: all old chunks remain eligible before similarity scoring; no recency pre-cap that silently loses old-but-relevant memories.
  - Useful: chunk identity and stale-chunk pruning are deterministic.
- `packages/server/src/db/schema/chats.ts` (`memoryChunks`)
  - Useful: raw messages remain canonical while embeddings/chunks are explicitly derived and rebuildable; imported chunks retain `sourceChatId` provenance.
- `packages/server/src/services/storage/chats.storage.ts` (`invalidateMemoryChunksFrom`)
  - Useful: edit, deletion, and active-swipe changes invalidate derived recall from the changed anchor instead of leaving stale vectors live.
- `packages/server/src/services/generation/memory-recall-pack.ts`
  - Useful: recalled context has its own hard budget (`MEMORY_RECALL_CONTEXT_SHARE = 0.15`) and deterministic truncation.
- `packages/server/src/services/agents/knowledge-router.ts`
  - Useful: route over a compact catalog, then inject selected source entries verbatim instead of asking an LLM to summarize each entry.
  - Useful: keyword-activated entries survive semantic shortlist failure; candidate count is capped.
  - Do not copy for v1: an extra router LLM call. Glaze can perform entity/topic routing deterministically because character facts are already structured.
- `packages/server/src/services/agents/knowledge-retrieval.ts`
  - Useful: bounded context injection and source-entry identity.
- `packages/server/src/services/agents/agent-executor.ts`
  - Generic bounded agent execution/retry exists, but this must not be misreported as a universal Marinara guarantee: inspected character-memory and knowledge-router parsers fail soft (`[]`/`null`) on malformed JSON rather than performing fact-specific retry.
- `packages/server/src/db/schema/chats.ts` + `packages/server/src/services/storage/chats.storage.ts` (`conversationNotes`)
  - Closest useful durable-record precedent: explicit rows, source/target chat IDs, anchor message ID, stable ordering, and a bounded prompt view.
- `packages/server/src/services/conversation/character-commands.ts` + `packages/server/src/services/generation/conversation-side-effect-command-runtime.ts`
  - Cautionary counterexample: `extensions.characterMemories[]` stores only `{from, fromCharId, summary, createdAt}`, targets by normalized name, and has no fact key, source message, deduplication, correction, supersession, or retraction. Do not describe Marinara as already having atomic character facts.

### Lumiverse / Lucid Loom

Source inspected at commit `3b14103`.

- `src/services/memory-cortex/retrieval.ts`
  - Useful: structured prefilter → optional vector score → multi-signal rerank → diversity selection → entity context assembly.
  - Useful: active entities and high-salience memories are independent candidate sources.
  - Useful later, not MVP: semantic/salience/recency/emotional/entity weighted fusion.
- `src/services/memory-cortex/entity-graph.ts`
  - Useful: aliases and entity relationships make retrieval robust to name variants.
- `src/services/memory-cortex/consolidation.ts`
  - Useful only for narrative summaries: higher-tier summaries retain source IDs and ranges and do not replace raw sources.
  - Do **not** use consolidation to rewrite character knowledge. Atomic facts remain canonical; summaries are derived views.
- `src/auth/default-preset.ts`
  - Strong pattern: one concise System Prompt + Narrative Guidance + a bounded Cortex block. FINAL is treated as a writer, not as an auditor reconciling six reports.
  - Strong pattern: character voice and immediate reaction lead; style serves character and scene.
- `src/macros/definitions/loom.ts`
  - Useful: conditional compact context macros rather than unconditional prompt dumping.
- `src/services/summarization-prompts.service.ts`
  - Useful for preserving narrative arc summaries, but not a source of truth for epistemic facts.

### Deliberately rejected reference patterns

- No new per-turn LLM router.
- No LLM compaction that can delete or silently rewrite an old knowledge fact.
- No replacement of Glaze tracker snapshots with Lumiverse Cortex tables.
- No recency-only candidate truncation before relevance scoring.
- No six-controller FINAL prompt with `ESTABLISHED`, `UNKNOWN`, verification, access-category, or audit/checklist language.
- No claim that Marinara supplies fact-level supersession/retraction; those are Glaze requirements derived from the observed limitations, not copied features.

---

## Invariants

1. A committed atomic fact is never mutated in place. Corrections create a new fact with `supersedesId`; invalidation sets the old fact lifecycle to `superseded` or `retracted` while preserving the row.
2. Facts from an unaccepted swipe are `tentative` and never enter normal retrieval. They become `active` only when the matching tracker snapshot is committed.
3. Deleting/regenerating a message retracts facts anchored to that message/swipe rather than leaving false knowledge active.
4. A branch receives only facts whose source anchors exist in the branched message slice.
5. `canon_override:*` and `canon_lock:*` remain the highest-priority user-owned inputs. The new resolver must never let an LLM fact override them.
6. `tracker_snapshots` remain the compact current-state source. Long-term character knowledge is not copied back into `npc:*.knowledge`.
7. Retrieval excludes facts already represented by visible source messages, mirroring Marinara read-behind behavior.
8. Embeddings are optional enrichment, never required for correct fact retrieval.
9. The new Studio presets/modes are separate; existing/default/v1/v2 presets and disabled alternative blocks are preserved unchanged.
10. FINAL-facing text contains facts and creative direction, not controller methodology or audit vocabulary.
11. The session-start card snapshot is immutable version evidence, not an automatically edited document. Runtime may follow the current source card, pin the old baseline, or ask on source-card change.
12. A present or focal NPC receives a mandatory current-character-state packet even when semantic retrieval finds no matching MemoryBook or fact.
13. Session development overrides conflicting baseline-card traits only at the narrowest applicable scope. A relationship-specific change toward Danvi must not globally rewrite Lucy's temperament toward everyone.
14. Source-world canon stays in the card and manual lorebook. MVP does not create an automatic session lorebook or global truth table. If objective world-fact loss is later demonstrated, extend the same atomic/provenance model instead of adding a periodic prose summary.
15. Direct Studio performs zero normal pre-generation controller calls. Fact/continuity checking and cleaning are optional post-generation stages; Ledger extraction remains the existing post-turn call.

---

## Data contract

Create `CharacterKnowledgeFact` with these fields:

- `id`: stable UUID/string ID.
- `chatSessionId`: owning chat.
- `knowerKey`: stable session-scoped entity key whose epistemic state is represented; resolve card-backed characters to immutable character IDs when available and use a deterministic entity key for ad-hoc NPCs.
- `knowerName`: current display name, kept separate from identity so aliases/renames do not orphan facts.
- `subjectKey`: stable entity/topic key the knowledge or development concerns.
- `subjectName`: display label used in prompts.
- `factClass`: `knowledge`, `relationship`, `behavior_change`, `commitment`, `goal`, `persistent_condition`, or `identity_development`.
- `scopeKey`: narrow application scope such as `relationship:danvi`, `context:combat`, `context:intimacy`, or `global`; default to the narrowest defensible scope, never `global` merely for convenience.
- `predicate`: short normalized relation, e.g. `identity`, `location`, `owns`, `intends`, `betrayed`, `trusts`, `knows_about`.
- `object`: exact factual proposition value; not a generated summary of all prior knowledge.
- `epistemicState`: `observed`, `heard_claim`, `inferred`, `confirmed`, `disbelieved`, `forgotten`, or `retracted`.
- `confidence`: `0.0..1.0`.
- `importance`: `0.0..1.0`.
- `entities`: aliases/entity names participating in the fact.
- `topics`: normalized retrieval keywords.
- `sourceMessageId`, `sourceSwipeId`, `sourceAgentSwipeId`: existing provenance anchor.
- `sourceKind`: `studio_ledger`, `legacy_tracker`, or `manual`.
- `supersedesId`: nullable prior fact ID.
- `lifecycle`: `tentative`, `active`, `superseded`, or `retracted`.
- `createdAt`, `updatedAt`.

Indexes:

- `(chat_session_id, lifecycle, knower_key)`
- `(chat_session_id, lifecycle, subject_key)`
- `(chat_session_id, source_message_id, source_swipe_id, source_agent_swipe_id)`
- `(chat_session_id, supersedes_id)`

Do not put a unique constraint on `(knowerKey, subjectKey, predicate)`: two characters may hold conflicting claims, and one character may retain a history of corrected beliefs. Idempotency instead comes from a deterministic fact ID or unique source-anchor-plus-export-ordinal key, so replaying the same ledger result cannot duplicate rows.

Although the initial class name may remain `CharacterKnowledgeFact` for migration continuity, this table is the canonical atomic **character delta**, not only a list of things the NPC knows. If implementation naming can still change cleanly before code generation, prefer `CharacterStateFact` / `character_state_fact_rows`, with epistemic knowledge represented as one `factClass`.

### Session card baseline policy

Keep an immutable session-start card snapshot for reproducibility and three-way comparison, but never mutate that snapshot as RP proceeds and do not make it the only runtime card forever.

Add `CharacterSessionBaselineRows` (or equivalent session columns if Drift conventions strongly favour them):

- `chatSessionId` primary key;
- `characterId`;
- `baselineCardJson` exact session-start payload;
- `baselineHash`;
- `sourceHashLastSeen`;
- `cardUpdatePolicy`: `follow_source`, `pinned_baseline`, or `ask_on_change`;
- `createdAt`, `updatedAt`.

Effective card assembly after the source character is edited:

1. Compare current source hash with `sourceHashLastSeen`.
2. For `follow_source`, use the new source card immediately, retain the same atomic session delta, and flag only direct conflicts for review.
3. For `pinned_baseline`, continue using the immutable session-start snapshot; no RP restart is required.
4. For `ask_on_change`, show a three-way choice/diff: old baseline → new source card, with existing session delta displayed separately. Applying the new source updates `sourceHashLastSeen`, never rewrites delta facts.
5. Runtime precedence remains manual override/lock > scoped session delta > selected source-card revision > source/model fallback.

The snapshot is therefore version evidence and an optional pinned baseline—not a document that the Ledger edits line by line.

### Deferred: future session-card projection plan

The Studio/Ledger implementation must not create, render, or mutate an evolved session card. A human-facing session-card projection/rewrite remains a possible future feature and is specified separately in `.hermes/plans/2026-07-11_future-session-card-projection.md`; it is not an MVP deliverable, schema requirement, or rollout dependency for this plan.

---

## Task 1: Add the atomic fact model and Drift schema

**Objective:** Establish a normalized, queryable, provenance-preserving store without modifying existing tracker or MemoryBook tables.

**Files:**
- Create: `lib/core/models/character_knowledge_fact.dart`
- Create: `lib/core/models/character_session_baseline.dart`
- Modify: `lib/core/db/tables.dart`
- Modify: `lib/core/db/app_db.dart`
- Generated: `lib/core/db/app_db.g.dart`
- Test: `test/db_migration_test.dart`

**Steps:**

1. Add failing tests asserting the current schema exposes `character_knowledge_fact_rows`, `character_session_baseline_rows`, and all required columns/indexes.
2. Raise `schemaVersion` from 67 to 68 and register both tables in `@DriftDatabase`.
3. Add guarded `if (from < 68)` creation for both tables. Do not rewrite existing sessions/cards during schema migration; lazily create a baseline record on first session load/generation from the exact card payload then selected.
4. Add immutable Dart models and enums/string validation helpers. Keep JSON conversion explicit; do not require Freezed unless neighbouring models make it materially simpler.
5. Add baseline hashing over the canonical serialized prompt-relevant card payload, not avatar bytes or volatile UI metadata.
6. Run code generation:
   - `dart run build_runner build --delete-conflicting-outputs`
7. Run:
   - `flutter test test/db_migration_test.dart`
   - Expected: schema version 68, both tables and indexes present, v67→v68 upgrade succeeds.

**Migration safety:** use `createTable`, not a series of column additions. Update every hard-coded schema-version assertion in `test/db_migration_test.dart`.

---

## Task 2: Implement repository lifecycle and swipe-safe provenance

**Objective:** Make fact activation, correction, deletion, and branch behavior match the existing committed-snapshot semantics.

**Files:**
- Create: `lib/core/db/repositories/character_knowledge_fact_repo.dart`
- Create: `lib/core/db/repositories/character_session_baseline_repo.dart`
- Create: `lib/core/llm/knowledge/effective_character_card_resolver.dart`
- Modify: `lib/core/state/db_provider.dart`
- Test: `test/character_knowledge_fact_repo_test.dart`
- Test: `test/effective_character_card_resolver_test.dart`

**Repository API:**

- `insertTentative(fact)`
- `insertAllTentative(facts)` in one transaction
- `activateAnchor(sessionId, messageId, swipeId, agentSwipeId)`
- `retractAnchor(...)`
- `supersede(oldId, replacementFact)` in one transaction
- `getActiveForSession(sessionId)`
- `getActiveForKnowers(sessionId, knowers)`
- `getBySourceAnchor(...)`
- `copyForSessionBranch(fromSessionId, toSessionId, messageIds)`
- `deleteBySessionId(sessionId)` for hard session deletion only

**Steps:**

1. Write failing repository tests for tentative invisibility, activation, supersession, retraction, and duplicate anchor insertion.
2. Implement transactional fact methods. Re-running the same ledger anchor must replace/retract only that anchor’s tentative rows, not duplicate them.
3. Implement baseline creation and effective-card resolution tests for `follow_source`, `pinned_baseline`, and `ask_on_change`; source-card edits must never require a new chat or mutate session delta facts.
4. Test a three-way conflict: old card says “cold and distrustful,” new card changes general temperament, and session delta says “trusts Danvi.” Resolver must preserve the Danvi-scoped delta while adopting or pinning the source change according to policy.
5. Add provider wiring in `lib/core/state/db_provider.dart`.
6. Test that active queries exclude `tentative`, `superseded`, and `retracted` rows.
7. Run:
   - `flutter test test/character_knowledge_fact_repo_test.dart test/effective_character_card_resolver_test.dart`

---

## Task 3: Extend the existing Studio Ledger export; add no LLM call

**Objective:** Extract atomic epistemic facts during the existing ledger pass and persist them tentatively alongside tracker operations.

**Files:**
- Modify: `lib/core/models/studio_ledger_export.dart`
- Generated: `lib/core/models/studio_ledger_export.freezed.dart`
- Generated: `lib/core/models/studio_ledger_export.g.dart`
- Modify: `lib/core/llm/studio_ledger_export_parser.dart`
- Modify: `lib/core/llm/studio_ledger_prompt.dart`
- Modify: `lib/core/llm/studio_ledger_service.dart`
- Modify: `lib/core/llm/ledger/ledger_op_applier.dart`
- Retire: `lib/core/llm/ledger/durable_fact_writer.dart`
- Test: `test/studio_ledger_test.dart`

**Contract change:** keep `ops`, add a `knowledgeFacts` array to `<glaze_memory_export>`, and retire the unsupported `durableFacts` field.

Example shape to encode in the prompt/tests:

```json
{
  "ops": [],
  "knowledgeFacts": [
    {
      "knowerKey": "entity:lucy",
      "knowerName": "Lucy",
      "subjectKey": "entity:danvi",
      "subjectName": "Danvi",
      "predicate": "identity",
      "object": "Danvi is the Honey Badger netrunner",
      "epistemicState": "confirmed",
      "confidence": 1.0,
      "importance": 0.8,
      "entities": ["Lucy", "Danvi"],
      "topics": ["identity", "netrunner"],
      "supersedesId": null
    }
  ]
}
```

**Steps:**

1. Add parser tests for valid facts, malformed enums, empty strings, overlong fields, confidence clamping/rejection, duplicate facts in one export, and unknown supersession IDs.
2. Keep parser failure isolated: one bad knowledge fact is dropped/quarantined without discarding valid tracker ops.
3. Update the ledger prompt:
   - `npc:<name>.knowledge` is no longer a writable target for new model output.
   - Emit one proposition per fact.
   - Distinguish direct observation, heard claim, inference, confirmation, disbelief, and correction.
   - Never summarize away prior facts.
   - Use `supersedesId` only when correcting a known injected fact ID.
4. Inject current relevant fact IDs into the ledger prompt so the model can reference supersession targets; do not inject the whole database.
5. In `StudioLedgerService`, after parsed tracker ops, write `knowledgeFacts` as `tentative` using the same `(messageId, swipeId, agentSwipeId)` anchor.
6. `durableFacts` is not a supported feature: the parsed output was never written and legacy `studio_ledger` MemoryBook entries are excluded from injection. The orphaned writer and export contract were removed; keep `ops` and `knowledgeFacts` as the Ledger persistence paths.
7. Ensure cancellation/current-generation checks occur before both fact and snapshot writes.
8. Return an explicit `applied` / `skipped_locked` / `skipped_duplicate` / `rejected` result from ledger application. The current `StudioLedgerService` increments `opsApplied` even when `LedgerOpApplier` made no change; do not repeat that diagnostic bug for atomic facts, and correct the existing counter while touching this path.
9. Run:
   - `flutter test test/studio_ledger_test.dart`

---

## Task 4: Commit, regenerate, delete, clear, and branch facts with chat state

**Objective:** Prevent rejected swipes and deleted messages from becoming character memory.

**Files:**
- Modify: `lib/features/chat/chat_provider.dart`
- Modify: `lib/features/chat/chat_message_service.dart`
- Modify: `lib/features/chat/chat_session_service.dart`
- Modify: `lib/features/chat_history/chat_history_provider.dart`
- Modify: `lib/core/state/character_provider.dart`
- Test: `test/character_knowledge_lifecycle_test.dart`
- Test: `test/tracker_delete_first_message_test.dart`

**Steps:**

1. Write a failing end-to-end lifecycle test:
   - ledger emits fact on assistant swipe A → tentative and not retrievable;
   - user sends follow-up → matching snapshot and facts become active;
   - regenerate/delete assistant message → facts from removed anchor become retracted;
   - branch before source message → fact absent; branch including source message → active fact copied under new session ID.
2. Next to `trackerSnapshotRepo.commitLatest(...)` in `chat_provider.dart`, activate facts for the exact committed anchor. Do not implement a separate “latest by timestamp” guess; use the snapshot’s actual anchor.
3. On message/swipe/agent-swipe deletion, call `retractAnchor` in the same logical operation as snapshot deletion.
4. In `ChatSessionService.branchSession`, call `copyForSessionBranch` using the existing `branchedMessageIds` set.
5. In both clear-chat paths, delete session facts together with tracker rows/snapshots.
6. In session/character deletion paths, hard-delete fact rows and add sync deletion tracking once sync support exists.
7. Run lifecycle and existing tracker regression tests.

---

## Task 5: Preserve legacy `npc:<name>.knowledge` without pretending it is atomic

**Objective:** Stop future lossy writes while retaining every byte of existing user history.

**Files:**
- Create: `lib/core/llm/ledger/legacy_character_knowledge_migrator.dart`
- Modify: `lib/core/db/app_db.dart` or invoke post-open migration from the existing data-migration service
- Modify: `lib/core/llm/studio_ledger_prompt.dart`
- Modify: `lib/core/llm/prompt/studio_session_state_compiler.dart`
- Test: `test/legacy_character_knowledge_migration_test.dart`

**Migration policy:**

- For every existing tracker named `npc:<name>.knowledge` with non-empty value, create one immutable `legacy_tracker` fact:
  - `knower = <name>`
  - `subject = <name>` or `legacy_knowledge` when no subject can be determined safely
  - `predicate = legacy_snapshot`
  - `object = exact original string`
  - `epistemicState = confirmed`
  - `importance = 0.7`
  - lifecycle `active` only if sourced from the latest committed snapshot; otherwise skip/live-store fallback rules apply.
- Deduplicate via a deterministic hash of `(sessionId, trackerName, exactValue)`.
- Do not split prose with an LLM or delete the tracker during the migration.
- After verification, stop rendering `npc:*.knowledge` from trackers when an equivalent legacy fact exists. Keep the row for rollback compatibility for one release.

**Steps:**

1. Test exact Unicode/line-break preservation and idempotent re-run.
2. Test that a 2,000-character legacy string survives unchanged.
3. Test that a legacy fact participates in retrieval but is lower priority than explicit atomic facts and `canon_override:*`.
4. Update ledger prompt allowed keys so new `set npc:*.knowledge` ops are rejected.
5. Update `studio_session_state_compiler.dart` to omit long-term knowledge from the compact current-state block; mood/location/current intent remain.

---

## Task 6: Build mandatory character-state packets plus situational retrieval

**Objective:** Prevent baseline-card reversion even when MemoryBook/vector retrieval misses the decisive development, without dumping every stored fact into FINAL and without an additional inference call.

**Files:**
- Create: `lib/core/llm/knowledge/character_knowledge_router.dart`
- Create: `lib/core/llm/knowledge/character_knowledge_context_builder.dart`
- Modify: `lib/core/llm/memory_injection_service.dart`
- Modify: `lib/core/llm/prompt_builder.dart` or the existing Studio prompt assembly integration point
- Reuse: `lib/core/llm/message_recall_service.dart`
- Reuse: `lib/core/llm/memory/memory_vector_searcher.dart`
- Test: `test/character_knowledge_router_test.dart`
- Test: `test/character_knowledge_injection_test.dart`

**Two-tier selection:**

1. **Mandatory current-state packet:** for every present/focal NPC, select active relationship-to-user changes, lasting behavior changes, commitments, persistent conditions, identity development, and long-running goals by `knowerKey`, independent of semantic similarity. Mentioned but absent NPCs receive a smaller packet limited to the current subject.
2. **Situational retrieval:** add knowledge/episode-specific facts by subject/entity/topic overlap and optional embedding rerank.

The mandatory packet is a bounded projection over atomic facts, not a mutable summary and not a rewritten card. Baseline card text describes the starting/general character; packet facts override it only for their declared `scopeKey`.

**Candidate generation order:**

1. Present entities from committed scene state.
2. Names/aliases mentioned in the latest user message and recent visible turn.
3. Active focal character/card.
4. Subject/entity/topic keyword overlap.
5. High-importance facts as a small serendipity reserve.

**Filtering:**

- Session match and lifecycle `active` only.
- Exclude facts whose `sourceMessageId` is in visible message IDs.
- Resolve supersession chains; emit only the active leaf unless historical conflict is explicitly relevant.
- Exclude `forgotten`/`retracted`; represent `disbelieved` as belief state, not objective truth.
- Apply matching `canon_override:*` values last and mark locked keys as authoritative.

**Scoring for MVP (deterministic):**

- `+100` knower is present/focal.
- `+70` subject/entity exact alias match.
- `+40` topic/keyword overlap.
- `+30 * importance`.
- `+20 * confidence`.
- `+10` confirmed/observed, `+5` heard claim, `+0` inferred/disbelieved.
- Stable tie-break: source message order, then ID.

**Budget:**

- Mandatory packet for the focal/present NPC: target <= 1,200 characters, with at least one slot reserved for each applicable class among relationship-to-user, commitment, lasting behavior/condition, and long-running goal. It may not be reduced to zero by situational matches.
- Mentioned/absent NPC packet: target <= 400 characters and only facts intersecting the current subject.
- Situational facts: hard cap 12 total, normally 4 per knower, target <= 1,800 additional characters or <= 450 estimated tokens.
- Reserve two situational slots for high-importance facts only when their entities intersect the active cast/topic.
- If the mandatory packet exceeds budget, rank within fact class and scope; do not LLM-summarize or silently collapse facts into a new blob.

**Rendering:**

```text
<current_character_state character="Lucy">
Baseline rule: the card describes Lucy's starting/general disposition; the scoped developments below take precedence where they conflict.
- [relationship:danvi] Trusts Danvi and allows vulnerability with him; this does not imply generalized warmth or trust toward others.
- [commitment:danvi] Promised not to disappear without warning.
</current_character_state>
<character_knowledge>
Lucy knows:
- [confirmed] Danvi is the Honey Badger netrunner. (fact:kf_123)
- [heard claim] Claire says the chip came from Arasaka. (fact:kf_456)
</character_knowledge>
```

The fact IDs are available to the ledger/update layer but may be removed from the final prose-facing variant if they cause copying. Do not render provenance message IDs to FINAL.

**Steps:**

1. TDD tests for 1,000 old facts: a relevant old fact wins over irrelevant recent facts.
2. Test that a present NPC always receives a non-empty mandatory state packet even when all vector/topic scores are zero and no MemoryBook is selected.
3. Test scoped development: `relationship:danvi = warm/trusting` overrides a conflicting baseline only in Danvi-facing interaction and does not make Lucy warm/trusting toward Claire or strangers.
4. Test alias matching, per-knower diversity, visible-message exclusion, deterministic ordering, token/character cap, and embedding-disabled operation.
5. Test contradictory beliefs held by different knowers remain separate.
6. Test manual override precedence.
7. Inject each block once. Ensure neither is duplicated by MemoryBook recall or `<studio_session_state>`.
8. Optional phase after MVP: use existing embeddings only to rerank the deterministic situational shortlist, never to remove mandatory state or exact entity/topic matches.

---

## Task 7: Add cloud sync and backup coverage

**Objective:** Ensure durable knowledge survives device changes and does not orphan data on deletion.

**Files:**
- Modify: `lib/features/cloud_sync/sync_models.dart`
- Modify: `lib/features/cloud_sync/sync_repo_interfaces.dart`
- Modify: `lib/features/cloud_sync/sync_provider.dart`
- Modify: `lib/features/cloud_sync/services/sync_manifest.dart`
- Modify: `lib/features/cloud_sync/services/sync_engine.dart`
- Modify: `lib/features/cloud_sync/services/sync_serialization.dart`
- Create or extend adapter under: `lib/features/cloud_sync/adapters/`
- Modify backup export/import paths discovered during implementation
- Modify: `lib/core/services/backup/backup_exporter.dart`
- Test: add focused sync serialization/round-trip tests beside existing cloud-sync tests

**Steps:**

1. Add `character_knowledge` sync type keyed by session ID, parallel to `tracker_snapshot` rather than one file per fact.
2. Serialize all lifecycle/provenance/supersession fields.
3. Merge by fact ID and `updatedAt`; never reactivate a remotely retracted fact solely because another device has an older active copy.
4. Add deletion tombstones on session/character deletion.
5. Add backup import/export round-trip test with supersession chain and Cyrillic text.
6. Verify old backups without the table import cleanly.

---

## Task 8: Introduce a typed, neutral FINAL-facing brief renderer

**Objective:** Stop leaking operational/audit vocabulary while preserving internal parser safety.

**Files:**
- Create: `lib/core/llm/studio_final_brief_renderer.dart`
- Modify: `lib/core/llm/studio_prompt_text.dart`
- Modify: `lib/core/llm/studio_brief_parser.dart`
- Modify: `lib/core/llm/studio/studio_brief_macro_renderer.dart`
- Modify: `lib/core/llm/studio_stage_brief.dart` only if a typed payload is needed
- Test: `test/studio_final_brief_renderer_test.dart`
- Extend: `test/studio_brief_parser_typed_json_test.dart`
- Extend: `test/studio_prompt_filtering_test.dart`

**Design:** Keep `Focus/Constraints/Avoid/Options` as an internal compatibility format if needed, but do not concatenate it directly into FINAL. Parse into a small typed payload and render by controller role:

- Continuity → `<continuity_context>` with `Current situation`, `Character knowledge`, `Open threads`, `Do not assume`.
- Narrative/merged director → `<scene_direction>` with `Immediate beat`, `Pressure/change`, `Cast activity`, `Hand-off point`.
- Meta → existing dedicated OOC contract.
- Beauty → remains excluded from FINAL as today.

Remove the prefix `Studio agent brief:` from `StudioBriefMacroRenderer.renderBriefs`.

Also neutralize the runtime/final bridge in `studio_prompt_text.dart`: remove final-facing phrases such as “operational brief,” “analysis is already done,” “do not re-analyze,” and “hidden guidance.” The final usage note should only say that supplied scene guidance is silent context and that the model must output the RP continuation.

**Lexical boundary:** reject or translate FINAL-facing lines containing case-insensitive forms of:

- `ESTABLISHED`, `UNKNOWN`, `verification`, `verifiable`, `access category`, `audit`, `checklist`, `controller`, `source block`, `risk classification`;
- Russian equivalents: `УСТАНОВЛЕНО`, `НЕИЗВЕСТНО`, `проверяемый результат`, `категория доступа`, `аудит`, `чек-лист`, `контроллер`.

Do not silently drop the underlying fact. Translate to neutral narrative language (`Do not assume X` / `X has not been learned by Lucy`) and test the transformation.

---

## Task 9: Add Direct Studio and Assisted Studio as separate modes

**Objective:** Let strong models use the full adapted Loom-like preset and Glaze memory/post-processing without pre-generation controllers, while retaining a small assisted topology for weaker models.

**Files:**
- Modify preset seed source: `lib/core/db/app_db.dart`
- Prefer extracting large seed constants to a dedicated file if already allowed by project convention; otherwise touch only the seed list.
- Test: `test/studio_seed_blocks_test.dart`
- Test: `test/studio_prompt_filtering_test.dart`

**New presets/modes:** create separate IDs; do not overwrite `studio_normalized_v2`, `studio_normalized_v2_sol`, default, or any user preset.

- `studio_direct_loom_v1` / **Direct Loom v1**: zero pregen controllers; one complete adapted Loom-like FINAL preset; optional Meta/Lumia, fact checker, cleaner, and Beauty remain independently configurable; post-turn Ledger always remains available.
- `studio_assisted_loom_v1` / **Assisted Loom v1**: the same context pack and FINAL contract, plus only Continuity and Scene Director before FINAL.

Direct/Assisted is an execution-mode property, not inferred merely from individual block enablement. Persist it explicitly in preset metadata/model so a stale runtime agent cannot execute in Direct mode.

**Direct topology:**

- Disabled pre-generation: `continuity`, `agency`, `narrative`, `dialogue`, `guard`, `world`.
- Conditional non-planning feature: `meta`/Lumia according to its existing trigger and user toggle.
- `final`: enabled with the complete adapted Loom contract.
- Optional post-generation: fact/continuity checker, targeted correction, cleaner, Beauty-owned cleanup.
- Required post-turn: Studio Ledger for scene state and atomic character delta; outputs remain tentative until swipe commit.

**Assisted topology:**

- Enabled pre-generation:
  - `continuity`: factual current state + relevant epistemic constraints.
  - `narrative`: renamed in block text to **Scene Director**; merges beat/pacing, dialogue opportunity, living-world pressure, and stop point.
  - `meta`: preserve existing user toggle/periodic Lumia behavior.
- Disabled: `agency`, `dialogue`, `guard`, `world`.
- `beauty`: preserve the existing atomic user toggle and post-cleaner ownership; do not inject its brief into FINAL.
- `final`: enabled.

**Continuity output contract:** maximum 8 short items; only changed/relevant facts; no atmospheric prose; no labels like established/unknown; distinguish “Lucy has not learned X” from “X is false.”

**Scene Director output contract:** maximum 5 items:

1. immediate reaction/answer;
2. one concrete change or consequence;
3. optional character/world activity only when it contributes something unique;
4. dialogue/action balance stated naturally, not as a numeric audit target;
5. hand-off point.

It must not invent examples, hooks, class transitions, or ready-made dialogue beyond source instructions.

**FINAL static rules:**

- Character voice and immediate scene reaction lead.
- Never write the user’s dialogue, choices, thoughts, or unprovided actions.
- Characters act from their own knowledge; objective truth and character belief remain distinct.
- The world may move offscreen, but only scene-relevant consequences enter this reply.
- Do not recite briefs or use operational labels in prose.
- Default target is roughly 400–750 words; shorter is allowed for a genuinely clipped exchange. Do not impose a 400-word minimum or multiple conflicting paragraph bands.
- Preserve detailed drink preparation and tactile service routines when they carry character, tension, or interaction; remove only repetition or plot-displacing procedure.
- Stop at a replyable change, not an artificial “hook” slogan.

**Cleaner:** retain faithful local cleanup. The cleaner may fix direct continuity contradictions but must not receive or emit controller/audit vocabulary in the prose rewrite. Preserve Lumia OOC and formatting behavior.

**Steps:**

1. Add seed tests proving both separate presets exist and existing presets/disabled style alternatives are unchanged.
2. Add an execution test proving Direct mode invokes no pregen controller even if stale runtime agents remain enabled; it still invokes FINAL and can invoke configured post-stages/Ledger.
3. Add tests proving Assisted mode sends only Continuity + Scene Director (+ optional Meta) briefs to FINAL.
4. Add prompt-level negative assertions for all banned audit terms.
5. Assert no simultaneous contradictory length rules (`minimum 400` plus `3–4 paragraphs` plus `800–1400 words`).
6. Assert Beauty’s preset toggle disables all Beauty stages as one unit; do not regress the existing requirement.
7. Add assertions for `StudioPromptText` itself, not only seeded preset blocks: neither its runtime envelope nor final usage note may reintroduce controller names, re-analysis instructions, or hidden-guidance language.
8. Keep the post-checker off by default for the first Direct A/B. Measure whether it catches real contradictions before paying an extra per-turn call; when enabled, require `PASS` or structured violations and prohibit freeform scene rewriting.

---

## Task 10: Add representative Lucy and Project Tokyo A/B fixtures

**Objective:** Verify prompt shape and prose behavior against the two known failure modes without relying only on unit-level string checks.

**Files:**
- Create: `test/fixtures/studio_direct/lucy_scene.json`
- Create: `test/fixtures/studio_direct/project_tokyo_scene.json`
- Create: `test/studio_direct_prompt_fixture_test.dart`
- Optional developer script: `tool/studio_ab_eval.dart`

**Fixture assertions:**

### Lucy

- Claire/Lucy presence cannot be removed without an explicit exit.
- Lucy’s knowledge is retrieved as Lucy’s epistemic state, not objective omniscience.
- No `ESTABLISHED`, `UNKNOWN`, verification, or access-category language reaches FINAL.
- No six repeated summaries of the same autonomy/continuity constraint.
- Procedural barcraft remains when it is interactive and character-bearing.

### Project Tokyo

- Narrator-style card is not turned into an in-scene body.
- Scene Director can allow NPC/world activity without forcing an NPC into an isolated/private scene.
- Final prompt remains substantially smaller than the old six-controller prompt.

**A/B metrics:**

- FINAL system+brief character count and estimated tokens.
- Number of pre-generation LLM calls.
- Duplicate normalized brief bullets.
- Banned audit-term count (must be zero).
- Generated response word count target distribution (median in 400–750 for ordinary beats; not a hard universal gate).
- Manual rubric: continuity, agency, character voice, world coherence, procedural detail, replyability, controller-language leakage.

Do not make subjective prose quality a brittle unit-test pass/fail. Keep deterministic gates on prompt construction and use a recorded review sheet for generated outputs.

---

## Task 11: Rollout, observability, and rollback

**Objective:** Ship safely without risking existing chats or presets.

**Files:**
- Modify existing debug/ops log surfaces only where needed.
- Add a feature setting only if shadow rollout cannot be achieved with the new preset ID and schema lifecycle alone.

**Rollout phases:**

1. **Schema + shadow write:** create/store facts tentatively/actively, but continue using old prompt retrieval. Compare counts and anchors in debug logs.
2. **Mandatory-state shadow render:** build current-character-state packets and compare them against the card/selected MemoryBooks without injecting them.
3. **Direct read opt-in:** enable `<current_character_state>` + `<character_knowledge>` only for `studio_direct_loom_v1`; no pregen controllers.
4. **Assisted opt-in:** expose `studio_assisted_loom_v1` for models that demonstrably benefit from Continuity + Scene Director.
5. **Stop new legacy writes:** reject new `npc:*.knowledge` ledger ops after migration has been verified.
6. **Default eligibility:** offer the new presets; do not auto-switch existing chats.
7. **Cleanup in a later release:** remove legacy tracker rendering only after telemetry/tests show no unmigrated rows.

**Observability (no fact contents in logs):**

- facts parsed/written/activated/retracted;
- retrieval candidate and selected counts;
- budget truncation count;
- legacy migration row count/hash only;
- supersession-chain errors;
- FINAL brief size and banned-term rejection count.

**Rollback:**

- Switching away from `studio_direct_loom_v1` or `studio_assisted_loom_v1` restores the old execution/prompt path immediately.
- Disable new fact injection while keeping rows intact.
- Do not downgrade/drop schema table automatically.
- Old `npc:*.knowledge` rows remain available during the compatibility release.
- No rollback path may overwrite active facts with a summary string.

---

## Verification matrix

Run targeted tests after each task, then the full suite:

```bash
flutter test test/db_migration_test.dart
flutter test test/character_knowledge_fact_repo_test.dart
flutter test test/legacy_character_knowledge_migration_test.dart
flutter test test/character_knowledge_router_test.dart
flutter test test/character_knowledge_injection_test.dart
flutter test test/studio_ledger_test.dart
flutter test test/studio_prompt_filtering_test.dart
flutter test test/studio_seed_blocks_test.dart
flutter test test/studio_final_brief_renderer_test.dart
flutter test test/studio_direct_prompt_fixture_test.dart
flutter analyze
flutter test
```

Expected final state:

- all tests pass;
- generated Drift/Freezed files are current;
- no new warning from `flutter analyze`;
- working tree contains only intended implementation/test/generated changes;
- existing preset snapshots remain byte-for-byte unchanged except where schema serialization necessarily adds an absent default field.

---

## Definition of done

- A fact learned near message 10 is retrievable near message 1,010 when its entity/topic becomes relevant.
- A focal/present NPC receives a bounded current-state packet near message 1,010 even when no MemoryBook or semantic fact match fires; durable session development therefore cannot disappear behind the baseline card.
- Relationship-scoped development does not globally mutate personality: Lucy may trust Danvi while remaining cold or suspicious toward other people.
- A visible source message prevents duplicate recall of the same fact.
- Two characters can hold different beliefs about the same subject.
- Correction creates a supersession chain; the original row remains inspectable but is not normally retrieved.
- Rejected swipes, regeneration, deletion, branching, clear-chat, session deletion, backup, and sync all preserve correct lifecycle semantics.
- Manual `canon_override:*` and `canon_lock:*` beat model-written facts.
- No new `npc:<name>.knowledge` strings are written after rollout phase 3.
- `Direct Loom v1` makes zero normal pre-generation RP planning calls; configured post-checker/cleaner stages and the existing post-turn Ledger are measured separately.
- `Assisted Loom v1` makes at most two normal pre-generation RP planning calls (Continuity + Scene Director), excluding optional Meta and post-processing.
- Direct FINAL receives the full adapted Loom contract plus memory/state context, not controller briefs; Assisted FINAL receives at most one neutral continuity context and one scene direction.
- FINAL prompt has zero banned audit terms in Lucy and Project Tokyo fixtures.
- Existing presets and intentionally disabled alternatives remain untouched and selectable.

---

## Risks and explicit trade-offs

- **One new table is justified:** existing `memory_entity_rows.facts_json` is entry-derived and replace-oriented; MemoryBook entries lack epistemic/supersession fields; tracker strings are mutable. Reusing any of those as the canonical atomic store would preserve the current failure mode.
- **Prompt-only Studio cleanup is insufficient:** `StudioBriefParser` currently canonicalizes output into `Focus/Constraints/Avoid/Options`, and `StudioBriefMacroRenderer` prefixes `Studio agent brief:`. A neutral renderer boundary is necessary even with a better preset.
- **Legacy strings cannot be safely atomized deterministically:** preserve them exactly as `legacy_snapshot` rather than fabricate predicates or pay for a migration LLM call.
- **Facts can grow indefinitely:** this is intentional for correctness. Retrieval is bounded; storage pruning is out of scope. If storage later becomes material, archive inactive superseded/retracted rows without changing active semantics.
- **No global truth table or automatic session lorebook in MVP:** source canon remains in card/manual lorebook, episodes in MemoryBooks, current scene in committed ledger, and character development/knowledge in atomic scoped facts. Add objective world/session facts to the same model only after a demonstrated retrieval failure; never introduce a periodic LLM-written canon article by default.
- **Do not use an LLM-mutated card snapshot as canonical state:** line editing destroys provenance, makes swipe/branch rollback ambiguous, couples session state to one historical card revision, encourages broad personality rewrites, and turns contradictions into destructive replacement. A session may retain the baseline card revision/hash for reproducibility, but development is an overlay of scoped atomic facts.
- **Card edits after session start:** do not require restarting the RP. Detect the baseline revision/hash change and offer/recompute a three-way effective view: new source card + existing session delta + manual conflict resolution. Existing session facts are not rewritten automatically.
- **No semantic reranker in MVP:** deterministic entity/topic routing is cheaper, debuggable, and sufficient to validate the architecture. Existing embeddings can be added only as shortlist reranking later.
