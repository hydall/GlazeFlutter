# Generation Invariants — Glaze Flutter

Formal runtime behavior that must not change during any refactor.
Every structural PR must preserve these invariants or explicitly document a deviation.

---

## 1. Chat Generation Invariants

### INV-C1: At most one active chat generation per `charId`

`ChatNotifier.sendMessage()` checks `state.isGenerating` before starting.
If a generation is already active for this character, the call is rejected.

### INV-C2: Generation state is always eventually cleaned up

For every generation start, there must be a matching cleanup on every exit:
- Completion
- Error
- Abort (`abortGeneration()`)
- App restart (fresh `ChatState` with `isGenerating = false`)

Note: `ChatNotifier` uses `ref.keepAlive()`, so provider disposal is not a cleanup path. State resets on app restart when `build()` runs fresh.

### INV-C3: Partial text is preserved on abort

When the user aborts mid-stream and partial text exists, the partial response is saved
as a completed message — not discarded. `ChatNotifier.abortGeneration()` reads
`streamingStateProvider` and persists partial text before clearing state.

### INV-C4: `isGenerating` is consistent with actual generation activity

`ChatState.isGenerating == true` iff an SSE stream is currently active for this `charId`.
On app restart, `build()` creates a fresh `ChatState` where `isGenerating` defaults to `false`.

### INV-C5: Session variables are restored on abort/error ✅

If macro expansion mutates `sessionVars` during prompt build, those mutations must
**not** be persisted on any non-happy exit path. Only the success path (`_saveAssistantMessage`)
writes the `pendingSessionVars` snapshot returned by the isolate.

`SavedMessageWriter.writeError` and `SavedMessageWriter.writeRegenError` keep the
original `currentSession.sessionVars` unchanged. The pre-generation vars from the
isolate only reach the database on the success branch (line 190 of
`stream_generation_service.dart`).

`currentSessionVars` lives only inside the isolate's local scope during
`buildPrompt()` (`lib/core/llm/prompt_builder.dart:195`) — nothing is persisted
before the success branch, so there is no rollback to perform. The fix in PR-B
(C11) was simply to stop **adding** `pendingSessionVars` to the error write paths
where they were being leaked into the database despite the abort.

### INV-C6: Background generation continues independently

When generation is running for character A and the user switches to character B,
generation for A continues. `ChatNotifier` is keyed by `charId` — each character
has its own independent state. Switching screens does not abort other characters.

### INV-C7: Stale completions are discarded

If an SSE stream completes after a new generation has started (e.g. very fast regen),
the stale callback must detect the mismatch and discard the result.
Guard: compare `_activeGenId` before writing to state. `ChatGenerationService`
receives `isAborted: () => _activeGenId != genId`.

---

## 2. Image Generation Invariants

### INV-IG1: Image generation runs after text generation completes

`ChatGenerationService.processImageTags()` is called only after the SSE stream completes
and the assistant message is saved. It never runs concurrently with text generation.

### INV-IG2: Image generation has independent abort infrastructure

Uses `_imgGenCancelToken` (separate from the text `_cancelToken`) and `isGeneratingImage`
state (separate from `isGenerating`).

### INV-IG3: Image generation abort clears `isGeneratingImage`

Both `abortGeneration()` and `cancelImageGeneration()` clear the flag.
Cancelled image tags are replaced with `[IMG:ERROR:...]`.

---

## 3. Summary Generation Invariants

### INV-S1: Summary is always non-streaming

`SummaryService.generateSummary()` uses `_dio.post()` (plain HTTP POST). No SSE.

### INV-S2: Summary does not create generation registry entries

Summary generation does not touch `ChatState.isGenerating` or any `charId`-keyed
generation guard. It has no `CancelToken` — once started, it cannot be aborted.

### INV-S3: Summary does not mutate chat messages

Summary generation only reads history and writes to `ChatSummary` via `SummaryRepo`.
It must not modify `ChatSession.messages`.

---

## 4. Memory Draft Generation Invariants

### INV-M1: Memory draft does not use chat generation state

