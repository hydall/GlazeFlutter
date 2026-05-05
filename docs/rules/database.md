# Database Rules

Rules for all code that reads from or writes to Isar.

## Isar write transactions for read-mutate-write

NEVER:
```dart
final data = await repo.getById(id);
data.messages.add(newMsg);
await repo.put(data);
```

ALWAYS:
```dart
await isar.writeTxn(() async {
  final col = await isar.chatSessionCollections
      .where().sessionIdEqualTo(id).findFirst();
  if (col == null) return;
  final messages = (jsonDecode(col.messagesJson) as List)
      .map((e) => ChatMessage.fromJson(e)).toList();
  messages.add(newMsg);
  col.messagesJson = jsonEncode(messages.map((e) => e.toJson()).toList());
  await isar.chatSessionCollections.put(col);
});
```

Isar `writeTxn` serializes concurrent writes. Two parallel `put()` calls outside a txn WILL conflict.

## Batch mutations in a single transaction

When you need to apply 2+ mutations to the same entity, do them all inside one `writeTxn`:

```dart
await isar.writeTxn(() async {
  final col = await isar.chatSessionCollections
      .where().sessionIdEqualTo(id).findFirst();
  if (col == null) return;
  // mutation 1
  // mutation 2
  // mutation 3
  await isar.chatSessionCollections.put(col);
});
```

One read → all mutations → one write. No redundant reads, no gap between mutations.

**When NOT to batch:** If you need async work (API call, embedding, image processing) between mutations, keep them as separate `writeTxn` calls. Transaction callbacks should minimize async gaps.

## Save before state cleanup

When finalizing a generation, persist data to Isar BEFORE clearing Riverpod state. If you clear state first and the save fails, data is lost.

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
2. Save intermediate state to Isar on `AppLifecycleState.paused`
3. On `AppLifecycleState.resumed`, verify generation state consistency
4. In-progress operations that were suspended may need restart — handled by provider layer, not widget layer

## Background persistence throttling

During active generation, stream text is persisted to Isar at reduced frequency:
- Desktop: moderate throttle (every ~500ms)
- Mobile / battery-saver: aggressive throttle (every ~2000ms)

This reduces Isar write churn while ensuring no data loss on crash.

## Image storage

- Character avatars and chat images stored on file system via `path_provider`
- `getApplicationDocumentsDirectory()` → `images/` subdirectory
- Isar stores only the relative file path string, not binary data
- On import, PNG tEXt avatar is extracted and saved to disk

## Embedding storage

When implemented:
- Store: Isar `EmbeddingCollection`
- Schema: `{ id, sourceType, sourceId, vectorsBlob, textHash, retrievalHints, updatedAt }`
- Vectors stored as `Uint8List` (Float32 encoded) for compact storage
