# Database Rules

Rules for all code that reads from or writes to the Drift database.

---

## One repo per table

All DB access goes through a repo class in `lib/core/db/repositories/`.
Never query Drift tables directly from a provider, service, or UI file.

```
UI → Provider → Service → Repo → Drift table
```

---

## No raw SQL outside repos

All queries use Drift's type-safe API. Raw SQL (`customSelect`, `customInsert`) is
allowed only inside the repo for the table it owns.

---

## Atomic read-mutate-write for chat sessions

`ChatRepo.put()` is a direct write. When you need to **read + modify + write** a session
(e.g. append a message, patch a field), you must do it atomically inside a Drift
`transaction()` to prevent concurrent writes from interleaving:

```dart
// NEVER:
final session = await chatRepo.getByCharacterId(charId);
session.messages.add(newMsg);
await chatRepo.put(session); // race: another write may have happened between read and write

// ALWAYS (inside a transaction or via a dedicated repo method):
await db.transaction(() async {
  final session = await chatRepo.getByCharacterId(charId);
  final updated = session.copyWith(messages: [...session.messages, newMsg]);
  await chatRepo.put(updated);
});
```

Prefer adding a dedicated repo method (e.g. `appendMessage`) that encapsulates
the transaction rather than doing it ad hoc in a service. Dedicated atomic
methods on `ChatRepo` include `appendSwipeToMessage`,
`appendAgentSwipe({kind: 'cleaned' | 'final'})` (nested blue sub-swipe +
`_syncAgentSwipesToMeta`), `updateAgentSwipeContent` / `removeAgentSwipe`
(in-place swipe editers used by the swipe-first cleaner flow — re-sync
`swipesMeta` the same way), and the chat/character variable-scope methods.

---

## Save before state cleanup

When finalizing a generation, persist data to DB **before** clearing reactive state.
If you clear `ChatState.isGenerating = false` first and the DB write fails, data is lost.

Order:
1. `chatRepo.put(finalSession)`
2. `state = state.copyWith(isGenerating: false, ...)`

---

## Schema migrations

All schema changes go in `AppDatabase.migration` in `app_db.dart`.
Bump the schema version and add a `from → to` migration step.
Never modify existing column types without a migration.

Current version: **51**