`MemoryDraftGenerator` owns its own `SseClient` and receives an external `CancelToken`.
It never reads or writes `ChatState.isGenerating`.

### INV-M2: Memory draft is always non-streaming

`MemoryDraftGenerator.generate()` calls the API with `stream: false` unconditionally.

### INV-M3: Memory draft cannot start while chat generation is active ✅ ENFORCED (PR-B C12)

`MemoryBookController.generateDraft()` rejects a start request
when `chatProvider(_charId).value?.isGenerating == true` for the
target character. The user gets a "Chat generation is active"
error message via the existing `onError` callback.

The check is read-only on the chat notifier — it does not wait for
the generation to finish; the user must explicitly abort the chat
generation or wait for it to complete.

### INV-M4: Chat generation cannot start while memory draft is active ✅ ENFORCED (PR-B C12)

`ChatNotifier.sendMessage()`, `ChatNotifier.regenerateLastAssistant()`,
and `ChatNotifier.continueMessage()` reject a start request when a
memory draft is currently being generated for the same `sessionId`.

Both invariants share a single new state container:
`lib/features/memory/state/memory_active_drafts_provider.dart`
(`StateNotifierProvider<MemoryActiveDraftsNotifier, Set<String>>`).
Drafts are added to the set when generation starts and removed when
it ends (success, error, or cancel).

Shared state contract is pinned by
`test/characterization/memory_draft_mutex_test.dart` (7 tests).

---

## 5. Prompt Semantics Invariants

### INV-PS1: Prompt block order is determined by the preset's `blocks` array

The preset's `blocks` list fully controls what appears in the prompt and in what order.
Character fields appear only when a matching preset block ID resolves them.
If a block is disabled, that field is omitted. `PromptBuilder` is the sole enforcer.

### INV-PS2: Vector scan runs before keyword scan; keyword deduplicates vector

1. Vector lorebook scan runs async in `PromptPayloadBuilder.buildFromSession()` — results packed into `PromptPayload.vectorEntries`.
2. Keyword lorebook scan runs synchronously in `PromptBuilder` (inside the Dart isolate).
3. `mergeKeywordVector()` deduplicates: vector entries whose IDs appear in keyword results are dropped. Keyword results always win.

### INV-PS3: History cutoff is oldest-first

When context overflows, history is trimmed from the **oldest** end.
`ContextCalculator._trimHistory()` walks backwards from the newest end, accumulating
messages until the budget is full. The oldest messages are dropped because they are never accumulated.

### INV-PS4: Memory injection is guarded by a token budget ✅ ENFORCED (PR-B C13)

`MemoryInjectionService.buildInjection()` enforces a hard upper bound
on the tokens spent on memory injection. The cap is configured per
`MemoryBookSettings.maxInjectionBudgetPercent` (default `0.35`, i.e.
35% of the active context budget).

**Formula:**

```
maxInjectionTokens = max(0, contextBudgetTokens) * maxInjectionBudgetPercent
```

where `contextBudgetTokens` is supplied by the caller (typically
`apiConfig.contextSize`). Entries are kept in score-descending
order; once the running total of `estimateTokens(entry.content)`
exceeds `maxInjectionTokens`, the tail of the list is dropped.

If `contextBudgetTokens` is not supplied (null/0) or
`maxInjectionBudgetPercent <= 0`, the guard is a no-op — legacy
behaviour is preserved for callers that don't yet pass the budget.

The percentage default lives in `MemoryBookSettings` (see
`lib/core/models/memory_book.dart`) so per-book overrides can be
added in the future without changing the service signature.

### INV-PS5: Memory injection position is deterministic

Memory can be injected into the prompt via one of two mechanisms,
both keyed off `MemoryGlobalSettings.injectionTarget` and
`MemoryBookSettings.injectionTarget` (per-book override):

* **`hard_block`** (default): a hard system message with
  `blockId='memory'` and `blockName='Memory Book'` is added before
  the first history message. The check is skipped when the preset
  already has a block with `id='memory'` or contains the `{{memory}}`
  macro (so the user can disable the hard block by adding an
  explicit `enabled: false` block in the preset, or by placing
  `{{memory}}` in a custom wrapper).

