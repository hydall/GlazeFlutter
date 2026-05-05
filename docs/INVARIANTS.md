# Generation Invariants

Runtime behavior that must not change during development.
Every structural PR must preserve these invariants or explicitly document a deviation.

---

## 1. Chat Generation Invariants

### INV-C1: One active chat generation per character

At most one chat-type generation may be active for a given `charId` at any time.
`startGeneration` enforces this via `getGenerationState(charId)` — if a non-impersonation
state exists, the call is silently rejected.

### INV-C2: Generation state is always eventually cleaned up

For every `setGenerationState(charId, ...)`, there must be a matching
`clearGenerationState(charId, ...)` on every exit path: completion, error, cancel, or dispose.

**Cancel path:** Cancel handler delegates cleanup to `handleGenerationError → finalizeGenerationState`
instead of calling `clearGenerationState` directly, to avoid double-cleanup and stale guard conflicts.
This satisfies the invariant — `clearGenerationState` is still called, just from the error handler.

### INV-C3: Partial text is preserved on cancel

When a user cancels mid-stream and partial text exists, the partial response is saved
as a completed message — not discarded.

### INV-C4: isGenerating is consistent with registry state

`isGenerating` must be `true` iff `hasGenerationState(activeChatChar.id)` is true
for the currently active character. On `openChat`, `isGenerating` is restored from
registry state.

### INV-C5: Prompt metadata snapshots are restored on cancel/error

`createPromptMetadataSnapshots()` is called before generation starts.
`restoreState()` must be called on every non-happy exit to roll back
any session variable mutations that occurred during prompt preparation.

### INV-C6: Background generation continues independently

When a generation is running for character A and the user navigates to character B,
generation for A continues in the background. Stream deltas are persisted to Isar
via background persistence provider.

### INV-C7: Stale completions are silently discarded

If a late `onComplete` fires for a `genId` that no longer matches the current
`generationStates[charId]`, the stale result is discarded and only cleanup is performed.

---

## 2. Summary Generation Invariants

### INV-S1: Summary is always non-streaming

Summary requests never use SSE streaming. The response is returned as a single
string from `executeSummaryRequest`.

### INV-S2: Summary does not create registry entries

Summary generation does not use `generationStates` at all. It has no `genId`,
no `requestToken`, and no UI state management beyond the caller's responsibility.

### INV-S3: Summary does not mutate chat state

Summary generation must not modify `isGenerating`, chat messages, or
generation registry state. It only reads history and returns a string.

---

## 3. Memory Draft Generation Invariants

### INV-M1: Memory draft does not use generation registry

Memory drafts use their own cancel infrastructure (`memoryDraftCancelTokens` Map)
and their own progress tracking (`memoryDraftProgressEntries` Map).
They never interact with `generationStates`.

### INV-M2: Memory draft is always non-streaming

Memory draft requests use `stream: false` unconditionally.

### INV-M3: Memory draft cannot start while chat generation is active

Checks `getGenerationState(activeChatChar.id)` and blocks if a non-impersonation
generation is running.

### INV-M4: Chat generation cannot start while memory draft is active

`startGeneration` checks `memoryDraftState.active` and blocks if a
memory draft is in progress for the same character.

---

## 4. Request Ownership Invariants

### INV-O1: Every generation has a unique genId

`genId` is a monotonically increasing integer from `generationIdCounter`.
It uniquely identifies a generation attempt.

### INV-O2: requestToken is composed from ownerKey + genId

`requestToken = "$ownerKey:$genId"` where `ownerKey = "$scope:$charId:$sessionId"`.
This provides a fully qualified identifier for a specific generation attempt
within a specific session scope.

### INV-O3: Stale responses are rejected by genId check

All callbacks (`onUpdate`, `onComplete`, `onError`) verify `genId` matches the current
`generationStates[charId]` before applying mutations. If `genId` doesn't match,
the callback is either discarded or routed to a stale cleanup path.

### INV-O4: clearGenerationState with expected genId prevents double-cleanup

When `clearGenerationState(charId, expectedGenId)` is called with a `genId` argument,
it only deletes the entry if the current `genId` matches. This prevents a cancel
from clearing the state of a subsequently started generation.

---

## 5. Stream vs Non-Stream Parity

### INV-P1: Final output is identical regardless of transport mode

Both streaming and non-streaming paths must produce the same final `onComplete(text, reasoning)`
result for the same API response. Streaming accumulates incrementally; non-streaming
extracts from the complete JSON — but the final normalized output must be equivalent.

### INV-P2: Reasoning extraction is equivalent

- Streaming: inline reasoning tags extracted incrementally by `StreamAccumulator`
- Non-streaming: inline tags stripped by `normalizeReasoningOutput`, model reasoning
  field merged by `ResponseNormalizer`

