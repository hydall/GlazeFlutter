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
as a completed message — not discarded. `AbortHandler.abortGeneration()` (called from
`ChatNotifier.abortGeneration()`) reads `streamingStateProvider` and persists partial
text before clearing state.

### INV-C4: `isGenerating` is consistent with actual generation activity

`ChatState.isGenerating == true` iff an SSE stream is currently active for this `charId`.
On app restart, `build()` creates a fresh `ChatState` where `isGenerating` defaults to `false`.

### INV-C5: Session variables are restored on abort/error ✅

If macro expansion mutates `sessionVars` during prompt build, those mutations must
**not** be persisted on any non-happy exit path. Only the success path
(`SavedMessageWriter.writeAssistant`) writes the `pendingSessionVars` snapshot returned
by the isolate.

`SavedMessageWriter.writeError` and `SavedMessageWriter.writeRegenError` keep the
original `currentSession.sessionVars` unchanged. The pre-generation vars from the
isolate only reach the database on the success branch (`stream_generation_service.dart`,
`writeAssistant` call with `pendingSessionVars`).

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
Guard: `AbortHandler.isCurrentGen(genId)` — exposed to the stream as
`isAborted: () => !abortHandler.isCurrentGen(genId)` via `ChatGenerationService.generate()`
→ `StreamGenerationService.run()`. `AbortHandler.nextGenId()` increments `_activeGenId`
on abort and on each new generation start.

---

## 2. Image Generation Invariants

### INV-IG1: Image generation runs after text generation completes

`ChatGenerationService.processImageTags()` is called only after the SSE stream completes
and the assistant message is saved, via `GenerationPipeline._runPostTextSide()`.
It never runs concurrently with text generation. **Exception:** `continueMessage()`
bypasses `GenerationPipeline` — see INV-CM2.

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

### INV-M5: Memory draft approval preserves source range ✅ ENFORCED

`MemoryBookController.approveDraft()` must copy `MemoryDraft.messageRange`
into the resulting `MemoryEntry.messageRange`. This range is provenance used by
source-window exclusion, message-distance recency, diagnostics, and future
excerpt selection.

Compatibility rule: legacy generated entries whose title is only a numeric
range such as `91-105` are read with a `messageRange` backfill in
`MemoryEntry.fromJson()`. This does not rewrite the stored JSON until the book
is saved normally.

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

## 8. Continue Message Invariants

### INV-CM1: Continue message appends to the last assistant message

`ChatNotifier.continueMessage()` calls `ChatGenerationService.generate()` directly
(not `GenerationPipeline.run()`). After the stream completes, it concatenates
`lastMsg.content + generatedMsg.content` onto the existing last assistant message
and persists via `chatRepo.put`. It does not create a new swipe.

Mutex: `continueMessage()` rejects when `_isMemoryDraftActive` (same as
`sendMessage` / `regenerateLastAssistant`) — see INV-M4.

### INV-CM2: Continue skips post-SSE pipeline side effects

Because `continueMessage()` does not use `GenerationPipeline`, the following do
**not** run on the continue path (by design today — document before changing):

- `processImageTags()` — inline `[IMG:GEN]` tags in the continued chunk
- `processExtensions()` — info-block / extension image post-gen
- `notifySyncMessageGenerated()` from the pipeline
- Regen rollback / `restorationMessage` handling from the pipeline

Notification start/complete in `continueMessage()` itself still runs.
If continue should match send/regen post-processing, route it through
`GenerationPipeline` with a dedicated continue mode.

---

## 9. Extension Post-Generation Invariants

### INV-EG1: Extensions run only after a successful normal/regen chat completion

`ExtensionPostGenService.processAfterGeneration()` is invoked from
`ChatGenerationService.processExtensions()`, which is called only from
`GenerationPipeline._runPostTextSide()` after text is saved. It does not run during
SSE streaming and does not run for `continueMessage()` (INV-CM2).

### INV-EG2: Extension failures do not fail chat generation

`ChatGenerationService.processExtensions()` catches errors and logs them; the
assistant message and chat state remain committed.

### INV-EG3: Extensions are gated by settings

Processing is a no-op when `extensionsSettings.enabled` is false or
`activePresetId` is null/empty. Info blocks are stored per `sessionId` via
`infoBlocksProvider`.

### INV-EG4: Block chain does not start if text generation was aborted

`ExtensionPostGenService.processAfterGeneration()` is only reached via
`GenerationPipeline._runPostTextSide()`, which itself only executes when the SSE
stream completes successfully. An aborted generation never reaches the pipeline's
post-text side; therefore the block chain never starts.

### INV-EG5: Extension cancel token is independent of the chat generation cancel token

