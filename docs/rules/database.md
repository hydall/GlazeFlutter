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
the transaction rather than doing it ad hoc in a service.

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

Current version: **46**

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
- v45: added `tracker_rows` table — lightweight key-value trackers written by the post-turn write-loop and Studio trackers (e.g. 'mood: happy', 'inventory: chip in pocket'). Composite PK `{sessionId, name}`; indexed on `{sessionId, scope}`. Deleted in `chatRepo.deleteByCharacterId` and `characterRepo.delete` cascades alongside `memory_book_rows`. Read live by `agentic_operations_log_dialog.dart` "Tracker values" tab and `studio_menu_dialog.dart` (current tracker value preview)
- v46: added `studio_config_rows.routing_mode` TEXT DEFAULT `'verbatim'` — controls how preset blocks become agent instructions (`verbatim` = blocks concatenated дословно, no LLM call; `compiled` = legacy LLM digest, deprecated). The 8-slot decomposition service (`studio_decomposition_service.dart`) was DELETED in Phase 2 of `docs/PLAN_AGENTIC_STUDIO.md`; only `verbatim_shard_assembler.dart` (20-line util) remains. `routing_mode = 'compiled'` is preserved for legacy JSON compatibility but no longer triggers an LLM call.

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
4. Deletes `ChatSummaries` by session IDs
5. Deletes `ChatSessions` by character ID
6. Deletes `Characters` by charId

This path is used by direct repo callers (e.g. sync engine). It is idempotent.

**Does NOT delete:**
- `Embeddings` — done separately in `CharactersNotifier.remove()`
- `Lorebooks` — character-scoped lorebooks deleted separately in `CharactersNotifier.remove()`

### `chatRepo.deleteByCharacterId(characterId)` (preferred path for bulk character-scoped cleanup)

Deletes in order:
1. `MemoryBookRows` for all sessions of the character
2. `TrackerRows` for all sessions of the character (agentic memory trackers)
3. `ChatSummaries` for all sessions of the character
4. `ChatSessions` for the character

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

Agent drafts that pass validation land in the MemoryBook UI "Agent memories"
tab as pending drafts (visible alongside approved agent entries). They are
NOT silently auto-promoted to `MemoryEntry` — the user explicitly approves or
deletes them. Invalid/empty/duplicate agent drafts stay as pending drafts in
the same tab until the user acts on them.

The dedicated atomic repo path is `MemoryBookRepo.appendDrafts` (transactional
read-modify-write of `pendingDraftsJson` inside `db.transaction()` per Rule 3
above). There is NO read-modify-write of the MemoryBook outside the dedicated
repo methods — `MemoryAgenticWriteService` calls `appendDrafts` directly and
never touches `entriesJson`.

### Display separation

`memory_books_sheet.dart` (Phase 7.2) tabs drafts/entries by `source`:
- **Approved** tab: `entry.source != 'agentic'` (curated + scan-promoted)
- **Scan drafts** tab: `draft.source != 'agentic'` (bulk scan drafts)
- **Agent memories** tab: `draft.source == 'agentic'` + `entry.source == 'agentic'`

`agentic_operations_log_dialog.dart` (Phase 7.5) has a separate "Tracker
values" tab that reads `trackerRepoProvider.getBySessionId` — live tracker
state (scene, weather, inventory, ...) is NOT a MemoryBook entry and is NOT
mixed with memory drafts. See INV-M6 in `docs/INVARIANTS.md`.