Both must produce the same `reasoning` output for the same raw content.

### INV-P3: Cancel behavior differs by design

- Streaming: partial text can be preserved on cancel (incremental accumulation)
- Non-streaming: no partial text is available on cancel (single response)

This asymmetry is intentional and correct.

### INV-P4: Non-streaming fallback preserves semantics

When a server returns a non-SSE response to a streaming request, the app falls back
to `completeJsonResponse()`. The final result must be identical to what streaming
would have produced.

---

## 6. Prompt Semantics Invariants

### INV-PS1: Prompt block order is determined by preset blocks array

The order of blocks in the prompt is fully determined by the preset's `blocks` array.
The preset is the sole controller of prompt topology. Character fields only appear
when a matching preset block ID exists.

### INV-PS2: Keyword scan always precedes vector scan

Keyword lorebook scanning happens inside the Isolate.
Vector scanning happens on the main thread after the isolate completes.
Vector results are deduplicated against keyword results and capped by
`maxInjectedEntries - keywordCount`.

### INV-PS3: History cutoff is newest-first

When context overflows, history is always trimmed from the **oldest** end.
Newer messages are always retained preferentially.

### INV-PS4: Context limit is enforced twice

1. Isolate-side: initial cutoff during prompt building
2. Late-enrichment: re-cutoff after vector lore + memory injection
3. Final guard: if static tokens still exceed `safeContext`, generation aborts

### INV-PS5: Memory injection position is deterministic

- `summary_macro` target: memory is appended to the summary message content
- `summary_block` target (default): memory is inserted before the first history message

Given the same inputs, the injection position is always the same.

### INV-PS6: Memory injection is guarded by token budget

If memory tokens >= 35% of `safeContext` OR memory tokens <= 0, injection is **aborted**.
This prevents memory from starving the context.

### INV-PS7: Regex application order is deterministic

Preset regex scripts run first, then global regex scripts. Within each group,
scripts are applied in array order. Each script runs `trimOut` before `regex`.

### INV-PS8: Preset overrides character settings, not merges

The preset's `blocks` array fully controls what appears in the prompt. Character data
is only included when a preset block with the corresponding `id` resolves it.
If a preset block is disabled or stashed, that character field is omitted.

### INV-PS9: Macro resolution order is fixed

Within a single `replaceMacros` call, macros are resolved in this order:
1. Comment stripping
2. Static character macros (`{{char}}`, `{{user}}`, etc.)
3. Trim macro
4. Session variable macros (`{{setvar::}}`, `{{getvar::}}`)
5. Custom named macros
6. Random/Pick macros
7. Dice macros
8. Date/Time macros
9. Reasoning tag macros
10. Escape handling

### INV-PS10: Recursive lorebook scan is bounded

Recursive keyword scanning is limited to `maxIterations = 5`. This prevents infinite loops
from circular lorebook references.

---

## 7. Cancel and Regenerate Invariants

### INV-A1: Cancel propagates through all layers

When `cancelToken.cancel()` is called:
- `CancelToken.isCanceled` becomes `true`
- Dio cancels the HTTP request and closes the connection
- SSE parser checks cancel state per chunk
- Pipeline loop breaks and calls `onError(CancelException)` with `userCanceled`
- All early cancel checks propagate `userCanceled` from the token

### INV-A2: Regenerate during active generation is silently rejected

If `startGeneration` is called while a non-impersonation generation is active,
the call is silently rejected. This is a UX gap but prevents overlap.

### INV-A3: Impersonation bypasses the overlap guard

Impersonation (`type == 'impersonation'`) is allowed to start even when another
generation is active. This is intentional — impersonation overwrites the existing state.

### INV-A4: Cancel restores pre-generation state

`restoreState()` rolls back: pending swipe, placeholder message, isTyping flag,
and prompt metadata snapshots. The chat must return to the state it was in before
the generation started.

`handleGenerationError` treats ALL `CancelException` (regardless of `userCanceled` flag)
as silent cleanup — no error toast, no error message in chat. Empty placeholder
messages are removed; partial text is preserved via `rollbackPendingSwipe`.

---

## Refactor PR Checklist

Before merging any structural PR, verify:

- [ ] Chat generation still produces correct responses
- [ ] Stop generation preserves partial text when available
- [ ] Regenerate while generating is safely rejected
- [ ] Switching characters during generation continues background generation
- [ ] Prompt block order matches the preset definition
- [ ] Lorebook keyword + vector results are correctly merged
- [ ] Memory injection respects token budget guard
- [ ] History cutoff trims oldest messages first
- [ ] Summary generation returns a string without affecting chat state
- [ ] Memory draft generation doesn't affect chat generation registry
- [ ] Context limit exceeded is caught and shown to the user
- [ ] API not configured is caught and shown to the user
