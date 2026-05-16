# Race Condition Prevention Rules

Every feature or fix that touches async boundaries, generation state, or the DB must satisfy these rules before commit.

---

## Rule 1: Every `await` is a checkpoint

After any `await`, verify you still own the state:

```dart
final result = await someAsyncWork();

// Check 1: not aborted
if (cancelToken.isCancelled) return;

// Check 2: same generation (if inside generation callback)
if (currentGenId != expectedGenId) return;

// Check 3: same session (if session-scoped)
if (currentSessionId != expectedSessionId) return;
```

Missing any of these checks means a stale completion from an aborted generation can
silently corrupt state.

---

## Rule 2: No state mutation without ownership

- SSE callbacks (`onDelta`, `onComplete`, `onError`) **must** check `genId` before
  mutating `ChatState` or persisting to DB.
- New services that receive async results and write to state must include a
  staleness/ownership check. Without it, late completions **will** corrupt state.

---

## Rule 3: Atomic read-mutate-write for DB

Never:
```dart
final session = await chatRepo.getById(charId);
session.messages.add(msg);
await chatRepo.put(session); // RACE: another write may have happened
```

Always use a Drift `transaction()` or a dedicated repo method that wraps the
read-mutate-write atomically. See `docs/rules/database.md`.

---

## Rule 4: New async boundaries need stale guards

When adding a composable, service, or callback that:
- Receives results from an HTTP request or isolate
- Mutates Riverpod state
- Writes to the DB

…it **must** include a staleness check before the mutation.
Rule of thumb: if there's an `await` before the mutation, there's a potential race.

---

## Rule 5: Mutual exclusion for concurrent operations

- Chat generation and memory draft generation are mutually exclusive (checked in both directions).
- If adding a new request type alongside chat generation, add mutual exclusion guards
  in **both** directions.
- Background operations (auto-sync, embedding indexing) should check `isGenerating`
  for the relevant `charId` before starting.

---

## Rule 6: CancelToken must reach the HTTP layer

When the user taps Stop, `CancelToken.cancel()` must propagate all the way to `Dio`.
Cancelling only UI state (`isGenerating = false`) while the TCP connection stays open
is a bug — the stream continues running in the background and may write stale results.

Verify: after pressing Stop, the network tab shows the request was actually terminated.

---

## Known race classes

| Race | Cause | Fix |
|------|-------|-----|
| Stale completion writes to new generation's state | Callback didn't check `genId` | Add `genId` check before any mutation |
| Stop button doesn't close TCP connection | `CancelToken` not passed to `Dio` | Ensure `CancelToken` reaches `SseClient` |
| Read-mutate-write in DB | `getById` + `put` without transaction | Wrap in `db.transaction()` |
| Two memory drafts start for same draft ID | No in-flight ID tracking | Track in-flight IDs in `MemoryDraftGenerator` |
| `apiListProvider` null on cold start | Sync provider read before async load | `await ref.read(apiListProvider.future)` first |
