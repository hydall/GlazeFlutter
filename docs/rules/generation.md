# Generation Lifecycle Rules

Mandatory rules for any code that participates in chat generation, summary, memory draft, or transport.

Full formal invariants with code references: `docs/INVARIANTS.md`

---

## Generation types and their scopes

| Type | State owner | Streaming | Abort |
|------|-------------|-----------|-------|
| Chat | `ChatState.isGenerating` per `charId` | Yes (SSE) | `AbortHandler`: `CancelToken` + `_activeGenId` |
| Image gen | `AbortHandler._imgGenCancelToken` + `isGeneratingImage` | No (one-shot) | Separate cancel token from text SSE |
| Summary | Widget-local in `summary_sheet.dart` | No | Widget-scoped `CancelToken` |
| Memory draft | `MemoryBookController` | No | Per-draft `CancelToken`; mutex via `memory_active_drafts_provider` |
| Ext blocks | `ExtensionPostGenService._extensionBlocksCancelToken` | No (per-block LLM call) | `cancelBlocks()` — independent of chat cancel token (INV-EG5) |
| JS extension (`glaze.generateText`) | `ActiveApiConfigProvider` (active or connection-profile slot) | No (one-shot, 55 s timeout) | Per-call `CancelToken` from the bridge handler |
| JS extension (`glaze.triggerGeneration`) | `GenerationDispatcher` | Routed through `ChatNotifier.continueMessage` / `regenerateLastAssistant` | Reuses chat + memory-draft mutex (INV-JS3) |
| JS extension periodic | `PeriodicTriggerScheduler` (`Timer.periodic`) | No (side-effect tick) | Each tick creates a fresh `CancelToken`; cancelled ticks are swallowed |

`ChatNotifier` owns `AbortHandler` per `charId` and delegates `abortGeneration()` to it.

---

## Entry paths (chat)

| User action | Orchestrator | Post-SSE (`GenerationPipeline`) |
|-------------|--------------|----------------------------------|
| Send message | `_runGeneration` → `GenerationPipeline.run()` | Yes — image tags, extensions, sync |
| Regenerate | `_runGeneration` → `GenerationPipeline.run()` | Yes |
| Continue | `ChatGenerationService.generate()` directly | **No** — see INV-CM2 |

---

## Mutual exclusion ✅ ENFORCED (PR-B C12)

Chat generation and memory draft **cannot** overlap for the same session/character:

- `MemoryBookController.generateDraft()` rejects when `chatProvider(charId).isGenerating`.
- `sendMessage` / `regenerateLastAssistant` / `continueMessage` reject when
  `memoryActiveDraftsProvider` contains the session id.

See `docs/INVARIANTS.md` INV-M3, INV-M4 and
`test/characterization/memory_draft_mutex_test.dart`.

Image generation runs after text generation completes on the normal/regen path
(`GenerationPipeline` → `processImageTags()`). Summary is independent.

---

## genId / CancelToken ownership

Every chat generation gets a unique id from `AbortHandler.nextGenId()` (monotonic
`_activeGenId`). All SSE callbacks **must** treat the generation as stale when
`!abortHandler.isCurrentGen(expectedGenId)` before mutating `ChatState`.

```dart
// Pattern passed into StreamGenerationService
isAborted: () => !abortHandler.isCurrentGen(genId),
```

`AbortHandler.setCancelToken()` attaches the Dio `CancelToken` for the active gen.
Image generation uses a separate `_imgGenCancelToken`.

---

## Abort signal chain

```
ChatNotifier.abortGeneration()
  → AbortHandler.abortGeneration()
      → _activeGenId++              ← invalidates pending callbacks
      → _cancelToken?.cancel()      ← propagates to Dio / SSE
      → _imgGenCancelToken?.cancel()
      → read streamingStateProvider → persist partial text if any
      → isGenerating / isGeneratingImage → false
      → restoration snapshot handling

Separately:
  → SseClient: DioException(cancel)
  → StreamGenerationService: isAborted() → early return, isGenerating false
```

**Never break this chain.** If `CancelToken` doesn't reach `Dio`, stop only clears UI
while the TCP stream continues.

Partial text persistence lives in `AbortHandler`, not in `ChatNotifier` directly.
See INV-C3 in `docs/INVARIANTS.md`.

