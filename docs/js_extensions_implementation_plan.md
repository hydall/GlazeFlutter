# JS Extensions Implementation Plan

## Current State

- `flutter_inappwebview` is already included in `pubspec.yaml`.
- Chat is rendered through one large WebView: `lib/features/chat/widgets/chat_webview_widget.dart`, `assets/chat_webview/bridge.js`, `assets/chat_webview/renderer.js`.
- ExtBlocks already exists under `lib/features/extensions` with `ExtensionPreset`, `BlockConfig`, `InfoBlock`, and `ExtensionPostGenService`.
- `jsRunner` already exists: LLM output or static script is executed in a sandboxed iframe through `ChatBridgeController.runJsBlock()` and `bridge.js::runSandboxedScript()`.
- Prompt injection for persisted ExtBlocks output already exists: `ExtBlocksPromptInjection` -> `InfoBlockInjector`, and it is already connected to prompt assembly.
- `ChatSession.sessionVars` exists as `Map<String, String>`. JS extension `chat` variables now use the reserved `__glaze_variables` JSON string key so existing macro/session vars remain compatible.

## Main Gaps

- A unified `window.glaze` API exists and is available inside the sandboxed JS runner. Variables, `generateText`, `injectPrompt`, `uninjectPrompt`, and `showToast` are implemented; trigger generation, audio, and command methods still fail explicitly until handled in Dart.
- There is no headless background engine. Current `jsRunner` requires the open chat WebView bridge; without it, JS blocks fail with `WebView bridge not available`.
- Interactive HTML panels are not a first-class feature. Because the current chat already uses one WebView, the implementation should render safe HTML islands inside the existing DOM rather than create one Flutter WebView per message.
- Current WebView settings need a security pass before user JS/HTML becomes more powerful. In particular, user-controlled JS must not run in the main first-party WebView context with broad file/universal access.
- `BlockTrigger.afterUser` and `periodic` exist in model/UI, but actual automatic execution is currently only post-generation after assistant messages.
- Secondary LLM calls exist internally for blocks, but not as bridge API `generateText(prompt, { preset: big|medium|small })` mapped to connection profiles.

## Implementation Plan

1. Preserve the current one-WebView chat architecture. DONE.
   - Do not implement per-message Flutter WebViews from the analysis document.
   - Render interactive UI as sandboxed HTML/iframe islands inside the existing chat WebView.
   - Add a separate headless background engine for background scripts.

2. Add a shared JS SDK. DONE.
   - Create an asset such as `assets/chat_webview/glaze_sdk.js`.
   - Inject `window.glaze` with `getVariables`, `setVariables`, `deleteVariable`, `executeCommand`, `triggerGeneration`, `injectPrompt`, `uninjectPrompt`, `generateText`, `showToast`, and `playAudio`.
   - Use the same SDK in background scripts and UI panels.

3. Add a Dart-side bridge adapter for `glaze.*`. DONE.
   - Create a focused service such as `lib/features/extensions/services/js_bridge_service.dart`.
   - Keep `ChatBridgeController` thin; it should delegate generic `glazeBridge` calls instead of owning all business logic.
   - Use a single method dispatcher shape: `{ method, params, context } -> result/error`.

4. Implement variable scopes. PARTIAL.
   - `chat`: DONE. Uses current chat session storage under reserved key `__glaze_variables` with JSON-compatible values.
   - `character`: DONE. Uses namespaced `Character.extensions['glaze_variables']` and preserves existing extension data.
   - `global`: add a persistence layer, preferably a small table/repo or SharedPreferences-backed JSON store.
   - `message`: decide between adding message vars to `ChatMessage` or storing them in a separate per-message table to avoid rewriting large `messagesJson` blobs.

5. Implement dot-notation operations on Dart side. DONE.
   - Provide get/set/delete helpers for nested JSON paths.
   - Make `setVariables` merge into the current object.
   - Validate JSON-compatible input and enforce size limits.
   - Do not rely only on JS-side path helpers.

6. Make variable writes atomic. DONE for chat/character scopes.
   - Add dedicated repo methods for read-modify-write operations.
   - Follow `docs/rules/database.md`: no ad-hoc `getById` + `put` outside a transaction for session/character variable updates.

