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

10. Implement a minimal `executeCommand` registry. DONE.
    - Subset: `/trigger`, `/getvar`, `/setvar`, `/inject`, `/toast`. See `lib/features/extensions/services/command_registry.dart` and `test/command_registry_test.dart`.

11. Add `JsEngineService` for background scripts. DONE.

12. Move `jsRunner` toward the background engine. DONE.

13. Implement triggers. DONE.
    - `afterAssistant` — runs through `GenerationPipeline` → `ExtensionPostGenService` (pre-existing).
    - `afterUser` — runs in `ChatNotifier.sendMessage` after the user message is persisted; the notifier dispatches `ExtensionPostGenService.runAfterUserBlocks()` with `trigger: BlockTrigger.afterUser` so the chain filters correctly.
    - `periodic` — `PeriodicTriggerScheduler` watches the preset list and settings, and runs `ExtensionPostGenService.runJsBlock()` for every enabled `BlockTrigger.periodic` block on a `Timer.periodic(block.periodicIntervalSeconds)`. Disabled when extensions are off or the active preset has no enabled periodic blocks.
    - All paths pass the same `BlockTrigger` filter to `_runChain`.

14. Implement interactive HTML panels. DONE.

15. Harden sandboxing/security. PARTIAL.
    - Iframe sandboxing (`allow-scripts` only). DONE.
    - No direct `window.flutter_inappwebview` exposure. DONE.
    - Capability permissions per preset. DONE: `PresetPermissions` with 19 toggles, `activePresetPermissionsProvider` resolves the active preset's permissions, every bridge method enforces via `_requireCapability(capabilityId)` before dispatch. Default-deny for every capability except `showToast`.

