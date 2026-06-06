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

Current version: **22**

Migration history:
- v18: added `characters.picksHash`
- v19: added `characters.createdAt` + data migration (`SET created_at = updated_at WHERE created_at = 0`)
- v20: added `extension_presets` and `info_blocks` tables (extension system)
- v21: added `api_configs.cacheControlTtl` (Anthropic prompt cache control: 'off' | '5min' | '1h')
- v22: added `info_blocks.status` TEXT DEFAULT `'done'` + `info_blocks.order_` INTEGER DEFAULT 0 (block execution order + run status for ext blocks redesign)

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
3. Deletes `ChatSummaries` by session IDs
4. Deletes `ChatSessions` by character ID
5. Deletes `Characters` by charId

This path is used by direct repo callers (e.g. sync engine). It is idempotent.

**Does NOT delete:**
- `Embeddings` — done separately in `CharactersNotifier.remove()`
- `Lorebooks` — character-scoped lorebooks deleted separately in `CharactersNotifier.remove()`

### `chatRepo.deleteByCharacterId(characterId)` (preferred path for bulk character-scoped cleanup)

Deletes in order:
1. `MemoryBookRows` for all sessions of the character
2. `ChatSummaries` for all sessions of the character
3. `ChatSessions` for the character

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