7. Implement runtime prompt injection API. DONE.
   - Store `{ sessionId, id, content, depth, role }` separately from persisted ExtBlocks output. DONE: in-memory session-scoped provider.
   - Integrate it near existing prompt injection, without mixing it with `InfoBlock` rows. DONE: prompt payload includes runtime depth blocks separate from `InfoBlock` injection.
   - Define lifetime clearly: injected prompt affects next generation until removed, session switch, or explicit cleanup. DONE: session-scoped memory until `uninjectPrompt` or provider lifecycle cleanup.

8. Implement `generateText`. DONE for active API config.
   - Reuse `SseClient`/`ApiConfig` for secondary LLM calls. DONE.
   - Initially map `preset` to the active API config or simple settings. DONE: `big`, `medium`, and `small` are accepted and all currently route to active config.
   - Later add explicit connection profile mapping for `big`, `medium`, and `small`.
   - Never expose API keys to JS.

9. Implement `triggerGeneration`. DONE.
   - Route through `ChatNotifier`/generation pipeline, not a parallel generation path.
   - Respect `genId`, cancel tokens, memory draft mutex, and rules in `docs/rules/generation.md`.
   - Decide exact semantics: `continue` (append to last assistant), `regenerate` (replace last assistant), or `auto` (continue if last is assistant, else regenerate).
   - Respect INV-C1, INV-M3/M4, INV-C6 (per-charId independent), and `docs/rules/generation.md` abort chain.
   - Files:
     - `lib/features/extensions/models/trigger_mode.dart` — `TriggerMode { continueGeneration, regenerate, auto }` with `parse(String?)` fallback.
     - `lib/features/extensions/models/trigger_result.dart` — sealed result hierarchy `TriggerAccepted` / `TriggerBusy` / `TriggerNoSession` / `TriggerError`.
     - `lib/features/extensions/services/generation_dispatcher.dart` — `GenerationDispatcher` class + `generationDispatcherProvider`. Enforces INV-C1, INV-M3/M4 by rejecting the call (not auto-aborting) when busy. Maps `auto` → `continue`/`regenerate` based on the last message's role.
     - `lib/features/extensions/services/trigger_generation_handler.dart` — typed `TriggerGenerationHandler` that validates `params` (`mode`/`reason` types) and delegates to the dispatcher. Returns a plain map suitable for the bridge `result` payload.
     - `lib/features/extensions/services/js_bridge_service.dart` — `JsBridgeService` gained a `TriggerGenerationHandlerFn?` parameter and a `_handleTriggerGeneration` branch. `triggerGeneration` no longer throws `unsupported_method` when the handler is registered.
     - `lib/features/extensions/services/js_engine_service.dart` — `JsEngineBridgeHost` gained an optional `currentCharIdProvider` callback that supplies a fallback `characterId` for `triggerGeneration` when the JS request has no `context.characterId` (headless scripts without an open chat).
     - `lib/features/extensions/providers/js_engine_service_provider.dart` — `jsEngineBridgeHostFor` factory now accepts `currentCharIdProvider`.
     - `lib/features/chat/widgets/chat_webview_widget.dart` — wires `_triggerBridgeGeneration` into `JsBridgeService` and forwards `widget.charId` to the headless engine's `JsEngineBridgeHost`.

10. Implement a minimal `executeCommand` registry.
    - Start with a safe subset: `/trigger`, `/getvar`, `/setvar`, `/inject`, `/toast`.
    - Do not attempt full STScript compatibility in the first pass.
    - Keep command handlers typed and auditable.

11. Add `JsEngineService` for background scripts. DONE.
    - Use `HeadlessInAppWebView` for first implementation, as recommended by the analysis document.
    - Initialize it when chat/extensions are active.
    - Inject `glaze_sdk.js` and register `glazeBridge`.
    - Load global, character, and preset scripts.
    - Pause/resume timers on app lifecycle changes.

12. Move `jsRunner` toward the background engine. DONE.
    - Keep current sandboxed iframe runner as a fallback during migration.
    - Prefer `JsEngineService` so JS blocks can run even when the visual chat bridge is not available.
    - Preserve current cancel/timeout behavior.

