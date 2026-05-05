# Generation Lifecycle Rules

Mandatory rules for any code that participates in chat generation, summary, memory draft, or transport.

Full formal invariants: `docs/INVARIANTS.md`

## Generation types and their scopes

| Type | Registry | Streaming | Abort | State isolation |
|------|----------|-----------|-------|-----------------|
| Chat | `generationStates` (genId) | Yes | Shared `CancelableOperation` | Per charId |
| Summary | None | No | Caller-owned | No chat state mutation |
| Memory draft | Own `memoryDraftCancelTokens` | No | Per-draft token | Per charId, separate from chat |

## Mutual exclusion

- Chat generation and memory draft CANNOT run simultaneously for the same charId (guards in BOTH directions)
- Summary is stateless and can run alongside anything
- Background operations must check `isGenerating` before starting

## genId ownership

Every chat generation gets a unique `genId`. All callbacks (`onUpdate`, `onComplete`, `onError`) MUST verify `genId` matches `generationStates[charId]` before mutating state. If mismatch — discard or route to stale cleanup.

`requestToken = "$scope:$charId:$sessionId:$genId"` — fully qualified ownership identifier.

## Cancel signal chain

```
cancelToken.cancel()
  → CancelableOperation.isCanceled = true
  → Dio passes cancelToken to HTTP request
  → SSE parser checks cancelToken per chunk
  → Dio cancels request, closes TCP connection
  → handleCancelOutcome() routes with userCanceled flag
  → onError(CancelException) fast-paths without error toast
```

**Never break this chain.** If `cancelToken` doesn't reach Dio, stop button only clears UI while TCP stays open.

### Pipeline cancel propagation

When `cancelToken.isCanceled` is true before the HTTP request starts (e.g. during
vector search, memory injection, or context limit guard), the pipeline breaks
and calls `onError(CancelException)` with `userCanceled` propagated from the token.
This ensures the cancel chain reaches error handling regardless of when the
cancel fires.

## State cleanup on every exit path

For every `setGenerationState(charId, ...)` there MUST be a `clearGenerationState(charId, ...)` on:
- Completion
- Error
- Cancel
- Widget dispose

`clearGenerationState(charId, expectedGenId)` prevents double-cleanup from cancel clearing a newer generation's state.

**Cancel path delegation:** Cancel handler does NOT call `clearGenerationState` directly.
It delegates cleanup to `handleGenerationError → restoreState → finalizeGenerationState`,
which calls `clearGenerationState` with the correct `expectedGenId`. Calling `clearGenerationState`
in both cancel and error handler would cause double-cleanup and race conditions with stale guards.

## Partial text on cancel

- Streaming: preserve partial text as completed message
- Non-streaming: no partial text available (by design)
- This asymmetry is intentional

## Prompt ordering (do not reorder)

1. Keyword lorebook scan (in Isolate)
2. Vector lorebook scan (after Isolate, deduplicated against keyword results)
3. Memory injection (guarded by 35% token budget)
4. Context cutoff trims oldest first

## Stream vs non-stream parity

Both paths must produce identical `onComplete(text, reasoning)` for the same API response.
Dio streaming and one-shot response must normalize to the same output structure.

## PR verification checklist

Before merging any structural PR:
- [ ] Chat generation produces correct responses
- [ ] Stop preserves partial text when available
- [ ] Regenerate while generating is safely rejected
- [ ] Character switch during generation continues background generation
- [ ] Prompt block order matches preset definition
- [ ] Lorebook keyword + vector results correctly merged
- [ ] Memory injection respects token budget guard
- [ ] History cutoff trims oldest first
- [ ] Summary returns string without affecting chat state
- [ ] Memory draft doesn't affect generation registry
- [ ] Context limit exceeded caught and shown
- [ ] API not configured caught and shown
