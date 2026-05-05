# Database Rules

Rules for all code that reads from or writes to Drift (SQLite).

## Drift transactions for read-mutate-write

NEVER:
```dart
final data = await repo.getById(id);
data.messages.add(newMsg);
await repo.put(data);
```

ALWAYS wrap read-mutate-write in a transaction:
```dart
await _db.transaction(() async {
  final row = await (_db.select(_db.chatSessions)
        ..where((t) => t.sessionId.equals(id)))
      .getSingleOrNull();
  if (row == null) return;
  final messages = (jsonDecode(row.messagesJson) as List)
      .map((e) => ChatMessage.fromJson(e)).toList();
  messages.add(newMsg);
  await _db.into(_db.chatSessions).insertOnConflictUpdate(
    _toCompanion(_toModel(row)..messages = messages),
  );
});
```

Drift `transaction()` serializes concurrent writes. Two parallel `put()` calls outside a txn WILL conflict.

## Batch mutations in a single transaction

When you need to apply 2+ mutations to the same entity, do them all inside one `transaction`:

```dart
await _db.transaction(() async {
  final row = await (_db.select(_db.chatSessions)
        ..where((t) => t.sessionId.equals(id)))
      .getSingleOrNull();
  if (row == null) return;
  // mutation 1
  // mutation 2
  // mutation 3
  await _db.into(_db.chatSessions).insertOnConflictUpdate(companion);
});
```

One read → all mutations → one write. No redundant reads, no gap between mutations.

**When NOT to batch:** If you need async work (API call, embedding, image processing) between mutations, keep them as separate `transaction` calls. Transaction callbacks should minimize async gaps.

## Save before state cleanup

When finalizing a generation, persist data to Drift BEFORE clearing Riverpod state. If you clear state first and the save fails, data is lost.

```dart
// RIGHT
await chatRepo.put(finalSession);
clearGenerationState(charId, genId);

// WRONG
clearGenerationState(charId, genId);
await chatRepo.put(finalSession); // might fail, data lost
```

## Crash recovery

On mobile (Android/iOS), the OS may suspend the app mid-generation. Strategy:
1. `WidgetsBindingObserver.appLifecycleState` detects backgrounding
2. Save intermediate state to Drift on `AppLifecycleState.paused`
3. On `AppLifecycleState.resumed`, verify generation state consistency
4. In-progress operations that were suspended may need restart — handled by provider layer, not widget layer

## Background persistence throttling

During active generation, stream text is persisted to Drift at reduced frequency:
- Desktop: moderate throttle (every ~500ms)
- Mobile / battery-saver: aggressive throttle (every ~2000ms)

This reduces SQLite write churn while ensuring no data loss on crash.

## Image storage

- Character avatars and chat images stored on file system
- `Platform.environment['APPDATA']/Glaze` (Windows), `~/.local/share/Glaze` (Linux), `~/Library/Application Support/Glaze` (macOS)
- Drift stores only the relative file path string, not binary data
- On import, PNG tEXt avatar is extracted and saved to disk

## Embedding storage

When implemented:
- Store: Drift table `Embeddings`
- Schema: `{ id, sourceType, sourceId, vectorsBlob, textHash, retrievalHints, updatedAt }`
- Vectors stored as `Uint8List` (Float32 encoded) for compact storage

## Table naming

Drift generates `*Data` (or custom `@DataClassName`) row classes from table definitions. Table classes in `tables.dart` use `@DataClassName('XxxRow')` suffix to avoid name collisions with Freezed models (e.g. `CharacterRow` vs `Character`).

## Migration

Drift supports schema migrations via `schemaVersion` and `MigrationStrategy`. When adding columns/tables:
1. Increment `schemaVersion` in `app_db.dart`
2. Add migration step in `onUpgrade`
3. Never delete columns — mark deprecated if needed