* **`macro`**: no hard block is added automatically. Memory is
  reachable only through the `{{memory}}` macro inside the preset,
  which gives the user full control over placement and wrapper tags.

Summary injection is independent and unchanged: the `{{summary}}`
macro resolves to `MacroContext.summaryContent` (user-authored
summary only — no memory piggyback). It is the user's responsibility
to place `{{summary}}` in a preset block if they want it injected.

**Accounting rule** (token breakdown): preset chrome is attributed
to `sourceTokens['preset']` and dynamic macro injections
(`{{summary}}`, `{{memory}}`, `{{lorebooks}}`, `{{guidance}}`) are
attributed to their dedicated buckets (`sourceTokens['summary']`,
`sourceTokens['memory']`, etc.) — never both.

Concretely, `resolveBlockContent` returns TWO flavours of the
resolved content:

* `content` — fully expanded (what the LLM actually sees), used
  for `messages` and the merged `PromptMessage` system block.
* `contentForAccounting` — same shape, but with dynamic macro
  injections blanked out (`replaceMacros` is run against a context
  where `summaryContent` / `memoryContent` / `lorebooksContent` /
  `guidanceText` are null). This is what `attributionBlocks` see, so
  `sourceTokens['preset']` reports ONLY the preset's static chrome.

Before this split, a preset block that contained `{{memory}}` would
double-count the memory tokens — once via the `id='memory'`
hard-block attribution and once via the merged preset buffer that
included the expanded content.

**Preset-only accounting** (`contentForAccounting` /
`MacroContext.forPresetAccounting()`): counts only text that belongs
to the preset file. **Blanked** (counted elsewhere): character fields
(`{{char}}`, `{{description}}`, `{{personality}}`, `{{scenario}}`,
`{{mesExamples}}`), persona (`{{user}}`, `{{persona}}`), and runtime
injections (`{{summary}}`, `{{memory}}`, `{{lorebooks}}`,
`{{guidance}}`). Those appear in `macroTokens` and/or dedicated
`StaticBlock` buckets (`description`, `personality`, `memory`, …).

**Still counted as preset**: literal block text, `{{setvar::}}` /
`{{setglobalvar::}}` definitions, `{{getvar::}}` expansions of
in-preset variables, and custom global vars set inside the preset.

Dedicated injection blocks (`char_card`, `char_personality`, …):
`contentForAccounting` uses **raw block content only**, not injected
character/persona payloads.

`presetNetTokens` equals `sourceTokens['preset']` (no further
subtraction — external macros are already excluded in accounting).

### INV-PS7: Macro resolution order is fixed

Within a single `MacroEngine.replaceMacros()` call, macros resolve in this order:
1. Comment stripping
2. Static character macros
3. `{{reasoningPrefix}}` / `{{reasoningSuffix}}`
4. `{{summary}}` / `{{memory}}` / `{{lorebooks}}` / `{{guidance}}`
5. Trim
6. Session variable macros (`setvar`/`getvar`)
7. Global variable macros (`setglobalvar`/`getglobalvar`)
8. Custom named macros
9. `{{random::}}` / `{{pick::}}`
10. Dice `{{roll::}}`
11. Date/Time
12. Escape handling

### INV-PS8: Recursive lorebook scan is bounded

`LorebookScanner` limits recursion to `maxIterations = 5` when `recursiveScan` is enabled,
or `1` when disabled. This prevents infinite loops from circular entry references.

### INV-PS9: Block-level append-to-last-user-message

`PresetBlock.appendToLastMessage = true` causes the block's content (after macro expansion) to be **appended to the last user-role message in the chat history** at prompt-assembly time.

Rules (enforced in `lib/core/llm/prompt_builder.dart:_assembleMessages` via `_applyAppendToLastMessage`):