`ExtensionPostGenService` owns `_extensionBlocksCancelToken` (`CancelToken`).
`cancelBlocks()` cancels this token; it does not touch the chat `_cancelToken` or
`_imgGenCancelToken`. Conversely, aborting chat generation does not cancel in-flight
extension blocks (they have already started post-SSE). Stopped blocks are marked
`BlockRunStatus.stopped` in the DB.

### INV-EG6: `dependsOnPrevious = true` blocks run serially; output chaining is preserved

When a `BlockConfig` has `dependsOnPrevious = true`, `ExtensionPostGenService` awaits
the preceding block's future before starting the dependent block. The preceding block's
`InfoBlock.content` is passed as `previousOutput` to the dependent block's prompt
builder. Blocks with `dependsOnPrevious = false` (default) are launched without
`await` and run concurrently.

### INV-EG7: Image-gen block results are stored via `ImageStorageService`; content holds the path token

After `ImageGenService.generateImage()` succeeds, the image bytes are saved to disk
through `ImageStorageService`. `InfoBlock.content` is set to `[IMG:RESULT:<path>]`
(same format as inline img-gen). The WebView bridge renders this token as an `<img>`
element inside the ext-blocks panel.

### INV-EG8: JS Runner / interactive panel code runs in a sandboxed iframe with null origin ✅ ENFORCED

User-authored JS (`BlockType.jsRunner` and `BlockType.interactive` panel
content) executes in a `<iframe sandbox="allow-scripts">` **without**
`allow-same-origin`. The iframe has a null origin and therefore cannot
reach `window.parent`, `window.flutter_inappwebview`, or any other
parent-context object. API keys live in native Drift and are never
serialised into the JS context.

`glaze.*` calls are the only sanctioned way for the script to talk
back to Dart, and every method is gated by `_requireCapability` (see
INV-JS3). Two execution paths share the same `JsBridgeService`:

* `ChatBridgeController.runJsBlock()` — visual WebView, used while a
  chat is open.
* `JsEngineService.runScript()` — headless `HeadlessInAppWebView`,
  preferred for periodic ticks / background scripts. Falls back to
  the visual bridge on `HeadlessUnavailableError`.

`runSandboxedScript` is implemented in
`assets/chat_webview/bridge/chat_bridge_controller.js` (visual) and
`headless.html` (headless). Both wire the iframe's
`postMessage` channel to a Dart `glazeBridge` handler with a
matching source-check (`e.source !== iframe.contentWindow` /
`!== contentWindow`).

---

## 10. JS Extension Bridge Invariants

### INV-JS1: `glaze.*` calls are gated by per-preset capability permissions (default-deny) ✅ ENFORCED

Every bridge method is wrapped in `JsBridgeService._requireCapability(capabilityId)`.
The default policy is **deny** when no `PermissionCheck` is registered (test seam).
Production wires `_bridgePermissionCheck` in `ChatWebViewWidget`, which reads
`activePresetPermissionsProvider`. The `PresetPermissions` model has 19
toggles; only `showToast` defaults to allow.

| Method | Capability |
|---|---|
| `glaze.getVariables / setVariables / deleteVariable` (`scope: chat`) | `read_chat_vars` / `write_chat_vars` / `delete_chat_vars` |
| same (`scope: character`) | `read_character_vars` / `write_character_vars` / `delete_character_vars` |
| same (`scope: global`) | `read_global_vars` / `write_global_vars` / `delete_global_vars` |
| same (`scope: message`) | `read_message_vars` / `write_message_vars` / `delete_message_vars` |
| `glaze.generateText` | `generate_text` |
| `glaze.triggerGeneration` | `trigger_generation` |
| `glaze.injectPrompt / uninjectPrompt` | `inject_prompt` / `uninject_prompt` |
| `glaze.playAudio` | `play_audio` |
| `glaze.executeCommand` | `execute_command` |
| `glaze.showToast` (default ALLOW) | `show_toast` |

### INV-JS2: Variable writes are atomic; payload is JSON-validated and ≤ 64 KiB ✅ ENFORCED

JS variable writes go through dedicated repo methods that wrap the
read-modify-write in a Drift transaction:

* `ChatRepo.updateSessionVarsJson(sessionId, mutator)` — `chat` scope
* `CharacterRepo.updateExtensionsJson(charId, mutator)` — `character` scope
* `GlobalVariablesRepo.update(mutator)` — `global` scope; serialized
  writes (`_writeLock`) and 64 KiB cap
* `MessageVariablesNotifier.update(sessionId, messageId, mutator)` — in-memory, not persisted

`JsBridgeService._validateJsonValue` enforces JSON compatibility
(no NaN, finite numbers, string keys, ≤ 64 KiB total per payload) and
surfaces failures as `ArgumentError` → bridge `invalid_request` code.

### INV-JS3: `glaze.triggerGeneration` respects generation mutexes (INV-C1, INV-M3/M4) ✅ ENFORCED