---

## State cleanup on every exit path

`ChatState.isGenerating` must return to `false` on: completion, error, abort, app
restart (`ChatNotifier.build()` fresh state). `ChatNotifier` uses `ref.keepAlive()` —
provider disposal is not a cleanup path.

---

## Prompt ordering (do not reorder)

1. Vector lorebook scan (async, `PromptPayloadBuilder`, before isolate)
2. Keyword lorebook scan (sync, `PromptBuilder`, inside isolate)
3. Merge keyword + vector (keyword wins; dedupe vector by id)
4. Memory candidate selection + excerpt packing (`memoryPackingMode`: full / hybrid / chunk_first — see `docs/ARCHITECTURE.md` §4)
5. Context cutoff — oldest messages trimmed first; deferred `{{memory}}` macro finalization runs after cutoff when `memorySelection` is present

---

## Reasoning / thinking controls

`requestReasoning=false` and/or `omitReasoning=true` mean Glaze should not ask
the transport for provider-native reasoning and should not persist reasoning
unless the provider explicitly returns it on an enabled final response. Do not
interpret these flags as a universal provider-side "thinking off" switch.

Provider notes:
- OpenAI-compatible/custom transports omit `reasoning_effort` when reasoning is omitted.
- Anthropic/Gemini transports omit their native thinking config when reasoning is omitted.
- Gemini 3.x may still think internally by default and may report/bill thought tokens. Gemini 3.1 Pro documents thinking levels, not a guaranteed full off switch.
- Avoid sending undocumented fields such as `reasoning: { exclude: true }` globally. Add provider-specific body fields only behind explicit protocol/provider support and tests.

Studio Mode:
- Intermediate Studio agents always force reasoning off/omitted.
- The final Studio agent inherits the resolved `ApiConfig` reasoning settings.
- Studio strips prompt-level hidden-reasoning directives from final-agent instructions when reasoning is disabled/omitted, but this only affects prompt text, not provider-internal thinking.

---

## Session variables on abort/error ✅ ENFORCED (PR-B C11)

`pendingSessionVars` from the isolate are written only on the success path
(`SavedMessageWriter.writeAssistant`). Error and regen-error paths keep the
pre-generation `sessionVars`. See INV-C5.

---

## Continue message

`ChatNotifier.continueMessage()`:

1. Calls `ChatGenerationService.generate()` (SSE + prompt build) directly.
2. Appends streamed content to the **existing** last assistant message.
3. Does **not** run `GenerationPipeline` post-steps (image tags, extensions, sync).

See INV-CM1, INV-CM2 before changing this path.

---

## Extension post-generation

After normal/regen completion, `GenerationPipeline` calls
`ChatGenerationService.processExtensions()` → `ExtensionPostGenService`.
Failures are logged only (INV-EG2). Gated by `extensionsSettings.enabled` and
active preset id (INV-EG3). The block chain does not start on aborted or errored
generation (INV-EG4).

### Block triggers

`BlockTrigger` controls when a block runs. The chain filter is enforced by
`_runChain(trigger:)` in `ExtensionPostGenService` — the same chain is
reused for all three trigger types:

| `BlockTrigger` | Entry point | Cancel / lifecycle |
|---|---|---|
| `afterAssistant` | `processAfterGeneration` → `runBlocksForMessage` | Uses `_extensionBlocksCancelToken` (INV-EG5) |
| `afterUser` | `ChatNotifier.sendMessage` → `unawaited(_dispatchAfterUserBlocks)` → `runAfterUserBlocks` | Same cancel token, fire-and-forget from the notifier's perspective |
| `periodic` | `PeriodicTriggerScheduler` → `Timer.periodic(periodicIntervalSeconds)` → `runJsBlock` (no chain) | Each tick creates a fresh `CancelToken`; the scheduler itself pauses on app background (INV-JS6) |

### Block execution model

```
blocks = preset.blocks.where(enabled && trigger == requested).sortBy(order)
prevFuture = null
for block in blocks:
    blockFuture = _runSingleBlock(block, prevFuture?.content)
    if block.dependsOnPrevious:
        prevFuture = await blockFuture   // serial
    else:
        prevFuture = null                // parallel; side-effect via .then(addOrReplace)
```