1. The block's own `role` is irrelevant in this mode — the content is always merged into the **last** user message found in `historyMsgs`. Block role may be `system`, `user`, or `assistant`; the merged message keeps the user role.
2. Macros (`{{lorebooks}}`, `{{summary}}`, etc.) are expanded **before** append, in `resolveBlockContent()` — see INV-PS7. A block like `<lorebooks>{{lorebooks}}</lorebooks><summary>{{summary}}</summary>` expands to fully-rendered text and is appended as-is.
3. Multiple blocks with `appendToLastMessage = true` are appended in **preset order**, joined with `\n\n`. Their `blockName`s are listed in the merged message's `blockName` as `"<orig> + <name1>, <name2>"` for preview attribution.
4. If the history has no user-role messages (empty chat / first message is assistant or system), the appended blocks are **silently dropped**.
5. The block is still subject to the standard `enabled` and `isStashed` gates — disabled or stashed blocks are ignored.
6. The append happens in `_assembleMessages` **after** `HistoryAssembler.assemble(history)` and **before** `interleaveDepthWithHistory`, so depth blocks are still positioned by history depth and regex pipeline sees a single merged user message.

---

## 6. Stream vs Non-Stream Parity

### INV-P1: Final output is identical regardless of transport mode

Both streaming (SSE) and non-streaming paths produce the same final
`(text, reasoning)` pair for the same API response content.
Both paths use `StreamAccumulator` for reasoning extraction.

### INV-P2: Reasoning extraction is equivalent

Both streaming and non-streaming paths use `StreamAccumulator` to split
`<think…>` tags. The non-streaming path feeds the entire response as one
delta through the same accumulator, producing identical output.

### INV-P3: Abort behavior differs by design

- Streaming: partial text can be preserved (incremental accumulation)
- Non-streaming: no partial text available on abort

This asymmetry is intentional and correct.

---

## 7. Abort Invariants

### INV-A1: Abort propagates to the HTTP layer

When `ChatNotifier.abortGeneration()` is called:
1. `_activeGenId++` — invalidates stale callbacks
2. `_cancelToken?.cancel()` — propagates to Dio, closes the SSE stream
3. `_imgGenCancelToken?.cancel()` — cancels any in-flight image generation
4. Manual state restoration + partial text persist in `abortGeneration()` itself

Cancelling only UI state while leaving the TCP connection open is a bug.

### INV-A2: Abort restores pre-generation state

On abort, `ChatNotifier.abortGeneration()` restores:
- The placeholder message (converted to partial or removed)
- `ChatState.isGenerating → false`
- `ChatState.isGeneratingImage → false`
- Session variables mutated during prompt build — ✅ on success only (see INV-C5)

### INV-A3: Regen during active generation aborts first

`ChatNotifier.regenerateLastAssistant()` does not simply reject when generation is active.
It calls `abortGeneration()` first, then proceeds with the new generation.
If abort fails to clear `isGenerating`, the subsequent check rejects.

---

## 8. Continue Message Invariant

### INV-CM1: Continue message appends to the last assistant message

`ChatNotifier.continueMessage()` reuses `ChatGenerationService.generate()` but
post-processes the result by concatenating `lastMsg.content + generatedMsg.content`.
It does not create a new message or swipe.

---

## Refactor PR Checklist

Before merging any structural PR:

- [ ] Chat generation produces correct responses end-to-end
- [ ] Stop generation (abort) preserves partial text when available
- [ ] Regenerate while generating aborts the current generation first
- [ ] Switching characters during generation continues background generation
- [ ] Prompt block order matches preset definition
- [ ] Vector scan runs before keyword scan; results deduplicated
- [ ] Memory injection does not exceed context budget (⚠️ no guard yet)
- [x] Memory injection does not exceed context budget (PR-B C13)
- [ ] History cutoff trims oldest messages first
- [ ] Summary returns a string without affecting chat state
- [x] Memory draft does not interact with chat generation state (PR-B C12)
- [ ] Image generation completes after text generation, has separate abort
- [ ] Context limit exceeded shows an error to the user
- [ ] API not configured shows an error to the user
- [ ] Abort closes the TCP connection (not just UI state)
- [x] Session variables are restored on abort/error (PR-B C11)
