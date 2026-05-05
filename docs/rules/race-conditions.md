# Race Condition Prevention Rules

Every new feature or fix that touches async boundaries, generation state, or Drift must satisfy these rules before commit.

## Rule 1: Every `await` is a checkpoint

After any `await`, always verify you still own the state:

- Not canceled? `cancelToken.isCanceled`
- Same generation? `isGenerationStateCurrent(charId, genId)`
- Same session? `sessionId == expected`
- Still mounted? `mounted` (in StatefulWidgets)

Pattern:
```dart
final result = await someAsyncWork();
if (cancelToken?.isCanceled ?? false) return;
if (!isGenerationStateCurrent(charId, genId)) return;
if (!mounted) return;
```

## Rule 2: No state mutation without ownership

- `onComplete` / `onError` / `onUpdate` callbacks MUST check `genId` before mutating any Riverpod state
- New providers that participate in generation lifecycle MUST use generation registry for ownership tokens
- Transient state (isGenerating, typing placeholder, pending swipe) is owned by a single generation token and auto-cleaned on finalization

## Rule 3: Drift transactions for all read-mutate-write

- NEVER do `final data = await repo.getById(id); /* mutate */; await repo.put(data)` outside a transaction — this is a race
- ALWAYS use `_db.transaction(() async { ... })` for any read-mutate-write cycle — Drift serializes writes
- For chat sessions with heavy concurrent access (streaming updates), use a dedicated write queue or throttle to avoid txn conflicts

Pattern:
```dart
await _db.transaction(() async {
  final row = await (_db.select(_db.chatSessions)
        ..where((t) => t.sessionId.equals(sessionId)))
      .getSingleOrNull();
  if (row == null) return;
  // mutate and write back
  await _db.into(_db.chatSessions).insertOnConflictUpdate(companion);
});
```

## Rule 4: New async boundaries need stale guards

When adding a new provider or service function that:
- receives callbacks from transport/pipeline layer
- mutates Riverpod state
- persists data to Drift

...it MUST include a staleness/ownership check before the mutation. Without it, a late completion from a canceled generation WILL corrupt state.

## Rule 5: Mutual exclusion for concurrent operations

- Chat generation and memory draft generation are mutually exclusive (checked in both directions)
- If adding a new request type that runs alongside chat generation, add mutual exclusion guards in BOTH directions
- Background operations must check `isGenerating` before starting

## Rule 6: Widget dispose vs operation cancel

**RULE: Widgets MUST NOT cancel long-running async operations in `dispose()`.**

### What `dispose` MAY do
- Unsubscribe from stream listeners
- Clear UI callback references
- Cancel render-only timers (debounce, scroll, animation)
- Set flags (`_isDisposed = true`)

### What `dispose` MUST NOT do
- Call `cancelToken.cancel()` on generation tokens
- Call `clearGenerationState()` or equivalent registry cleanup
- Kill HTTP connections
- Delete state that async completion handlers need

### The principle: unsubscribe ≠ cancel
When a widget disposes, it **disconnects from results**, not **cancels the operation**. The operation continues in the background, writing to Drift through repository-layer paths. When the user navigates back, data is loaded from Drift.

### Ownership model
- **Provider layer** owns the operation lifecycle: start, progress, completion, cleanup
- **Widget layer** owns the UI subscription: render, scroll, local state updates
- Only explicit user action (stop button) triggers cancel via provider-layer cancel function

## Why this matters

Dart's event loop has the same boundaries as JS. Each `await` yields control, and other microtasks can run. The same races that existed in JS exist in Dart — the rules are the same, just with different primitives (`CancelToken` instead of `AbortController`, Drift txn instead of `patchChatData`).

## Known race classes and their fixes

| Race | Cause | Fix |
|------|-------|-----|
| Stale completion mutates new typing state | Callback didn't check genId | `expectedGenId` in finalize/restore/complete |
| Cancel didn't reach Dio | cancelToken not passed to request | Signal chain through request config |
| Read-mutate-write in Drift | `getById` + `put` without txn | `_db.transaction` for read-mutate-write |
| Registry leak after dispose | `clearGenerationState` not called | Fix in dispose guard |
| Memory draft + chat generation simultaneously | No mutual exclusion | Block in both directions |
