# Generation Lifecycle Rules

Mandatory rules for any code that participates in chat generation, summary, memory draft, or transport.

Full formal invariants with code references: `docs/INVARIANTS.md`

---

## Generation types and their scopes

| Type | State owner | Streaming | Abort |
|------|-------------|-----------|-------|
| Chat | `ChatState.isGenerating` (per `charId`) | Yes (SSE) | `CancelToken` in `ChatNotifier` |
| Summary | None (caller-owned) | No | Caller-owned `CancelToken` |
| Memory draft | Own per-draft abort in `MemoryDraftGenerator` | No | Per-draft `CancelToken` |

---

## Mutual exclusion

- Chat generation and memory draft **cannot run simultaneously** for the same `charId`.
  - Chat start → check no memory draft active → reject if so.
  - Memory draft start → check `ChatState.isGenerating` → reject if so.
- Summary is stateless — can run alongside anything.

---

## genId / CancelToken ownership

Every chat generation gets a unique generation identifier (use a monotonic counter or UUID).
All SSE callbacks (`onDelta`, `onComplete`, `onError`) **must** verify the generation ID still
matches the current active generation before mutating `ChatState`.

If the IDs do not match → **discard** the result silently.

```dart
// Pattern: check before any state mutation after an await
final delta = await sseClient.nextDelta();
if (_currentGenId != expectedGenId) return; // stale — discard
state = state.copyWith(messages: ...);
```

---

## Abort signal chain

```
ChatNotifier.stopGeneration()
  → CancelToken.cancel()
    → SseClient receives DioException(type: cancel)
      → SSE stream terminated
        → ChatGenerationService.onError(cancelled)
          → restores ChatState, persists partial text
```

**Never break this chain.** If `CancelToken` doesn't reach `Dio`, the stop button
only clears UI while the TCP connection stays open and the stream continues.

---

## State cleanup on every exit path

For every generation start, `ChatState.isGenerating` must be reset to `false` on:
- Completion
- Error
- Abort
- Notifier disposal / screen dispose

A generation that sets `isGenerating = true` and then crashes without clearing it will
permanently block future generations for that character.

---

## Partial text on abort

- Streaming: persist partial text as a completed message before clearing state.
- Non-streaming: no partial text available (by design — nothing was accumulated).

This asymmetry is intentional.

---

## Prompt ordering (do not reorder)

1. Keyword lorebook scan (synchronous, runs in Dart isolate)
2. Vector lorebook scan (async, after keyword results — deduplicates against them)
3. Memory injection (guarded by 35% token budget)
4. Context cutoff — trims oldest history messages first

---

## Session variable restore on abort

If macro expansion during prompt build writes to `sessionVars`, save a snapshot before
the build and restore it on every non-happy exit (abort, error). Otherwise aborted
generations leave behind mutated variables.

---

## Adding a new generation path

If you add a new request type (impersonation, image alt-text, etc.) that runs alongside
chat generation, you must:
1. Define a separate abort mechanism (do not reuse the chat `CancelToken`).
2. Add mutual exclusion checks in **both** directions (your type ↔ chat generation).
3. Verify `genId` matches before mutating any shared state.

---

## PR verification checklist

Before merging any generation-related PR:
- [ ] Chat produces correct responses end-to-end
- [ ] Stop preserves partial text when available
- [ ] Regen while generating is safely rejected
- [ ] Character switch continues background generation for the original character
- [ ] Prompt block order matches preset definition
- [ ] Keyword + vector lorebook results correctly merged and deduplicated
- [ ] Memory injection respects 35% token budget
- [ ] History cutoff trims oldest first
- [ ] Summary returns string without touching chat state
- [ ] Memory draft doesn't affect chat generation state
- [ ] Context limit exceeded is shown to the user
- [ ] API not configured is shown to the user
- [ ] Abort closes the TCP connection (not just UI)