`GenerationDispatcher.dispatch(charId, rawMode, reason)` is the only
entry point that touches the chat notifier from a JS call. The
dispatcher returns `TriggerResult`:

* `TriggerNoSession` — no chat state for `charId`
* `TriggerBusy(busyKind: 'chat')` — INV-C1 violated
* `TriggerBusy(busyKind: 'memory_draft')` — INV-M3/M4 violated
* `TriggerAccepted` / `TriggerError`

`auto` mode resolves to `continue` (last msg = assistant) or
`regenerate` (last msg = user). The dispatcher never auto-aborts;
the JS side decides whether to retry. See
`test/trigger_generation_test.dart` for the full contract.

### INV-JS4: `glaze.playAudio` does not leak the audio session ✅ ENFORCED

`AudioBridgeService` keeps a single `AudioPlayer` per widget and
`dispose()`s it on widget dispose. `routeSource` is the pure
`@visibleForTesting` helper that maps the source string to the
matching `audioplayers` `Source` subclass. Built-in cues
(`click` / `alert` / `haptic`) bypass the audio player entirely
(`SystemSound` / `HapticFeedback`).

### INV-JS5: `executeCommand` routes `/trigger`, `/getvar`, `/setvar`, `/inject`, `/toast` to the same services as the dedicated bridge methods ✅ ENFORCED

`buildWiredCommandRegistry(WiredCommandDeps)` is the production
default. Each handler delegates to the same service that powers the
dedicated `glaze.*` method:

* `/trigger` → `TriggerGenerationHandler.handle` (mirrors `glaze.triggerGeneration`)
* `/getvar` / `/setvar` → `JsBridgeService.dispatch` (mirrors `glaze.getVariables` / `setVariables`)
* `/inject` → `RuntimePromptInjectionNotifier.inject`
* `/toast` → `JsBridgeToastController.show` (severity-aware)

`buildDefaultCommandRegistry` is retained for tests/CMS — its
handlers echo arguments. The `CommandRegistry.run` contract catches
all handler exceptions and returns `CommandResult.error`.

### INV-JS6: Periodic scheduler pauses on app background, never produces catch-up ticks ✅ ENFORCED

`PeriodicTriggerScheduler` is a `WidgetsBindingObserver`. On
`paused` / `inactive` / `hidden` / `detached` it cancels every timer.
On `resumed` it rebuilds the timer set from the current active preset;
the first tick after a long backgrounding period is **not** a catch-up
firing — the timer is fresh.

`_tick` is `unawaited` (fire-and-forget): the chain itself owns its
own cancel token and writes via `infoBlocksProvider.notifier.addOrReplace()`
without blocking the scheduler. The `debugLifecycleState` test seam
in `periodic_lifecycle_test.dart` exercises the full pause/resume
contract.

---

## Refactor PR Checklist

Before merging any structural PR:

- [ ] Chat generation produces correct responses end-to-end
- [ ] Stop generation (abort) preserves partial text when available
- [ ] Regenerate while generating aborts the current generation first
- [ ] Switching characters during generation continues background generation
- [ ] Prompt block order matches preset definition
- [ ] Vector scan runs before keyword scan; results deduplicated
- [x] Memory injection respects token budget (PR-B C13 / INV-PS4)
- [ ] History cutoff trims oldest messages first
- [ ] Summary returns a string without affecting chat state
- [x] Memory draft mutex with chat generation (PR-B C12 / INV-M3, INV-M4)
- [ ] Image generation completes after text generation (not on continue path — INV-CM2)
  - [ ] Extensions post-gen runs after normal/regen only (INV-EG1; not on continue)
  - [ ] Block chain does not start on aborted generation (INV-EG4)
  - [ ] Extension cancel token is separate from chat cancel token (INV-EG5)
  - [ ] `dependsOnPrevious` blocks await the preceding block; output is chained (INV-EG6)
  - [ ] Image-gen block results stored via ImageStorageService; content = `[IMG:RESULT:<path>]` (INV-EG7)
  - [ ] JS Runner / interactive panel code runs in null-origin iframe (INV-EG8)
  - [ ] Bridge `glaze.*` calls gated by preset capabilities (INV-JS1)
  - [ ] Variable writes are atomic + JSON-validated + ≤ 64 KiB (INV-JS2)
  - [ ] `glaze.triggerGeneration` respects generation mutexes (INV-JS3)
  - [ ] `glaze.playAudio` does not leak the audio session (INV-JS4)
  - [ ] `executeCommand` wired registry routes to the same services (INV-JS5)
  - [ ] Periodic scheduler pauses on app background; no catch-up tick (INV-JS6)
- [ ] Context limit exceeded shows an error to the user
- [ ] API not configured shows an error to the user
- [ ] Abort closes the TCP connection (not just UI state)
- [x] Session variables not persisted on abort/error (PR-B C11 / INV-C5)