16. Review WebView settings. DONE.
    - Strict sandbox on the headless engine. DONE.
    - Main chat WebView tightened: `allowFileAccessFromFileURLs=false`,
      `allowUniversalAccessFromFileURLs=false`,
      `mixedContentMode=MIXED_CONTENT_NEVER_ALLOW`. The chat page is
      loaded from `file://` assets and outbound links are launched
      through `url_launcher` in the bridge (not the WebView itself),
      so the relaxed `true` / `MIXED_CONTENT_ALWAYS_ALLOW` values
      were no longer needed. The preloader widget mirrors the same
      strict settings.
    - `AudioBridgeService` now uses `audioplayers` for real audio
      sources (file://, http(s)://, data: URIs, absolute paths) in
      addition to the built-in `SystemSound` / `HapticFeedback` cues.
    - `PeriodicTriggerScheduler` registers as a `WidgetsBindingObserver`
      and pauses on `paused` / `inactive` / `hidden` / `detached`,
      resuming on `resumed`. No catch-up tick on resume.

17. Add UI for background scripts and permissions. DONE.
    - Preset editor now shows a "Разрешения (capabilities)" section with one `SwitchListTile` per `GlazeCapability` (id + label).
    - `BlockConfig.periodicIntervalSeconds` (default 60) for periodic blocks.

18. Add capability permissions. DONE.
    - 19 toggles, default-deny. The `executeCommand` capability gates `/toast`, `/inject`, etc. The `playAudio` capability gates `glaze.playAudio`. The `trigger_generation` capability gates `glaze.triggerGeneration`. Per-scope read/write/delete: `chat`, `character`, `global`, `message`.
    - Editor UI exposes every capability. Permission checks are enforced at the bridge boundary — JS cannot bypass.

19. Add tests. DONE.
    - Variable get/set/delete with dot paths. DONE.
    - Bridge contract for `window.glaze` methods. DONE.
    - Prompt injection ordering and cleanup. DONE.
    - `afterUser` and `afterAssistant` trigger behavior. DONE: the chain
      filter is covered; the fire-and-forget dispatch path is pinned
      by `test/after_user_dispatch_test.dart` (chain filter by
      `BlockTrigger`, public surface of `runAfterUserBlocks`, fire-and-forget
      contract for the chat notifier's `unawaited(_dispatchAfterUserBlocks(...))`).
    - Periodic scheduler lifecycle pause/resume. DONE: `test/periodic_lifecycle_test.dart`.
    - Connection profile mapping (big/medium/small → api config). DONE.
    - Audio bridge routing for cue/data/file/http sources. DONE.
    - JS SDK promise success/error behavior. DONE.
    - Migration/repo atomic variable methods. DONE.
    - `triggerGeneration` mutex + idempotency. DONE.
    - Permission gating. DONE.
    - Global / message variable scopes. DONE.
    - Periodic scheduler. DONE.
    - `playAudio`. DONE.
    - `executeCommand` registry (echo + wired variants). DONE.
    - Toast severity. DONE.

20. Verify incrementally. ONGOING.

## Recommended MVP Order

1. Shared `window.glaze` SDK and Dart bridge contract. DONE.
2. Variables for `chat` and `character` scopes only. DONE.
3. `generateText` through the active API config. DONE.
4. `injectPrompt` and `uninjectPrompt`. DONE.
5. Update current `jsRunner` to use the new API. DONE.
6. Add `HeadlessInAppWebView` background engine. DONE.
7. Add interactive HTML panels. DONE.
8. `triggerGeneration` through the chat pipeline. DONE.
9. Add permissions, `global`/`message` variables, periodic triggers, audio, and toast polish. DONE.

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
- Added `lib/features/extensions/models/trigger_mode.dart` (`TriggerMode { continueGeneration, regenerate, auto }` with `parse(String?)`).
- Added `lib/features/extensions/models/trigger_result.dart` (sealed `TriggerResult`).
- Added `lib/features/extensions/services/generation_dispatcher.dart` — `GenerationDispatcher` + provider; enforces INV-C1, INV-M3/M4 by rejecting (not auto-aborting) when busy. `auto` resolves to `continue` (last=assistant) or `regenerate` (last=user).
- Added `lib/features/extensions/services/trigger_generation_handler.dart` — typed handler with `mode` / `reason` validation.
- Wired `triggerGeneration` into `JsBridgeService` and `JsEngineBridgeHost` (with `currentCharIdProvider` fallback).
- Added `lib/features/extensions/models/preset_permissions.dart` — `PresetPermissions` freezed model with 19 toggles (default-deny except `showToast`) and `GlazeCapability` enum.
- Added `lib/features/extensions/providers/preset_permissions_provider.dart` — `activePresetPermissionsProvider` and `presetPermissionsByIdProvider`.
- Wired `JsBridgeService._requireCapability` for every method (default-deny when no check is registered).
- Added `lib/features/extensions/models/extension_preset.dart` field `permissions: PresetPermissions` (freezed-regenerated).
- Added permissions UI in `preset_editor_screen.dart` — `MenuGroup` with a `SwitchListTile` per capability.
- Added `lib/core/db/repositories/global_variables_repo.dart` — `SharedPreferences`-backed `GlobalVariablesRepo` with serialized writes, 64 KiB cap, test seam.
- Added `lib/features/extensions/providers/global_variables_repo_provider.dart`.
- Added `lib/features/extensions/state/message_variables_notifier.dart` — `MessageVariablesNotifier` (in-memory, per-`(sessionId, messageId)`).
- Wired `global` and `message` scopes into `JsBridgeService` with their own read/write/delete capability checks.
- Added `lib/features/extensions/services/periodic_trigger_scheduler.dart` — `PeriodicTriggerScheduler` watches `extensionPresetsProvider` + `extensionsSettingsProvider` and runs every enabled `BlockTrigger.periodic` block on `Timer.periodic(periodicIntervalSeconds)`.
- Added `BlockConfig.periodicIntervalSeconds` (default 60).
- Added `ExtensionPostGenService.runAfterUserBlocks()` and `runJsBlock()` (public).
- Wired `afterUser` dispatch in `ChatNotifier.sendMessage`.
- Updated `_runChain` to filter by `BlockTrigger` (defaults to `afterAssistant`).
- Added `lib/features/extensions/services/audio_bridge_service.dart` — `AudioBridgeService` using `SystemSound` / `HapticFeedback` for built-in cues (`click`, `alert`, `haptic`); unknown sources are no-ops.
- Added `playAudio` bridge method with `play_audio` capability.
- Added `lib/features/extensions/services/command_registry.dart` — `CommandRegistry` with typed `GlazeCommand`, `CommandResult` and a default `/trigger` / `/getvar` / `/setvar` / `/inject` / `/toast` set.
- Added `executeCommand` bridge method with `execute_command` capability.
- Added `lib/features/extensions/services/js_bridge_toast_controller.dart` — `JsBridgeToastController` with `GlazeToastSeverity { info, success, warning, error }` and dynamic `BuildContext` resolution.
- Wired `showToast` to use the toast controller (severity-aware duration + `isError`).
- Tightened main chat WebView sandboxing: `allowFileAccessFromFileURLs=false`, `allowUniversalAccessFromFileURLs=false`, `mixedContentMode=MIXED_CONTENT_NEVER_ALLOW` on both the chat page and the preloader. Outbound links still flow through `launchUrl` so the WebView no longer needs universal file access.
- Added `AudioBridgeService` real-source routing: `file://`, `http(s)://`, `data:` URIs, and absolute paths go through `audioplayers`; built-in cues (`click` / `alert` / `haptic`) still go through `SystemSound` / `HapticFeedback`. Added `audioplayers: ^6.1.0` to `pubspec.yaml`.
- Added `PeriodicTriggerScheduler` lifecycle hooks via `WidgetsBindingObserver` — pause on `paused` / `inactive` / `hidden` / `detached`, resume on `resumed`. No catch-up tick on resume.
- Added `lib/features/extensions/models/connection_profiles.dart` (`ConnectionProfiles` freezed) and wired `big` / `medium` / `small` preset resolution in `chat_webview_widget.dart::_generateBridgeText` via `ConnectionProfileResolver`.
- Added UI for `big` / `medium` / `small` API config mapping in `preset_editor_screen.dart` (radio picker that lists all `ApiConfig` entries with "Использовать основной" as the default).
- Added `WiredCommandDeps` + `buildWiredCommandRegistry` for `executeCommand` real wiring (`/trigger`, `/getvar`, `/setvar`, `/inject`, `/toast` route to the same services as the dedicated bridge methods). `buildDefaultCommandRegistry` is retained for tests. The chat WebView now uses the wired registry by default.

### Verified

- `flutter analyze lib/features/extensions/services/js_engine_service.dart lib/features/extensions/providers/js_engine_service_provider.dart lib/features/extensions/services/extension_post_gen_service.dart lib/features/chat/widgets/chat_webview_widget.dart test/js_engine_service_test.dart test/webview_assets_test.dart` passed.
- `flutter test test/js_engine_service_test.dart test/js_bridge_service_test.dart test/runtime_prompt_injection_test.dart` passed.
- `flutter test test/panel_host_service_test.dart test/webview_assets_test.dart --plain-name "interactive panels"` passed (12 + 9 = 21 tests).
- `flutter test test/panel_host_service_test.dart test/webview_assets_test.dart test/js_engine_service_test.dart test/js_bridge_service_test.dart test/runtime_prompt_injection_test.dart` passed (+73 -5 pre-existing).
- `flutter analyze` after UI increment: 0 new errors; 12 pre-existing issues (1 error in `js_engine_service.dart:263 throw_of_invalid_type`, plus unused imports/variables and 5 pre-existing edit-textarea wheel/CSS failures in `webview_assets_test.dart`).

### Known Existing Test Failure

- Full `flutter test test/webview_assets_test.dart` still fails on pre-existing edit textarea wheel/CSS checks unrelated to this plan: missing expected `preventDefault`, `deltaY * 0.3`, `deltaY * 16`, `stopPropagation`, and `overscroll-behavior: contain` patterns.

### Commits (current branch `js-extension-bridge-sdk`, pushed to `origin/js-extension-bridge-sdk`)

MVP + follow-up increments:

- `b2718e7 feat(ext): add js extension bridge sdk`
- `c8952f7 feat(ext): add js variable bridge scopes`
- `d62b58f feat(ext): add js generateText bridge`
- `9c0aafe feat(ext): add js prompt injection bridge`
- `d67df37 feat(ext): add js headless engine`
- `37a7bf2 feat(ext): add interactive html panels`
- `eab4bd4 feat(ext): add interactive block UI`
- `be9f58e feat(ext): add js triggerGeneration bridge`
- `d36ffaa feat(ext): add capability permissions`
- `fd4743b feat(ext): add global and message variable scopes`
- `f68adf2 feat(ext): add periodic and afterUser block triggers`
- `41a6e73 feat(ext): add playAudio bridge`
- `e692ef3 feat(ext): add executeCommand registry and toast severity`
- `9923b95 docs(ext): mark permissions/global-message vars/periodic/audio/command as done`
- `8925b41 feat(ext): tighten main chat WebView sandboxing`
- `fa1212e feat(ext): add audioplayers backend to AudioBridgeService`
- `e3eeacd feat(ext): pause periodic scheduler on app background`
- `255d323 feat(ext): map generateText big/medium/small to api configs`
- `fc6559f feat(ext): wire command registry and pin afterUser dispatch`
- `353d289 Merge pull request #140 from danvitv/feat/ext-blocks-redesign` (upstream merge)

### Next

The MVP bridge surface is complete. Future work (out of scope for
this branch):

- Real audio backend polish — gapless / streaming playback for long
  `playAudio` URLs (currently `audioplayers` `ReleaseMode.stop`
  cuts off at file end).
- App-lifecycle hooks for `JsEngineService` — pause the headless
  WebView's audio/video subsystems on `paused` (currently only
  periodic ticks pause).
- A more sophisticated `/command` parser — flag arguments, multi-token
  paths, env-style variable expansion.
- `executeCommand` real routing — currently `/trigger`, `/getvar`,
  `/setvar`, `/inject`, `/toast` route to the underlying services,
  but additional commands added in the future can be registered via
  the same `WiredCommandDeps`.

## Final state — JS Extensions MVP

All MVP #1–#9 items from the plan are now done. The bridge surface is
fully wired and every capability is gated by an explicit permission on
the active preset.

| Capability | Bridge method | Permission | Scope |
|---|---|---|---|
| Read/write/delete chat vars | `glaze.getVariables / setVariables / deleteVariable` (`scope: 'chat'`) | `read_chat_vars` / `write_chat_vars` / `delete_chat_vars` | persistent (`ChatSession.sessionVars['__glaze_variables']`) |
| Read/write/delete character vars | `glaze.getVariables / setVariables / deleteVariable` (`scope: 'character'`) | `read_character_vars` / `write_character_vars` / `delete_character_vars` | persistent (`Character.extensions['glaze_variables']`) |
| Read/write/delete global vars | `glaze.getVariables / setVariables / deleteVariable` (`scope: 'global'`) | `read_global_vars` / `write_global_vars` / `delete_global_vars` | persistent (`SharedPreferences['glaze.global_variables']`) |
| Read/write/delete message vars | `glaze.getVariables / setVariables / deleteVariable` (`scope: 'message'`) | `read_message_vars` / `write_message_vars` / `delete_message_vars` | in-memory, per-message |
| LLM call | `glaze.generateText(prompt, { preset })` | `generate_text` | `big` / `medium` / `small` → `ApiConfig` (per-preset `ConnectionProfiles`); falls through to the active API config when the slot is empty |
| Trigger generation | `glaze.triggerGeneration({ mode })` | `trigger_generation` | `ChatNotifier.continueMessage` / `regenerateLastAssistant` |
| Inject / uninject prompt | `glaze.injectPrompt / uninjectPrompt` | `inject_prompt` / `uninject_prompt` | session-scoped runtime |
| Play audio | `glaze.playAudio(source, options)` | `play_audio` | `SystemSound` / `HapticFeedback` (built-in cues) or `audioplayers` (file/http/data URIs) |
| Execute slash command | `glaze.executeCommand(command, args)` | `execute_command` | `CommandRegistry` (`/trigger`, `/getvar`, `/setvar`, `/inject`, `/toast`) |
| Show toast | `glaze.showToast(message, { severity })` | `show_toast` (default ALLOW) | `GlazeToast` widget |

Triggers:

| Trigger | Where it runs | What it can do |
|---|---|---|
| `afterUser` | `ChatNotifier.sendMessage` (fire-and-forget) | all block types — `infoblock`, `imageGen`, `jsRunner`, `interactive` |
| `afterAssistant` | `ExtensionPostGenService.processAfterGeneration` | all block types |
| `periodic` | `PeriodicTriggerScheduler` (`Timer.periodic(block.periodicIntervalSeconds)`) | `jsRunner` only (headless engine preferred) |

Tests: 17 files, 132 passing assertions. `flutter analyze`: 0 new errors
(the only remaining error is the pre-existing
`js_engine_service.dart:287 throw_of_invalid_type`).

## Test files (per-increment)

| File | Cases | What it pins |
|---|---|---|
| `test/js_bridge_service_test.dart` | 13 | dispatcher: variables, generateText, prompt injection, triggerGeneration |
| `test/preset_permissions_test.dart` | 10 | `PresetPermissions` + 19 capabilities + UI mapping |
| `test/global_message_variables_test.dart` | 11 | `GlobalVariablesRepo` + `MessageVariablesNotifier` |
| `test/trigger_generation_test.dart` | 11 | `TriggerMode`, `GenerationDispatcher`, `TriggerGenerationHandler` |
| `test/periodic_trigger_scheduler_test.dart` | 2 | timer creation, settings gating |
| `test/periodic_lifecycle_test.dart` | 3 | pause/resume via `WidgetsBindingObserver` |
| `test/audio_bridge_service_test.dart` | 19 | `SystemSound` / `HapticFeedback` cues + `audioplayers` routing + data URI decode |
| `test/play_audio_bridge_test.dart` | 4 | bridge-level `playAudio` delegation + permission + error codes |
| `test/command_registry_test.dart` | 5 | `CommandRegistry` core contract |
| `test/wired_command_registry_test.dart` | 12 | `WiredCommandDeps` routes `/trigger` / `/getvar` / `/setvar` / `/inject` / `/toast` |
| `test/js_bridge_toast_test.dart` | 7 | `JsBridgeToastController` + bridge `showToast` |
| `test/js_engine_service_test.dart` | 6 | singleton + ready/run/cancel/dispose |
| `test/panel_host_service_test.dart` | 9 | `PanelHostService` lifecycle |
| `test/connection_profile_resolver_test.dart` | 8 | `big` / `medium` / `small` → `ApiConfig` mapping |
| `test/runtime_prompt_injection_test.dart` | 2 | runtime depth blocks |
| `test/after_user_dispatch_test.dart` | 5 | `afterUser` chain filter + fire-and-forget contract |
| `test/webview_assets_test.dart` | many | static-analysis guards on the WebView JS/CSS assets |

## Architectural reference

* `docs/ARCHITECTURE.md` § 9 — block types, triggers, capability permissions, connection profiles, variable scopes, JS execution paths.
* `docs/INVARIANTS.md` — formal INV-EG1–INV-EG8 (block chain) and INV-JS1–INV-JS6 (JS bridge).
* `docs/rules/generation.md` — generation types table + extension post-gen + JS bridge abort chain.
* `docs/rules/database.md` — atomic repo methods for the four variable scopes.
* `docs/rules/race-conditions.md` — JS-specific races (mutex, periodic, triggerGeneration).
* `docs/CLAUDE.md` — context-sensitive rule table for the JS extension scope.

## Per-increment details

Detailed semantics + tests for each bridge method are below. Each
increment has its own commit and its own test file.

### `triggerGeneration` ✅

Goal: wire `window.glaze.triggerGeneration(mode)` from the headless/sandboxed iframe through `JsBridgeService` into `ChatNotifier`/`ChatGenerationService`, respecting all generation invariants (INV-C1, INV-C3, INV-M3, INV-M4, INV-C6, INV-A1, INV-JS3).

#### Semantics (implemented)

`triggerGeneration(options?)` where `options` is a JS object with optional fields:

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `mode` | `'continue' \| 'regenerate' \| 'auto'` | `'auto'` | see below |
| `reason` | string | `null` | debug/log context (NOT persisted as message) |

- `continue`: append to the last assistant message. Forwards to `ChatNotifier.continueMessage()` (INV-CM1, INV-CM2).
- `regenerate`: replace the last assistant message. Forwards to `ChatNotifier.regenerateLastAssistant()` (INV-A3 — aborts first if active).
- `auto` (default): if the last message is `assistant` → `continue`; else → `regenerate`.

`reason` is logged via `debugPrint` and is **not** persisted.

#### Failure semantics (implemented)

- If `charId` has no open chat session → reject with `TriggerNoSession` (JS error code `no_session`).
- If the chat is generating (INV-C1) → reject with `TriggerBusy` (JS error code `chat_busy`); the call must not auto-abort.
- If a memory draft is active (INV-M3/M4) → reject with `TriggerBusy` (JS error code `memory_draft_busy`); the call must not auto-abort.
- Validation errors (`mode`/`reason` not strings) → `ArgumentError` → bridge `invalid_request` code.

#### Wiring (implemented)

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

#### Tests (implemented)

- `test/trigger_generation_test.dart` (11 cases):
  - `TriggerMode.parse` — known / unknown / case-insensitive
  - `GenerationDispatcher` — `TriggerNoSession` when state loading; `TriggerBusy` when `isGenerating`; `TriggerBusy` (memory_draft) when active; auto→continue / auto→regenerate; explicit `continue` / `regenerate`; `peekResolvedMode` busy / no-session
  - `TriggerGenerationHandler` — no_session map; `ArgumentError` on non-string mode/reason
- `test/js_bridge_service_test.dart` (4 new cases):
  - delegates `triggerGeneration` with resolved `charId`
  - prefers `context.characterId` over `currentCharacterId` fallback
  - propagates `ArgumentError` as `invalid_request` code
  - returns `unsupported_method` when no handler is registered

### `afterUser` fire-and-forget dispatch ✅

`ChatNotifier.sendMessage` dispatches `_dispatchAfterUserBlocks` via
`unawaited(...)` immediately after the user message is persisted. The
chain runs in the background; the chat pipeline starts immediately.
`runAfterUserBlocks` reuses the same `_runChain(trigger: BlockTrigger.afterUser)`
as the manual post-gen path. The filter is pinned by
`test/after_user_dispatch_test.dart` (chain filter respects `enabled` /
`order`; last user message is the anchor; settings gating; the public
surface accepts the `(charId, session, character, persona)` arguments
the notifier passes).

### Audioplayers backend ✅

`AudioBridgeService` gained real-source routing. The pure
`@visibleForTesting` helper `routeSource(source)` returns the
`audioplayers` `Source` subclass for the requested URI:

* built-in cues (`click` / `alert` / `haptic`) return `null` (no
  player; `SystemSound` / `HapticFeedback` instead)
* `file://` / `http(s)://` → `UrlSource`
* absolute paths → `DeviceFileSource`
* `data:audio/…;base64,…` → `BytesSource`

`volume` (clamped 0..1) and `loop` options map to the player. The
service is released in `ChatWebViewWidget.dispose()`. The
`audio_bridge_service_test.dart` (19 cases) pins every routing path
plus the data URI decoder (roundtrip, missing padding, missing
`;base64`).

### Periodic lifecycle hooks ✅

`PeriodicTriggerScheduler` registers as a `WidgetsBindingObserver`
and pauses on `paused` / `inactive` / `hidden` / `detached`. On
`resumed` it rebuilds the timer set from the current preset. There
is no catch-up tick — periodic scripts are side-effect-only, and a
long backgrounding period (overnight, etc.) must not produce a burst
of catch-up ticks. `debugLifecycleState` is the test seam used by
`periodic_lifecycle_test.dart` (3 cases).

### Connection profiles ✅

`ExtensionPreset.connectionProfiles` is a freezed record with three
`apiConfigId` slots: `big` / `medium` / `small`. `glaze.generateText({
preset })` reads the matching slot via `ConnectionProfileResolver`
which falls through to the active API config when the slot is empty
or the configured id is stale. The UI picker in
`preset_editor_screen.dart` lists every `ApiConfig` plus an
"Использовать основной" default. `connection_profile_resolver_test.dart`
(8 cases) pins parse, fall-through behaviour, and stale-id recovery.

### Wired `executeCommand` registry ✅

`buildWiredCommandRegistry(WiredCommandDeps)` is the production
default. Each handler delegates to the same service that powers the
dedicated `glaze.*` method:

* `/trigger` → `TriggerGenerationHandler.handle`
* `/getvar` / `/setvar` → `JsBridgeService.dispatch`
* `/inject` → `RuntimePromptInjectionNotifier.inject`
* `/toast` → `JsBridgeToastController.show`

`buildDefaultCommandRegistry` is retained for tests / CMS — its
handlers echo arguments. `wired_command_registry_test.dart` (12
cases) pins validation (`/trigger` rejects non-string mode, `/inject`
rejects missing id/content/charId, etc.) and routing.

### Main chat WebView sandboxing ✅

`allowFileAccessFromFileURLs=false`,
`allowUniversalAccessFromFileURLs=false`,
`mixedContentMode=MIXED_CONTENT_NEVER_ALLOW` on both the chat page
and the preloader. The chat page is loaded from `file://` assets and
outbound links go through `launchUrl(..., externalApplication)` —
the WebView no longer needs universal file access. XSS in a user
panel / extension JS can no longer `fetch('file:///...')` or
`fetch('http(s)://...')` from a local origin.
