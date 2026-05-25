# Generation Lifecycle Rules

Mandatory rules for any code that participates in chat generation, summary, memory draft, or transport.

Full formal invariants with code references: `docs/INVARIANTS.md`

---

## Generation types and their scopes

| Type | State owner | Streaming | Abort |
|------|-------------|-----------|-------|
| Chat | `ChatState.isGenerating` (per `charId`) | Yes (SSE) | `_cancelToken` + `_activeGenId` in `ChatNotifier` |
| Image gen | `ChatState.isGeneratingImage` + `_imgGenCancelToken` | No (one-shot LLM) | `_imgGenCancelToken` in `ChatNotifier` |
| Summary | Widget-local `_isGenerating` in `summary_sheet.dart` | No | No CancelToken (cannot be aborted) |
| Memory draft | Widget-local `_generatingDrafts` in `memory_books_sheet.dart` | No | Per-draft `CancelToken` in widget's `_cancelTokens` map |

---

## Mutual exclusion

⚠️ **Not currently enforced.** The following are intended rules but not implemented:

- Chat generation and memory draft **should not** run simultaneously for the same `charId`.
  - Chat start → should check no memory draft active → reject if so. (NOT IMPLEMENTED)
  - Memory draft start → should check `ChatState.isGenerating` → reject if so. (NOT IMPLEMENTED)
- Image generation runs only after text generation completes (this IS enforced — `processImageTags()` is called after stream ends).
- Summary is stateless — can run alongside anything.

---

## genId / CancelToken ownership

Every chat generation gets a unique generation identifier (`_activeGenId`, monotonic counter).
All SSE callbacks (`onDelta`, `onComplete`, `onError`) **must** verify the generation ID still
matches the current active generation before mutating `ChatState`.

If the IDs do not match → **discard** the result silently.

```dart
// Pattern: check before any state mutation after an await
final delta = await sseClient.nextDelta();
if (_activeGenId != expectedGenId) return; // stale — discard
state = state.copyWith(messages: ...);
```

Image generation uses a separate `_imgGenCancelToken` but shares the same `_activeGenId`
for text generation invalidation. Image retries currently do NOT have a `genId` guard.

---

## Abort signal chain

```
ChatNotifier.abortGeneration()
  → _activeGenId++                    ← invalidates all pending callbacks
  → _cancelToken?.cancel()            ← propagates to Dio
  → _imgGenCancelToken?.cancel()      ← cancels any in-flight image gen
  → _clearStreaming()
  → Manual state restoration:
      - Read streamingStateProvider for partial text
      - Persist partial text as completed message
      - isGenerating = false
      - isGeneratingImage = false
      - Cancelled [IMG:GEN] tags → [IMG:ERROR:...]

Separately (asynchronously):
  → SseClient detects cancel → DioException(type: cancel)
  → ChatGenerationService.onError() → isAborted() returns true
    → returns ChatState(isGenerating: false) — effectively a no-op
```

**Never break this chain.** If `CancelToken` doesn't reach `Dio`, the stop button
only clears UI while the TCP connection stays open and the stream continues.

---

## State cleanup on every exit path

For every generation start, `ChatState.isGenerating` must be reset to `false` on:
- Completion
- Error
- Abort (`abortGeneration()`)
- App restart (fresh `ChatState` in `build()`)

Similarly, `isGeneratingImage` must be reset on:
- Image generation completion
- Image generation error
- Abort (`abortGeneration()` also cancels image gen)

A generation that sets `isGenerating = true` and then crashes without clearing it will
permanently block future generations for that character.

---

## Partial text on abort

- Streaming: persist partial text as a completed message before clearing state.
  Done in `ChatNotifier.abortGeneration()` by reading `streamingStateProvider`.
- Non-streaming: no partial text available (by design — nothing was accumulated).

This asymmetry is intentional.

---

## Image tag cleanup on abort

When generation is aborted, any `[IMG:GEN]` tags in the partial text are replaced
with `[IMG:ERROR:cancelled]` by `ChatGenerationService`. This prevents the UI from
showing "generating" spinners for images that will never complete.

---

## Prompt ordering (do not reorder)

1. Vector lorebook scan (async, runs in `PromptPayloadBuilder` — before isolate)
2. Keyword lorebook scan (synchronous, runs in `PromptBuilder` inside the Dart isolate)
3. Merge keyword + vector results (keyword wins on collision, vector deduplicated)
4. Memory injection
5. Context cutoff — trims oldest history messages first

---

## Session variable restore on abort ⚠️ NOT IMPLEMENTED

If macro expansion during prompt build writes to `sessionVars`, the pre-generation
snapshot should be restored on every non-happy exit (abort, error). Currently
aborted generations leave behind mutated variables.

---

## Continue message

`ChatNotifier.continueMessage()` is a distinct generation path that reuses
`ChatGenerationService.generate()` but appends the result to the last assistant
message instead of creating a new message or swipe.

---

## Adding a new generation path

If you add a new request type (impersonation, image alt-text, etc.) that runs alongside
chat generation, you must:
1. Define a separate abort mechanism (do not reuse the chat `CancelToken`).
2. Add mutual exclusion checks in **both** directions (your type ↔ chat generation).
3. Verify `genId` matches before mutating any shared state.
4. Ensure `isGenerating*` flags are cleared on every exit path.

---

## PR verification checklist

Before merging any generation-related PR:
- [ ] Chat produces correct responses end-to-end
- [ ] Stop preserves partial text when available
- [ ] Regen while generating aborts the current generation first
- [ ] Character switch continues background generation for the original character
- [ ] Prompt block order matches preset definition
- [ ] Vector scan runs before keyword scan; results correctly merged and deduplicated
- [ ] Memory injection respects context budget (⚠️ no guard yet)
- [ ] History cutoff trims oldest first
- [ ] Summary returns string without touching chat state
- [ ] Memory draft doesn't affect chat generation state (⚠️ not enforced)
- [ ] Image generation completes after text generation
- [ ] Context limit exceeded is shown to the user
- [ ] API not configured is shown to the user
- [ ] Abort closes the TCP connection (not just UI state)
- [ ] Session variables are restored on abort/error (⚠️ not implemented)
