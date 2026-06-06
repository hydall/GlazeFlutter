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
4. Memory injection (token budget — INV-PS4)
5. Context cutoff — oldest messages trimmed first

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
active preset id (INV-EG3). The block chain does not start on aborted generation (INV-EG4).

### Block execution model

```
blocks = preset.blocks.where(enabled).sortBy(order)
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

### Cancel

`ExtensionPostGenService.cancelBlocks()` cancels `_extensionBlocksCancelToken`.
Each `_runSingleBlock` checks the token before and after every `await`; cancelled
blocks are marked `BlockRunStatus.stopped`. Does **not** affect the chat text cancel
token or in-progress image generation.

### Bridge feedback

On status change, call `ChatBridgeController.updateBlockStatus(messageId, aggregatedStatus)`.
On panel open/update, call `ChatBridgeController.showExtBlocksPanel(messageId, blocks)`.

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
  - [ ] Block chain does not start on aborted generation (INV-EG4)
  - [ ] Extension cancel token independent of chat cancel token (INV-EG5)
  - [ ] `dependsOnPrevious` blocks await preceding block; output chained (INV-EG6)
- [ ] Context limit / API-not-configured errors shown to user
- [ ] Abort closes TCP (CancelToken reaches Dio)
- [x] Session vars not leaked on abort/error (INV-C5)
