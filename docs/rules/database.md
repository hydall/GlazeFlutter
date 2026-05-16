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

Current version: **17**

---

## Embedding storage

Table: `Embeddings`
Schema: `{ id, sourceType, sourceId, vectors (BLOB), textHash, retrievalHints (BLOB), updatedAt }`

- Vectors stored as binary float32 BLOB via `EmbeddingRepo.vectorListToBytes()`.
- `textHash` used for dirty-check: if hash matches stored hash, skip re-embedding.
- `sourceType`: `'lorebook_entry'` | `'memory_entry'`

---

## Deletion cascades

`CharacterRepo.delete(charId)`:
- Deletes all `ChatSession` rows for that character
- Deletes all `Embedding` rows for that character's lorebook entries and memory entries
- **Does not** delete `Lorebook` rows (lorebooks are global, not per-character) —
  character-lorebook bindings are stored in activations (SharedPreferences), not in DB

When adding a new table with per-character data, add its deletion to `CharacterRepo.delete()`.

---

## Reactive streams

`CharacterRepo.watchAll()` returns a `Stream<List<Character>>` (Drift reactive query).
`CharactersNotifier` subscribes to this stream — UI rebuilds automatically on any change.

For other tables that need reactive updates, add a `watch*` method to the repo.
Do not poll; use Drift streams.