Migration history:
- v18: added `characters.picksHash`
- v19: added `characters.createdAt` + data migration (`SET created_at = updated_at WHERE created_at = 0`)
- v20: added `extension_presets` and `info_blocks` tables (extension system)
- v21: added `api_configs.cacheControlTtl` (Anthropic prompt cache control: 'off' | '5min' | '1h')
- v22: added `info_blocks.status` TEXT DEFAULT `'done'` + `info_blocks.order_` INTEGER DEFAULT 0 (block execution order + run status for ext blocks redesign)
- v23: added `api_configs.protocol` TEXT DEFAULT `'openai'` — wire protocol selector (openai / anthropic / gemini / openrouter). Drives `ChatTransport` factory routing
- v24: added `api_configs.topK` INTEGER DEFAULT 0, `api_configs.frequencyPenalty` REAL DEFAULT 0, `api_configs.presencePenalty` REAL DEFAULT 0
- v25: added `api_configs.cacheBreakpointMode` TEXT DEFAULT `'depth'` — Anthropic/OpenRouter prompt cache marker placement (`depth` / `stable_prefix`); `api_configs.sessionIdMode` TEXT DEFAULT `'openrouter'` — controls when `session_id` is sent for provider sticky routing
- v26: version bump only — no schema change (guards added to v20–v25 migration blocks)
- v27: added `info_blocks.swipe_id` INTEGER DEFAULT 0 (scopes ext blocks per message swipe); backfill `api_configs` columns missing from partial migrations (`top_k`, penalties, cache/session modes)
- v28: data migration — `UPDATE info_blocks SET swipe_id = 0 WHERE swipe_id IS NULL` (backfill for rows that survived v27 with NULL)
- v29: added `memory_catalog_rows` table for rebuildable per-session Memory Catalog state
- v30: added `chat_summaries.enabled` BOOL DEFAULT 1 (+ backfill NULL → 1)
- v31: added `character_folders` + `character_folder_members` tables (local character folders; composite PK `{folderId, charId}` enforces no-duplicate-within-folder)
- v32: added `characters.tokenCount` INTEGER DEFAULT 0 (cached estimated token count; computed on import/save, backfilled in background for existing rows)
- v33: added `characters.variantGroupId` TEXT + `characters.variantName` TEXT + `characters.variantOrder` INTEGER (character variations: rows sharing `variant_group_id` collapse to one list card; backfill sets each existing character's group to its own `char_id`)
- v34: added `characters.hidden` BOOL DEFAULT 0 (hideable characters: excludes a character/group from the My Characters list)
- v35: added Memory Graph tables (`memory_entity_rows`, `memory_salience_rows`, `memory_cadence_rows`, `memory_consolidation_rows`)
- v36: added `studio_config_rows`
- v37: added Studio `buildApiConfigId` / `runApiConfigId`
- v38: added Studio selected block ids fields
- v39: added Studio `finalPresetId`
- v40: added Studio request preset ids
- v41: added Studio preset overrides JSON
- v42: added Studio `profileId` / `profileName` for reusable session-bound profiles
- v43: added Studio `builderPromptTemplate` override for editable Studio rebuild prompts
- v44: added Studio `maxFinalHistoryMessages` INTEGER DEFAULT 15 — caps trailing chat messages sent to the final Studio generator (0 = unlimited); Studio trackers receive their own `StudioAgent.contextSize` (default 5, hard-cap 200) instead — see INV-ST1/INV-ST2 in `docs/INVARIANTS.md`
- v45: added `tracker_rows` table — lightweight key-value trackers written by the post-turn write-loop and Studio trackers (e.g. 'mood: happy', 'inventory: chip in pocket'). Composite PK `{sessionId, name}`; indexed on `{sessionId, scope}`. Deleted in `chatRepo.deleteByCharacterId` and `characterRepo.delete` cascades alongside `memory_book_rows`. Read live by `agentic_operations_log_dialog.dart` "Tracker values" tab.
- v46: added `studio_config_rows.routing_mode` TEXT DEFAULT `'verbatim'` — controls how preset blocks become agent instructions (`verbatim` = blocks concatenated дословно, no LLM call; `compiled` = legacy LLM digest). The decomposition service (`studio_decomposition_service.dart`) was restored after Phase 2: `decompose()` produces `StudioAgent`s (trackers + one final generator) that slot into `runTrackerCycle`; `routing_mode = 'compiled'` triggers the LLM builder, `'verbatim'` concatenates blocks directly.
- v50: added `tracker_snapshots` table — per-agent-swipe immutable snapshots of all trackers (mirrors Marinara-Engine's `game_state_snapshots`). Composite PK `{sessionId, messageId, swipeId, agentSwipeId}`; columns `trackersJson` (JSON array of `Tracker.toJson`), `committed` (0/1), `createdAt` (epoch seconds). Three indexes on `(sessionId, committed, createdAt)` for fast `getLatestCommitted` lookups. The `TrackerSnapshotRepo` (299 lines) owns all access; `tracker_rows` is kept as the write-loop's internal mutable store (LLM upserts into it, then a snapshot is taken).
- v51: data migration — aggregates `tracker_rows` per session into a baseline snapshot at the sentinel anchor `(messageId='', committed=1)`. Legacy sessions that had `tracker_rows` but no snapshots get a one-time baseline so the snapshot-first read path (Phase 3) finds data immediately. The sentinel anchor is never dropped by `deleteForMessage` (only by `deleteBySessionId` / `deleteByCharacterId`).

---

## Atomic single-column updates

For status fields that change frequently (e.g. block run status during extension
post-generation), use a dedicated repo method that updates only the target column
rather than reading and re-writing the entire row:

```dart
// GOOD — atomic, minimal I/O
Future<void> updateStatus(String id, BlockRunStatus status) =>
    (db.update(db.infoBlocks)..where((t) => t.id.equals(id)))
        .write(InfoBlocksCompanion(status: Value(status.name)));

// BAD — full row read-mutate-write for a single column change
final block = await getById(id);
await put(block.copyWith(status: status));
```

Pattern: `InfoBlocksRepository.updateStatus()` is the canonical example.

---

## Atomic read-mutate-write for JS variable scopes

The JS bridge (`JsBridgeService._updateScope`) writes four variable
scopes. The `chat` and `character` scopes go through dedicated repo
methods that wrap the read-modify-write in a Drift transaction so two
concurrent bridge calls cannot interleave:

```dart
// ChatRepo.updateSessionVarsJson
await db.transaction(() async {
  final session = await repo.getById(sessionId);
  final next = mutator(_decodeChatVars(session.sessionVars));
  if (next.isEmpty) session.sessionVars.remove(_chatVarsKey);
  else session.sessionVars[_chatVarsKey] = jsonEncode(next);
  await repo.put(session);
});

// CharacterRepo.updateExtensionsJson — same shape, on the extensions map.
```

`global` variables go through `GlobalVariablesRepo` (SharedPreferences
JSON) with a serialized write lock (`_writeLock`) and a 64 KiB payload
cap. `message` variables are in-memory only (`MessageVariablesNotifier`).

**Never** do `getById → mutate → put` for any of these scopes —
always go through the dedicated repo method.

---

## Embedding storage

Table: `Embeddings`
Schema: `{ entryId, sourceType, sourceId, vectorsBlob (BLOB), textHash, retrievalHintsJson (JSON text), errorJson (JSON text), updatedAt }`

- Vectors stored as binary float32 BLOB via `vectorListToBytes()` free function in `vector_math.dart` (not a method on `EmbeddingRepo`).
- `textHash` used for dirty-check: if hash matches stored hash, skip re-embedding.
- `sourceType`: `'lorebook_entry'` | `'memory_entry'`
- `entryId` namespaced as `lorebookId_entryId` to prevent cross-lorebook collisions.
- `retrievalHintsJson` is JSON text (not BLOB).
- `errorJson` stores embedding error details (classification via `EmbeddingErrorLabel`).

---

## Deletion cascades

### `CharacterRepo.delete(charId)` (inside DB transaction, defensive)

1. Gets session IDs for the character
2. Deletes `MemoryBookRows` by session IDs
3. Deletes `TrackerRows` by session IDs (agentic memory trackers)
4. Deletes `TrackerSnapshots` by session IDs (Phase 1 tracker-snapshot rollback system — cascade alongside `TrackerRows` so legacy and snapshot stores are cleaned together)
5. Deletes `ChatSummaries` by session IDs
6. Deletes `ChatSessions` by character ID
7. Deletes `Characters` by charId

This path is used by direct repo callers (e.g. sync engine). It is idempotent.

**Does NOT delete:**
- `Embeddings` — done separately in `CharactersNotifier.remove()`
- `Lorebooks` — character-scoped lorebooks deleted separately in `CharactersNotifier.remove()`

### `chatRepo.deleteByCharacterId(characterId)` (preferred path for bulk character-scoped cleanup)

Deletes in order:
1. `MemoryBookRows` for all sessions of the character
2. `TrackerRows` for all sessions of the character (agentic memory trackers)
3. `TrackerSnapshots` for all sessions of the character (Phase 1 cascade — `trackerSnapshotRepoProvider.deleteBySessionId` per session)
4. `ChatSummaries` for all sessions of the character
5. `ChatSessions` for the character

Returns the list of deleted session IDs (for sync-deletion tracking).

### `CharactersNotifier.remove(id)` (provider-level, wraps repo + extra cleanup)

1. Deletes character-scoped lorebooks (`lorebookRepo.getByScopeAndTarget('character', id)`)
2. Deletes embeddings for those lorebooks (`embeddingRepo.deleteBySourceId(lorebookId)`)
3. Cleans stale IDs from `lorebookActivations` SharedPreferences map
4. Calls `chatRepo.deleteByCharacterId(id)` — fully cleans `MemoryBookRows`, `ChatSummaries`, and `ChatSessions` for the character (see above)
5. Calls `repo.delete(id)` — deletes the `Characters` row (its internal defensive cleanup of per-session rows is a no-op after step 4, since sessions are already gone)

This order guarantees no orphan `MemoryBookRows` or `ChatSummaries` rows after character deletion.

When adding a new table with per-character or per-session data, add its deletion to the appropriate cascade path (`deleteByCharacterId` for session-scoped data, or `CharactersNotifier.remove` for character-scoped auxiliary data).

---

## Reactive streams

`CharacterRepo.watchAll()` returns a `Stream<List<Character>>` (Drift reactive query).
`CharactersNotifier` subscribes to this stream — UI rebuilds automatically on any change.

For other tables that need reactive updates, add a `watch*` method to the repo.
Do not poll; use Drift streams.

---

## MemoryBook agent-generated batches (Phase 7)

`MemoryBookRows.entriesJson` and `pendingDraftsJson` are JSON TEXT blob
columns — adding fields to `MemoryEntry` / `MemoryDraft` requires NO Drift
schema migration, only a freezed regeneration (`dart run build_runner build`)
plus an in-place migration in `fromJson` (see `_migrateEntryInPlace` and
`_migrateInjectionTargetInPlace` in `lib/core/models/memory_book.dart`).

### Source / kind markers

- `MemoryDraft.source`: `'scan_chat'` (set by `MemoryBookController.scanChat`)
  or `'agentic'` (set by `MemoryAgenticWriteService._executeMemoryWrites` post-turn
  write-loop) or `''` (legacy / manual).
- `MemoryEntry.source`: propagated from `draft.source` by
  `MemoryBookController.approveDraft` (Phase 7). Defaults to `''` for legacy
  entries; migrated in `_migrateEntryInPlace`.
- `MemoryEntry.kind`: `'curated'` (default) or `'agent'` (set by `approveDraft`
  when `draft.source == 'agentic'`).

### Auto-approve policy

Agent drafts that pass validation are **auto-promoted to `MemoryEntry`**
immediately — they land in the MemoryBook `entriesJson` with `kind='agent'`,
`source='agentic'`, `messageIds=[messageId]`. The user can edit or delete
them afterwards via the MemoryBook UI "Agent memories" tab, but no manual
"Approve" click is required. This is the auto-approve path:
`MemoryAgenticWriteService._executeMemoryWrites` builds `MemoryEntry`
objects directly and calls `MemoryBookRepo.appendApprovedEntries` (not
`appendDrafts`).

Scan drafts (`source='scan_chat'`, produced by `MemoryBookController.scanChat`)
still use the pending-drafts path: they land in `pendingDraftsJson` and the
user explicitly approves or deletes them via the MemoryBook UI. This is
because scan drafts are bulk-produced from a user-triggered scan, where
review is the point of the operation.

Invalid/empty/duplicate agent drafts are silently dropped (the LLM may emit
fewer valid entries than it tried to). There is no half-approved state.

The dedicated atomic repo path is `MemoryBookRepo.appendApprovedEntries`
(transactional read-modify-write of `entriesJson` inside `db.transaction()`
per Rule 3 above). `MemoryAgenticWriteService` never touches `entriesJson`
directly — it always goes through `appendApprovedEntries`. The legacy
`appendDrafts` (for scan drafts) follows the same atomic pattern.

### Delete-on-message-removal

Deleting an assistant message also drops the memory entries/drafts sourced
from it: `ChatMessageService.deleteMessage` calls
`MemoryBookRepo.deleteForMessage(sessionId, messageId)`, which atomically
removes any `MemoryEntry` or `MemoryDraft` whose `messageIds` contains
`messageId`. Items sourced from other messages are preserved. This mirrors
the tracker-snapshot rollback (`TrackerSnapshotRepo.deleteForMessage`) that
already ran on this path.

### Display separation

`memory_books_sheet.dart` (Phase 7.2) tabs drafts/entries by `source`:
- **Approved** tab: `entry.source != 'agentic'` (curated + scan-promoted)
- **Scan drafts** tab: `draft.source != 'agentic'` (bulk scan drafts)
- **Agent memories** tab: `draft.source == 'agentic'` + `entry.source == 'agentic'`

`agentic_operations_log_dialog.dart` (Phase 7.5) has a separate "Tracker
values" tab that reads `trackerRepoProvider.getBySessionId` — live tracker
state (scene, weather, inventory, ...) is NOT a MemoryBook entry and is NOT
mixed with memory drafts. See INV-M6 in `docs/INVARIANTS.md`.

---

## Tracker snapshot rollback system (Phases 1-12)

`tracker_snapshots` is an immutable per-agent-swipe snapshot of all
trackers, written once after each generation's write-loop completes and
never mutated. Rollback is **emergent**: deleting rows makes the previous
committed snapshot become the new latest (no explicit "restore" code path).

### Granularity

Each snapshot is anchored at `(sessionId, messageId, swipeId, agentSwipeId)`:
- `messageId` — the assistant message that triggered the write-loop.
- `swipeId` — which swipe of that message (regen creates new swipes).
- `agentSwipeId` — which agent sub-swipe (e.g. `'final'` vs `'cleaned'`).

This per-agent-swipe granularity (chosen explicitly over per-message or
per-session) lets the rollback system restore state at the exact level the
user navigates: swiping back through agent sub-swipes restores the matching
tracker state.

### Sentinel anchor for legacy data

Migrated `tracker_rows` (Phase 7 migration v51) become a baseline snapshot
at the sentinel anchor `(messageId='', committed=1)`. This anchor is
**never** dropped by `deleteForMessage` (only by `deleteBySessionId` /
`deleteByCharacterId`), so legacy sessions always have a baseline until the
session itself is deleted.

### Write path

`MemoryAgenticWriteService.runWriteLoop` accepts `messageId`/`swipeId`/
`agentSwipeId` and, after the LLM writes to `tracker_rows`, re-reads the
updated trackers and upserts an immutable snapshot at that anchor via
`TrackerSnapshotRepo.upsertTrackers`. The snapshot is initially
`committed=0`.

`commitLatest` (Phase 6) is called by `ChatNotifier.sendMessage` just
before the next generation starts — it marks the latest snapshot for the
session as `committed=1`. Committed snapshots are what the read path
surfaces; uncommitted snapshots are intermediate state from in-flight
write-loops.

`post_cleaner_service.applyCleanedText` (Phase 2) clones the parent
message's snapshot into the new `'cleaned'` agent-swipe anchor so the
cleaned sub-swipe inherits the parent's tracker state.

### Read path (snapshot-first)

The 3 call sites (`prompt_payload_builder.dart`, `write_loop_stage.dart`,
`agentic_operations_log_dialog.dart`) call `getLatestCommitted` /
`getLatest` and fall back to `trackerRepoProvider.getBySessionId` when no
snapshot exists (legacy sessions that haven't been re-saved since Phase 1).

### Rollback paths

| User action | Repo method | Effect |
|-------------|-------------|--------|
| Delete a message | `ChatRepo.deleteMessage` → `trackerSnapshotRepo.deleteForMessage` + `trackerRepo.replaceForSession` + `memoryBookRepo.deleteForMessage` | All snapshots at that `messageId` are dropped; the previous committed snapshot becomes the latest. The live `tracker_rows` store is rolled back to that preceding committed snapshot so the UI "Tracker values" tab and the Studio tracker preview show the state as of the previous message (e.g. if the deleted message's write-loop recorded "put cup on shelf", that tracker value is reverted). Memory book entries/drafts whose `messageIds` contains the deleted `messageId` are also dropped. |
| Delete a session | `chat_history_provider.deleteSession` → `deleteBySessionId` + `SyncDeletionTracker.record('tracker_snapshot', sessionId)` | All snapshots for the session are dropped; cloud sync deletion is tracked. |
| Clear chat | `chat_session_service.clearChat` → `deleteBySessionId` (both paths) | Same as delete-session. |
| Delete by character | `chatRepo.deleteByCharacterId` → cascade `deleteBySessionId` per session | All snapshots for all of the character's sessions are dropped. |
| Swipe removal | `trackerSnapshotRepo.shiftSwipeIdsAfterRemoval` | Re-keys snapshots whose `swipeId` > removed id, preserving continuity. |
| Branch session | `chat_session_service.branchSession` → `copyForSessionBranch` | Copies snapshots for sliced message IDs to the new session ID. |

### Cloud sync coverage (Phase 9)

`tracker_snapshots` is in the backup whitelist (`backup_exporter.dart`,
backup `_schemaVersion` 5) and has full cloud sync coverage via
`SyncTrackerSnapshotStore` + `TrackerSnapshotSyncStore` adapter. Sync
follows the InfoBlock per-session collection pattern: one entry per
session, payload `{__trackerSnapshots:true, items:[...]}`. Deletes are
tracked via `SyncDeletionTracker.record('tracker_snapshot', sessionId)`.

### Never

- **Never** read-modify-write a `ChatSession` / `Character` from outside
  the dedicated atomic repo methods (this applies to the chat/character
  variable scopes — see "Atomic read-mutate-write for JS variable scopes"
  above). Tracker snapshots follow the same rule: use
  `TrackerSnapshotRepo.upsertTrackers` / `deleteForMessage` /
  `deleteBySessionId` etc. — never `getById → mutate → put`.
- **Never** mutate an existing snapshot row. Snapshots are write-once; the
  only allowed writes are `upsertTrackers` (insert-or-replace by PK),
  `commit` / `commitLatest` (flip `committed` 0→1), and delete methods.
- **Never** drop the sentinel anchor `(messageId='')` via
  `deleteForMessage`. Only `deleteBySessionId` / `deleteByCharacterId`
  may drop it.