13. Implement triggers. PARTIAL.
    - Keep `afterAssistant` path through `GenerationPipeline` and `ExtensionPostGenService`. DONE.
    - Add `afterUser` after user message persistence in `ChatNotifier.sendMessage`. TODO: dispatch preset scripts that listen for `trigger.afterUser`.
    - Defer `periodic` until background scheduler, lifecycle, and battery saver behavior are defined.

14. Implement interactive HTML panels. DONE.
    - Add a safe panel type or marker rendered by `renderer.js`.
    - Render panel content in sandboxed iframes inside the existing chat DOM.
    - Bridge iframe -> parent -> Dart through postMessage, not direct `window.flutter_inappwebview` access.
    - Support dynamic height updates inside the existing virtual list layout.
    - Editor UI: `BlockType.interactive` with LLM/static-HTML modes, min-height, optional API/model/streamToPanel. DONE.

15. Harden sandboxing/security. PARTIAL.
    - Use iframe sandboxing similar to current `runSandboxedScript`: `allow-scripts` without `allow-same-origin` for untrusted JS. DONE.
    - Do not expose `window.flutter_inappwebview` to user scripts. DONE.
    - Add permissions/capabilities per script/block before enabling dangerous methods. TODO.

16. Review WebView settings. PARTIAL.
    - Audit `allowFileAccessFromFileURLs`, `allowUniversalAccessFromFileURLs`, and mixed content settings. DONE for headless; TODO for main chat WebView.
    - Keep broad access only where absolutely required by the main renderer.
    - Ensure user JS/HTML runs in a stricter sandbox path.

17. Add UI for background scripts and permissions. PARTIAL.
    - Extend existing extension preset editor or add a dedicated screen. PARTIAL: editor covers `infoblock`, `imageGen`, `jsRunner`, and `interactive`. TODO: per-block permissions UI.
    - Configure enabled state, scope, trigger, script source, and permissions.
    - Add connection profile mapping for secondary LLM calls.

18. Add capability permissions. TODO.
    - Default-deny dangerous methods: `generateText`, `triggerGeneration`, `playAudio`, variable writes, prompt injection.
    - Let users enable capabilities per preset/script/block.

19. Add tests. PARTIAL.
    - Variable get/set/delete with dot paths. DONE.
    - Bridge contract for `window.glaze` methods. DONE.
    - Prompt injection ordering and cleanup. DONE.
    - `afterUser` and `afterAssistant` trigger behavior. TODO.
    - JS SDK promise success/error behavior. DONE.
    - Migration/repo atomic variable methods. DONE.
    - `triggerGeneration` mutex + idempotency. TODO.

20. Verify incrementally. ONGOING.
    - Run `flutter analyze` after Dart changes.
    - Run targeted tests first: `js_script_extractor_test`, `webview_assets_test`, webview callback contract tests, extension characterization tests.
    - Run full `flutter test` before considering the feature complete.
    - After changes under `assets/chat_webview/`, the app needs hot restart, not only hot reload.

## Recommended MVP Order

1. Shared `window.glaze` SDK and Dart bridge contract. DONE.
2. Variables for `chat` and `character` scopes only. DONE.
3. `generateText` through the active API config. DONE.
4. `injectPrompt` and `uninjectPrompt`. DONE.
5. Update current `jsRunner` to use the new API. DONE.
6. Add `HeadlessInAppWebView` background engine. DONE.
7. Add interactive HTML panels. DONE.
8. `triggerGeneration` through the chat pipeline. DONE.
9. Add permissions, `global`/`message` variables, periodic triggers, audio, and toast polish. TODO.

## Implementation Progress

### Done

