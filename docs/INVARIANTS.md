# Generation Invariants — Glaze Flutter

Formal runtime behavior that must not change during any refactor.
Every structural PR must preserve these invariants or explicitly document a deviation.

PR checklist: bottom of this file.

---

## 1. Chat Generation Invariants

### INV-C1: At most one active chat generation per `charId`

`ChatNotifier.sendMessage()` / `generate()` checks `state.isGenerating` before starting.
If a generation is already active for this character, the call is rejected.

### INV-C2: Generation state is always eventually cleaned up

For every generation start, there must be a matching cleanup on every exit:
- Completion
- Error
- Abort (`stopGeneration()`)
- Screen dispose / notifier disposal

### INV-C3: Partial text is preserved on abort

When the user aborts mid-stream and partial text exists, the partial response is saved
as a completed message — not discarded. `ChatGenerationService` must persist partial text
before clearing state.

### INV-C4: `isGenerating` is consistent with actual generation activity

`ChatState.isGenerating == true` iff an SSE stream is currently active for this `charId`.
On hot restart / provider rebuild, `isGenerating` must be reset to `false`.

### INV-C5: Session variables are restored on abort/error

If macro expansion mutates `sessionVars` during prompt build, those mutations must be
rolled back on every non-happy exit path. `ChatGenerationService` must restore the
pre-generation snapshot on abort or error.

### INV-C6: Background generation continues independently

When generation is running for character A and the user switches to character B,
generation for A continues. `ChatNotifier` is keyed by `charId` — each character
has its own independent state. Switching screens does not abort other characters.

### INV-C7: Stale completions are discarded

If an SSE stream completes after a new generation has started (e.g. very fast regen),
the stale `onComplete` callback must detect the mismatch and discard the result.
Guard: compare `genId` / `CancelToken` before writing to state.

---

## 2. Summary Generation Invariants

### INV-S1: Summary is always non-streaming

`SummaryService` always calls the API with `stream: false`. No SSE.

### INV-S2: Summary does not create generation registry entries

Summary generation does not touch `ChatState.isGenerating` or any `charId`-keyed
generation guard. It has its own abort controller owned by the caller.

### INV-S3: Summary does not mutate chat messages

Summary generation only reads history and writes to `ChatSummary` via `SummaryRepo`.
It must not modify `ChatSession.messages`.

---

## 3. Memory Draft Generation Invariants

### INV-M1: Memory draft does not use chat generation state

`MemoryDraftGenerator` owns its own abort infrastructure (per-draft `CancelToken`).
It never reads or writes `ChatState.isGenerating`.

### INV-M2: Memory draft is always non-streaming

`MemoryDraftGenerator` calls the API with `stream: false` unconditionally.

### INV-M3: Memory draft cannot start while chat generation is active

`MemoryDraftGenerator.generate()` must check `ChatState.isGenerating` for the same
`charId` and reject if active.

### INV-M4: Chat generation cannot start while memory draft is active

`ChatNotifier.sendMessage()` must check whether a memory draft generation is currently
running for the same `charId` and reject if so.

---

## 4. Prompt Semantics Invariants

### INV-PS1: Prompt block order is determined by the preset's `blocks` array

The preset's `blocks` list fully controls what appears in the prompt and in what order.
Character fields appear only when a matching preset block ID resolves them.
If a block is disabled, that field is omitted. `PromptBuilder` is the sole enforcer.

### INV-PS2: Keyword scan always precedes vector scan

Keyword lorebook scan runs synchronously in `PromptBuilder` (inside the Dart isolate).
Vector scan runs async after the isolate completes, in `PromptPayloadBuilder`.
Vector results are deduplicated against keyword results.

### INV-PS3: History cutoff is oldest-first

When context overflows, history is trimmed from the **oldest** end.
Newer messages are always retained preferentially.
`ContextCalculator` enforces this: it walks from index 0 forward, dropping old messages.

### INV-PS4: Memory injection is guarded by a token budget

If memory tokens ≥ 35% of `safeContext` OR memory tokens ≤ 0 → injection skipped.
`MemoryInjectionService` enforces this before any injection attempt.

### INV-PS5: Memory injection position is deterministic

Given the same inputs, the injection point is always the same:
- `summary_block` target (default): memory inserted before the first history message
- `summary_macro` target: memory appended to the summary block content

### INV-PS6: Regex application order is deterministic

Preset regex scripts run first, then global regex scripts.
Within each group, scripts are applied in array order.
`RegexService` enforces this.

### INV-PS7: Macro resolution order is fixed

Within a single `MacroEngine.apply()` call, macros resolve in this order:
1. Comment stripping
2. Static character macros
3. Trim
4. Session variable macros (`setvar`/`getvar`)
5. Global variable macros
6. Custom named macros
7. `{{random::}}` / `{{pick::}}`
8. Dice `{{roll::}}`
9. Date/Time
10. Reasoning tags
11. Escape handling

### INV-PS8: Recursive lorebook scan is bounded

`LorebookScanner` limits recursion to `maxIterations = 5`.
This prevents infinite loops from circular entry references.

---

## 5. Stream vs Non-Stream Parity

### INV-P1: Final output is identical regardless of transport mode

Both streaming (SSE) and non-streaming paths must produce the same final
`(text, reasoning)` pair for the same API response content.

### INV-P2: Reasoning extraction is equivalent

- Streaming: `StreamAccumulator` splits `<think>…</think>` tags incrementally with
  partial-suffix lookahead to handle tag boundaries across chunk splits.
- Non-streaming: `ResponseNormalizer.normalizeReasoningOutput()` strips tags from
  the final string; `reasoning_content` field merged separately.

Both must produce the same `reasoning` output for the same raw content.

### INV-P3: Abort behavior differs by design

- Streaming: partial text can be preserved (incremental accumulation)
- Non-streaming: no partial text available on abort

This asymmetry is intentional and correct.

---

## 6. Abort Invariants

### INV-A1: Abort propagates to the HTTP layer

When `ChatNotifier.stopGeneration()` is called, the `CancelToken` passed to
`SseClient` must be cancelled. This closes the underlying Dio request and stops
the SSE stream. Cancelling only UI state while leaving the TCP connection open is a bug.

### INV-A2: Abort restores pre-generation state

On abort, `ChatGenerationService` must restore:
- The placeholder message (remove or convert to partial)
- `ChatState.isGenerating → false`
- Any session variables mutated during prompt build

### INV-A3: Regen during active generation is rejected

`ChatNotifier.regenerate()` must check `isGenerating` and reject if active.

---

## Refactor PR Checklist

Before merging any structural PR:

- [ ] Chat generation produces correct responses end-to-end
- [ ] Stop generation preserves partial text when available
- [ ] Regenerate while generating is safely rejected
- [ ] Switching characters during generation continues background generation
- [ ] Prompt block order matches preset definition
- [ ] Keyword scan runs before vector scan; results deduplicated
- [ ] Memory injection respects the 35% token budget guard
- [ ] History cutoff trims oldest messages first
- [ ] Summary returns a string without affecting chat state
- [ ] Memory draft does not interact with chat generation state
- [ ] Context limit exceeded shows an error to the user
- [ ] API not configured shows an error to the user
- [ ] Abort closes the TCP connection (not just UI state)