- **Serial** (`dependsOnPrevious = true`): block awaits the previous block; receives its output as `previousOutput`.
- **Parallel** (`dependsOnPrevious = false`): block is launched without `await`; `unawaited(future.then(...))` writes the result via `infoBlocksProvider.notifier.addOrReplace()`.

### Block types

| `BlockType` | Engine | Notes |
|---|---|---|
| `infoblock` | `InfoBlockService` (LLM) | Result stored in `InfoBlock.content` |
| `imageGen` | `ImageGenService` (LLM agent → image API) | `[IMG:RESULT:<path>]` token in `InfoBlock.content` |
| `jsRunner` | `JsEngineService` (preferred) → `ChatBridgeController.runJsBlock` (fallback) | Script output becomes the block content; null origin iframe (INV-EG8) |
| `interactive` | `PanelHostService` (LLM agent → sandboxed iframe panel) | HTML persisted to `InfoBlock.content`; panel is rendered as a live iframe island |

### Cancel

`ExtensionPostGenService.cancelBlocks()` cancels `_extensionBlocksCancelToken`.
Each `_runSingleBlock` checks the token before and after every `await`; cancelled
blocks are marked `BlockRunStatus.stopped`. Does **not** affect the chat text cancel
token or in-progress image generation.

### Bridge feedback

On status change, call `ChatBridgeController.updateBlockStatus(messageId, aggregatedStatus)`.
On panel open/update, call `ChatBridgeController.showExtBlocksPanel(messageId, blocks)`.

### JS bridge abort chain

`glaze.generateText` (JS bridge → `SseClient.streamChatCompletion`) takes a
fresh `CancelToken` per call. `_generateBridgeText` in
`ChatWebViewWidget` enforces a 55-second timeout and cancels the token
on expiry. The token is independent of the chat text generation
token — aborting the chat does NOT cancel in-flight JS generate calls.

`glaze.triggerGeneration` reuses the chat path entirely — see
`GenerationDispatcher.dispatch` for the mutex / abort chain.

---

## Adding a new generation path

1. Define abort mechanism (`AbortHandler` or separate `CancelToken`).
2. Add mutual exclusion in **both** directions if it shares a `charId` / session.
3. Verify `isCurrentGen(genId)` before mutating shared state after every `await`.
4. Clear `isGenerating*` on every exit path.
5. Decide whether post-SSE steps (image tags, extensions) must run — use
   `GenerationPipeline` or document an explicit exception like continue.

---

## PR verification checklist

Before merging any generation-related PR:

- [ ] Chat produces correct responses end-to-end
- [ ] Stop preserves partial text when available (AbortHandler / INV-C3)
- [ ] Regen while generating calls `abortGeneration()` first
- [ ] Character switch does not abort other characters' generations
- [ ] Prompt block order matches preset definition
- [ ] Vector scan before keyword; merge deduplicates correctly
- [x] Memory injection respects token budget (INV-PS4)
- [ ] History cutoff trims oldest first
- [ ] Summary does not touch `ChatState.isGenerating` or messages
- [x] Memory draft mutex enforced (INV-M3, INV-M4)
- [ ] Image tags run after text on send/regen (not on continue unless changed)
  - [ ] Extensions post-gen on send/regen only (INV-EG1)
  - [ ] Block chain does not start on aborted or errored generation (INV-EG4)
  - [ ] Extension cancel token independent of chat cancel token (INV-EG5)
  - [ ] `dependsOnPrevious` blocks await preceding block; output chained (INV-EG6)
  - [ ] JS Runner / interactive panel code runs in null-origin iframe (INV-EG8)
  - [ ] Bridge `glaze.*` calls gated by preset capabilities (INV-JS1)
  - [ ] `glaze.triggerGeneration` respects generation mutexes (INV-JS3)
  - [ ] `glaze.playAudio` does not leak the audio session (INV-JS4)
  - [ ] `executeCommand` wired registry routes to the same services (INV-JS5)
  - [ ] Periodic scheduler pauses on app background; no catch-up tick (INV-JS6)
- [ ] Context limit / API-not-configured errors shown to user
- [ ] Abort closes TCP (CancelToken reaches Dio)
- [x] Session vars not leaked on abort/error (INV-C5)