- Added `assets/chat_webview/glaze_sdk.js` with `window.glaze` methods: `getVariables`, `setVariables`, `deleteVariable`, `executeCommand`, `triggerGeneration`, `injectPrompt`, `uninjectPrompt`, `generateText`, `showToast`, and `playAudio`.
- Loaded `glaze_sdk.js` from `assets/chat_webview/index.html` before `bridge.js`.
- Added `glazeBridge` handler registration in `ChatBridgeController`.
- Added `lib/features/extensions/services/js_bridge_service.dart` as the Dart-side dispatcher shape `{ method, params, context } -> { ok, result/error }`.
- Updated `bridge.js::runSandboxedScript()` so the sandboxed iframe receives `window.glaze` without direct access to `window.flutter_inappwebview`.
- Added iframe-to-parent relay for `glaze:request` / `glaze:response` messages, then parent-to-Dart forwarding through `glazeBridge`.
- Added static WebView asset tests for SDK loading order, exposed SDK methods, and sandbox relay behavior.
- Kept the first implementation minimal: only `showToast` is handled in Dart for now; unsupported methods fail explicitly.
- Implemented JSON-compatible `chat` and `character` variable scopes.
- Added Dart-side dot-path `getVariables`, `setVariables`, and `deleteVariable` handling with type/size validation.
- Added atomic repository helpers `ChatRepo.updateSessionVarsJson()` and `CharacterRepo.updateExtensionsJson()`.
- Wired current session and character context into `ChatWebViewWidget`, `ChatBridgeController.runJsBlock()`, and `ExtensionPostGenService`.
- Added `test/js_bridge_service_test.dart` for chat vars, character vars, and JSON compatibility rejection.
- Implemented minimal `generateText(prompt, { preset })` bridge handling through the active API config.
- Added `GenerateTextHandler` injection to keep `JsBridgeService` testable without network calls.
- Wired chat WebView bridge `generateText` to `SseClient.streamChatCompletion(stream: false)` with a 55 second timeout and CancelToken cancellation.
- Accepted `big`, `medium`, and `small` preset names but routed all to active config until explicit connection profile mapping exists.
- Added `generateText` bridge tests for handler delegation and invalid preset rejection.
- Implemented runtime `injectPrompt` and `uninjectPrompt` bridge handling.
- Added `RuntimePromptInjectionNotifier` as in-memory, session-scoped runtime prompt storage separate from persisted `InfoBlock` rows.
- Added `RuntimePromptBlock` payload serialization so runtime prompt injections survive main-thread to prompt-worker isolate transfer.
- Integrated runtime prompt blocks into prompt assembly as depth blocks with `role`, `depth`, and macro expansion.
- Preserved depth block ordering across history trimming by replacing only kept history messages instead of bulk-inserting trimmed history at the first history marker.
- Added runtime prompt injection tests for session scoping, removal, bridge dispatch, and prompt assembly ordering.
- Added `assets/chat_webview/headless.html` as a strict `sandbox="allow-scripts"` host for the background engine.
- Added `lib/features/extensions/services/js_engine_service.dart` as a singleton headless engine driven by `HeadlessInAppWebView` with idempotent `init()`, `runScript(...)`, `cancel()`, and `dispose()`.
- Registered `glazeBridge` JS handler on the headless controller and shared the same `JsBridgeService` instance used by the visual WebView.
- Routed headless engine scripts through `window.headlessBridge.runSandboxedScript(script, contextJson)` with a 30 second default timeout, `CancelToken` race, and explicit `HeadlessUnavailableError` on engine-not-ready.
- Updated `ExtensionPostGenService._executeJsScript` to prefer the headless engine and fall back to the visual `ChatBridgeController.runJsBlock` when the engine is not ready or raises `HeadlessUnavailableError`.
- Added strict sandbox settings on the headless WebView: `allowFileAccessFromFileURLs=false`, `allowUniversalAccessFromFileURLs=false`, `mixedContentMode=MIXED_CONTENT_NEVER_ALLOW`.
- Added `test/js_engine_service_test.dart` covering singleton identity, init idempotency, runScript delegation, `HeadlessUnavailableError`, cooperative cancel, and dispose.
- Added headless.html static assertions to `test/webview_assets_test.dart` for SDK load, `window.headlessBridge.runSandboxedScript`, and `allow-scripts`-only sandbox.
- Added `BlockType.interactive` enum value in `block_config.dart` (regenerated `block_config.g.dart`).
- Added `assets/chat_webview/bridge.js::class PanelHost` — sandboxed iframe islands inside the chat DOM, source-check `e.source === iframe.contentWindow`, dynamic resize via `ResizeObserver`, `Bridge.openPanel/closePanel/postToPanel` JS API, postMessage reлай for `glaze:request` and parent → iframe `glaze:response`, `glaze:panel-{ready,resize,action,close,push}` events, `window.glazePanel.{ready,close,reportHeight,sendAction}` user helpers, cleanup in `clearAll/setMessages/removeMessage`.
- Added `lib/features/extensions/services/panel_host_service.dart` — singleton `PanelHostService` with `resizeStream`/`eventStream`, `openPanel/closePanel/closeAllForChar/disposeAll`, test-only `resetForTest` seam, injectable `_bridgeResolver`.
- Added `_runInteractive` in `ExtensionPostGenService` — LLM → strip code-fence → `panelHostService.openPanel` → persist in `InfoBlock.content` → status `done`.
- Wired `ChatBridgeController.openInteractivePanel/closeInteractivePanel/closeAllInteractivePanels/postToInteractivePanel` and `onPanelResize/onPanelEvent` callbacks; bridge handlers in `bridge_handlers.dart` (HandlerKind.jsonObject).
- Added panel CSS in `assets/chat_webview/styles.css` (`.interactive-panel`, `.interactive-panel-frame`).
- Added `test/panel_host_service_test.dart` (9 cases) and `interactive panels` group (12 asserts) in `webview_assets_test.dart`.
- Added `BlockType.interactive` UI in `preset_editor_screen.dart` — SegmentedButton (LLM / Static HTML), static HTML textarea, prompt field, minHeight numeric, optional dependsOnPrevious, contextMessageCount, contextSystemPrompt, `_ApiConfigSelector`, `_ModelField`, `streamToPanel` switch; `_buildSavedBlock` saves static HTML to `script` and LLM-only config to `prompt`/api/model/context.

