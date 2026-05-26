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

- SSE callbacks (`onDelta`, `onComplete`, `onError`) **must** check `_activeGenId` before
  mutating `ChatState` or persisting to DB.
- Image generation callbacks (`retryImageGeneration`, `retryImageGenerationForMessage`)
  currently do NOT have a `genId` guard — potential stale state write.
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

## Rule 5: Mutual exclusion for concurrent operations ⚠️ PARTIALLY UNENFORCED

- Chat generation and memory draft generation **should** be mutually exclusive, but
  neither direction is implemented:
  - `ChatNotifier.sendMessage()` does NOT check for active memory drafts.
  - `memory_books_sheet.dart._generateDraft()` does NOT check `ChatState.isGenerating`.
  - No shared state bridges the two systems.
- Image generation runs only after text generation completes (enforced by call order).
- Background operations (auto-sync, embedding indexing) should check `isGenerating`
  for the relevant `charId` before starting.

If adding a new request type alongside chat generation, add mutual exclusion guards
in **both** directions.

---

## Rule 6: CancelToken must reach the HTTP layer

When the user taps Stop, `abortGeneration()` calls `_cancelToken?.cancel()` and
`_imgGenCancelToken?.cancel()`, both of which must propagate to Dio.
Cancelling only UI state (`isGenerating = false`) while the TCP connection stays open
is a bug — the stream continues running in the background and may write stale results.

Verify: after pressing Stop, the network tab shows the request was actually terminated.

---

## Known race classes

| Race | Cause | Fix / Status |
|------|-------|-----|
| Stale completion writes to new generation's state | Callback didn't check `_activeGenId` | Guard exists in `ChatGenerationService` callbacks via `isAborted()` |
| Stop button doesn't close TCP connection | `CancelToken` not passed to `Dio` | Ensure `CancelToken` reaches `SseClient` |
| Read-mutate-write in DB | `getById` + `put` without transaction | Wrap in `db.transaction()` |
| Two memory drafts start for same draft ID | No in-flight ID tracking in generator | Tracked in widget: `memory_books_sheet.dart._generatingDrafts` map |
| `apiListProvider` null on cold start | Sync provider read before async load | `await ref.read(apiListProvider.future)` first; also used by `MemoryDraftGenerator` |
| Image retry state corruption | `retryImageGeneration` callbacks have no `genId` guard | ⚠️ Unfixed — potential stale write to `ChatState` |
| Chat ↔ memory draft mutual exclusion | Neither side checks the other | ⚠️ Not implemented |
| Character deletion orphan rows | `CharactersNotifier.remove()` previously called `chatRepo.deleteByCharacterId` (only deleted `ChatSessions`) before `CharacterRepo.delete`, missing per-session tables | **Fixed** — `deleteByCharacterId` now deletes `MemoryBookRows` + `ChatSummaries` + `ChatSessions` in correct order. See `docs/rules/database.md`. |