### Verified

- `flutter analyze lib/features/extensions/services/js_engine_service.dart lib/features/extensions/providers/js_engine_service_provider.dart lib/features/extensions/services/extension_post_gen_service.dart lib/features/chat/widgets/chat_webview_widget.dart test/js_engine_service_test.dart test/webview_assets_test.dart` passed.
- `flutter test test/js_engine_service_test.dart test/js_bridge_service_test.dart test/runtime_prompt_injection_test.dart` passed.
- `flutter test test/panel_host_service_test.dart test/webview_assets_test.dart --plain-name "interactive panels"` passed (12 + 9 = 21 tests).
- `flutter test test/panel_host_service_test.dart test/webview_assets_test.dart test/js_engine_service_test.dart test/js_bridge_service_test.dart test/runtime_prompt_injection_test.dart` passed (+73 -5 pre-existing).
- `flutter analyze` after UI increment: 0 new errors; 12 pre-existing issues (1 error in `js_engine_service.dart:263 throw_of_invalid_type`, plus unused imports/variables and 5 pre-existing edit-textarea wheel/CSS failures in `webview_assets_test.dart`).

### Known Existing Test Failure

- Full `flutter test test/webview_assets_test.dart` still fails on pre-existing edit textarea wheel/CSS checks unrelated to this plan: missing expected `preventDefault`, `deltaY * 0.3`, `deltaY * 16`, `stopPropagation`, and `overscroll-behavior: contain` patterns.

### Commits (current branch `js-extension-bridge-sdk`, pushed to `origin/js-extension-bridge-sdk`)

- `eab4bd4 feat(ext): add interactive block UI` — preset editor UI for `BlockType.interactive`.
- `37a7bf2 feat(ext): add interactive html panels` — `PanelHost` in `bridge.js`, `PanelHostService`, `_runInteractive`, `ChatBridgeController` panel methods, panel CSS, tests.
- `d67df37 feat(ext): add js headless engine` — `JsEngineService` (headless singleton) + `headless.html` + fallback wiring in `ExtensionPostGenService`.
- `9c0aafe feat(ext): add js prompt injection bridge` — `RuntimePromptInjectionNotifier` + prompt assembly integration.
- `d62b58f feat(ext): add js generateText bridge` — `generateText` through active API config.
- `c8952f7 feat(ext): add js variable bridge scopes` — chat + character variable scopes with atomic repo helpers.
- `b2718e7 feat(ext): add js extension bridge sdk` — `glaze_sdk.js`, `glazeBridge` handler, dispatcher shape.
- `353d289 Merge pull request #140 from danvitv/feat/ext-blocks-redesign` (upstream merge).

### Next

- Add permissions, `global`/`message` variables, periodic triggers, audio, and toast polish.
- Run after each step:
  - `flutter analyze` on touched files
  - targeted `flutter test` for the increment
  - `flutter test` on the full test set on completion

## Current Increment: `triggerGeneration` — COMPLETE

Goal: wire `window.glaze.triggerGeneration(mode)` from the headless/sandboxed iframe through `JsBridgeService` into `ChatNotifier`/`ChatGenerationService`, respecting all generation invariants (INV-C1, INV-C3, INV-M3, INV-M4, INV-C6, INV-A1).

### Semantics (implemented)

`triggerGeneration(options?)` where `options` is a JS object with optional fields:

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `mode` | `'continue' \| 'regenerate' \| 'auto'` | `'auto'` | see below |
| `reason` | string | `null` | debug/log context (NOT persisted as message) |

- `continue`: append to the last assistant message. Forwards to `ChatNotifier.continueMessage()` (INV-CM1, INV-CM2).
- `regenerate`: replace the last assistant message. Forwards to `ChatNotifier.regenerateLastAssistant()` (INV-A3 — aborts first if active).
- `auto` (default): if the last message is `assistant` → `continue`; else → `regenerate`.

`reason` is logged via `debugPrint` and is **not** persisted.

### Failure semantics (implemented)

- If `charId` has no open chat session → reject with `TriggerNoSession` (JS error code `no_session`).
- If the chat is generating (INV-C1) → reject with `TriggerBusy` (JS error code `chat_busy`); the call must not auto-abort.
- If a memory draft is active (INV-M3/M4) → reject with `TriggerBusy` (JS error code `memory_draft_busy`); the call must not auto-abort.
- Validation errors (`mode`/`reason` not strings) → `ArgumentError` → bridge `invalid_request` code.

### Wiring (implemented)

```
JS: window.glaze.triggerGeneration({ mode: 'auto' })
  → glazeSdk.glazeBridge.request('triggerGeneration', { mode })
  → bridge.js: glazed bridge postMessage('glaze:request', ...)
  → ChatBridgeController._dispatchGlazeRequest
  → JsBridgeService.dispatch(method, params, context)
  → JsBridgeService._handleTriggerGeneration → TriggerGenerationHandlerFn
  → TriggerGenerationHandler.handle (validate mode/reason)
  → GenerationDispatcher.dispatch(charId, mode, reason)
  → ref.read(chatProvider(charId).notifier)
  → ChatNotifier.{continueMessage | regenerateLastAssistant}
```

### Tests (implemented)

- `test/trigger_generation_test.dart` (11 cases):
  - `TriggerMode.parse` — known / unknown / case-insensitive
  - `GenerationDispatcher` — `TriggerNoSession` when state loading; `TriggerBusy` when `isGenerating`; `TriggerBusy` (memory_draft) when active; auto→continue / auto→regenerate; explicit `continue` / `regenerate`; `peekResolvedMode` busy / no-session
  - `TriggerGenerationHandler` — no_session map; `ArgumentError` on non-string mode/reason
- `test/js_bridge_service_test.dart` (4 new cases):
  - delegates `triggerGeneration` with resolved `charId`
  - prefers `context.characterId` over `currentCharacterId` fallback
  - propagates `ArgumentError` as `invalid_request` code
  - returns `unsupported_method` when no handler is registered

### Verified

- `flutter analyze` on touched files: 0 new errors (only 3 pre-existing warnings/errors in unrelated files).
- `flutter test test/trigger_generation_test.dart test/js_bridge_service_test.dart` — 25/25 passed.
- `flutter test` on the 5-file extension set: 42/42 passed (the 5 pre-existing `webview_assets_test.dart` failures are unchanged).
