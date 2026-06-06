# Refactor Plan — Bridge, God-Widgets, God-Services

**Status:** Phase 0 (RFC, pre-implementation)
**Scope:** Decompose 4 Dart god-objects and 3 JS god-scripts that grew during the
`js-extension-bridge-sdk` branch (22 feature commits) into focused modules.
**Goal:** Clean foundation for future feature work; no functional changes.
**Implementation timeline:** ~8-12 days, 9 phases, 1 commit per phase.

---

## 1. Why this refactor

The `js-extension-bridge-sdk` branch added 22 feature commits to a working
MVP. Some files accumulated responsibilities well past the project's
"150 lines per class" guideline (`docs/CODE_STYLE.md`):

### Dart god-objects

| File | Lines | Touched by |
|---|---:|---|
| `lib/features/chat/widgets/chat_webview_widget.dart` | **1630** | 6 follow-up commits (sandboxing, audioplayers, periodic lifecycle, command registry, connection profiles, headless engine) |
| `lib/features/extensions/services/extension_post_gen_service.dart` | **1526** | periodic, afterUser, swipe, panels, image gen, js runner, status tracking, error handling |
| `lib/features/extensions/screens/preset_editor_screen.dart` | **1214** | permissions, connection profiles, block editor, model fetching |
| `lib/features/extensions/services/js_bridge_service.dart` | **707** | 8 capability additions, growing ~50-100 lines per new method |

### JS god-scripts

| File | Lines | What |
|---|---:|---|
| `assets/chat_webview/bridge.js` | **2141** | ChatBridgeController, runSandboxedScript, PanelHost, scrollback, settings, periodic dispatch, afterUser — everything |
| `assets/chat_webview/renderer.js` | **1234** | Message rendering, markdown, code highlighting, image embeds |
| `assets/chat_webview/formatter.js` | **443** | ST-macro expansion, text formatting |

### Risk of not refactoring

* Every new feature on the extension surface adds 50-200 lines to the
  existing god-objects. Monblant compat would push `js_bridge_service.dart`
  to 1100+ lines.
* Test coverage of god-objects is forced to mock the entire world.
* Code review on a 1600-line diff is impractical.

---

## 2. Refactor strategy

**Functional behavior is preserved.** No public API changes, no new
features, no test deletions. Every phase is a structural rearrangement
covered by the existing 132 passing tests plus new unit tests for the
extracted modules.

**Two constraints:**

1. Each phase must end with `flutter analyze` clean and
   `flutter test <target files>` 100% green.
2. No phase may exceed 500 net lines of churn (deletions + additions) so
   the PR stays reviewable.

---

## 3. Phases

### Phase 1 — `js_bridge_service.dart` split (1 day)

**Before:** `lib/features/extensions/services/js_bridge_service.dart` (707 lines)
— one class with `_handleGetVariables`, `_handleSetVariables`,
`_handleDeleteVariable`, `_handleExecuteCommand`, `_handleTriggerGeneration`,
`_handlePlayAudio`, `_handleShowToast`, `_handleGenerateText`,
`_handleInjectPrompt`, `_handleUninjectPrompt`, plus the dispatcher.

**After:**

```
lib/features/extensions/services/js_bridge/
  js_bridge_service.dart            (≤150 lines: dispatch + context lookup)
  handlers/
    get_variables_handler.dart
    set_variables_handler.dart
    delete_variable_handler.dart
    execute_command_handler.dart
    trigger_generation_handler.dart
    play_audio_handler.dart
    show_toast_handler.dart
    generate_text_handler.dart
    inject_prompt_handler.dart
    uninject_prompt_handler.dart
  capability_resolver.dart          (read/write/delete per scope → capability id)
  permission_gate.dart              (`_requireCapability` extracted)
```

**Pattern:** each handler exposes `FutureOr<dynamic> handle(JsBridgeContext context)`.
Dispatcher in `js_bridge_service.dart` looks up the handler from a map and
delegates. The `JsBridgeContext` carries `(params, context, repos,
handlers)` so handlers stay testable in isolation.

**Test impact:** existing `test/js_bridge_service_test.dart` (13 cases)
keeps the dispatcher contract; add per-handler unit tests
(`test/handlers/get_variables_handler_test.dart`, etc.).

### Phase 2 — `extension_post_gen_service.dart` → Chain of Responsibility (2 days)

**Before:** one 1526-line service that:

* Walks block chain
* Branches on `BlockType` (infoblock, imageGen, jsRunner, interactive)
* Handles status tracking (`InfoBlock.status` lifecycle)
* Manages image-gen step
* Calls InfoBlockService for infoblocks
* Calls PanelHostService for interactive blocks
* Calls JsEngineService for jsRunner

**After:**

```
lib/features/extensions/services/blocks/
  block_chain.dart                  (≤200 lines: walks blocks, dispatches to handler)
  block_handler.dart                (abstract: `Future<void> handle(BlockContext)`)
  handlers/
    infoblock_handler.dart          (LLM → extract → persist)
    image_gen_handler.dart          (LLM agent → Image Gen service)
    js_runner_handler.dart          (headless engine preferred, visual fallback)
    interactive_handler.dart        (LLM → panel host)
  block_context.dart                (session, message, character, persona, previousOutput, etc.)
  block_status_tracker.dart         (InfoBlock status lifecycle, extracted)
```

**Pattern:** `BlockChain.run(blocks, trigger)` iterates blocks in order,
resolves the right handler, and calls `handler.handle(ctx)`. Status
transitions are centralized in `BlockStatusTracker` so every handler
follows the same `pending → running → done | error | cancelled` flow.

**Test impact:** existing `test/after_user_dispatch_test.dart` and
chain-filter tests stay; add per-handler unit tests
(`test/blocks/infoblock_handler_test.dart`, etc.).

### Phase 3 — `chat_webview_widget.dart` → Mixins (2 days)

**Before:** one 1630-line `ConsumerStatefulWidget` doing WebView setup,
bridge wiring, panel lifecycle, audio lifecycle, swipe handling, periodic
tick consumption, afterUser, theme application, scrollback.

**After:**

```
lib/features/chat/widgets/chat_webview/
  chat_webview_widget.dart          (≤300 lines: build, dispose, composition)
  mixins/
    webview_lifecycle_mixin.dart    (initState, dispose, didChangeAppLifecycleState)
    bridge_host_mixin.dart          (register handlers, _generateBridgeText)
    panel_lifecycle_mixin.dart      (openPanel, closePanel, postToPanel, eventStream)
    audio_lifecycle_mixin.dart      (AudioBridgeService init/dispose/play)
    swipe_mixin.dart                (swipe detection, regeneration flow)
    periodic_dispatch_mixin.dart    (subscribe to PeriodicTriggerScheduler)
    theme_mixin.dart                (apply theme tokens to WebView)
  chat_webview_preload.dart         (already separate, no changes)
```

**Pattern:** `ChatWebViewWidget` mixes in only what it needs. Mixins
expose typed state (`BridgeHostMixin` owns the `JsBridgeService`
instance, `PanelLifecycleMixin` owns the `PanelHostService` subscription,
etc.). Cross-mixin communication goes through a small `ChatWebViewContext`
object passed via constructor.

**Test impact:** mixins are tested in isolation with a `TestChatWebView`
harness widget (`test/mixins/bridge_host_mixin_test.dart`, etc.). End-to-end
behavior is still covered by the manual `flutter run` test.

### Phase 4 — `preset_editor_screen.dart` → Sub-screens (1 day)

**Before:** one 1214-line screen with 6 menu groups, a 580-line
`_BlockEditDialog`, API config selector, model fetcher, profile picker,
permissions toggles, etc.

**After:**

```
lib/features/extensions/screens/preset_editor/
  preset_editor_screen.dart         (≤200 lines: top-level scaffold, navigation)
  sections/
    blocks_section.dart             (list of blocks + add)
    permissions_section.dart        (one SwitchListTile per capability)
    profiles_section.dart           (big/medium/small connection profile mapping)
  block_editor_sheet.dart           (full-screen sheet, was _BlockEditDialog)
  widgets/
    api_config_selector.dart        (reusable, used in block editor + elsewhere)
    model_field.dart                (with fetch button)
    block_type_picker.dart
    block_trigger_picker.dart
    profile_picker_sheet.dart
```

**Pattern:** each section is a `ConsumerWidget` with its own state.
`BlockEditorSheet` is a full-screen modal route (not a dialog) so the
form gets the full viewport — solves the cramped-dialog UX issue too.

**Test impact:** widget tests for each section widget (`golden tests`
optional, smoke tests required).

### Phase 5 — `bridge.js` → ES modules (3 days)

**Before:** `assets/chat_webview/bridge.js` (2141 lines) — a single IIFE
that holds ChatBridgeController, Sandbox, PanelHost, scrollback,
settings, character rendering tooltips, gestures, periodic dispatch,
afterUser.

**After:**

```
assets/chat_webview/bridge/
  index.js                          (≤100 lines: bootstrap, re-export facade)
  chat_bridge_controller.js         (main controller, registers handlers)
  sandbox_runner.js                 (runSandboxedScript, iframe relay)
  panel_host.js                     (PanelHost class, openPanel/closePanel/postToPanel)
  scrollback.js                     (chat scroll, message list)
  settings.js                       (applyTheme, setMessages, etc.)
  gestures.js                       (swipe, scroll, keyboard)
  periodic_dispatch.js              (subscribe to periodic events from Dart)
  after_user.js                     (subscribe to afterUser events)
  message_renderer.js               (delegates to renderer.js modules)
```

**Loading:** replace the single `<script src="bridge.js">` with
`<script type="module" src="bridge/index.js">` in
`assets/chat_webview/index.html`. Modules export their public surface,
`index.js` wires the public surface to the controller.

**Risk:** ES module loading from `file://` WebView is well-supported on
modern WebView (Android 5+ / iOS 11+ / desktop WebView2/WKWebView).
**Mitigation:** keep a fallback `bridge.legacy.js` (the current file) for
one release; switch the default in `index.html` only after smoke test
on every desktop platform.

**Test impact:** add `test/webview_assets_module_test.dart` that asserts
each new module is referenced from `index.js` and is syntactically valid
(parsed via `dart:js_util` or a static check).

### Phase 6 — `renderer.js` → modules (1 day)

**Before:** `assets/chat_webview/renderer.js` (1234 lines).

**After:**

```
assets/chat_webview/renderer/
  index.js                          (public `renderMessage` facade)
  markdown.js                       (markdown → safe HTML)
  code_highlight.js                 (```lang fences → highlighted)
  image_embed.js                    ([IMG:GEN] / data-uri rendering)
  message_template.js               (avatar, name, role-specific CSS classes)
  macros_in_message.js              ({{user}}, {{char}} in body)
```

### Phase 7 — `formatter.js` → modules (0.5 day)

**Before:** `assets/chat_webview/formatter.js` (443 lines).

**After:**

```
assets/chat_webview/formatter/
  index.js                          (public `formatText` facade)
  macros.js                         ({{...}} expansion)
  text_format.js                    (italics, bold, code inline)
```

### Phase 8 — Test coverage, docs sync, final PR (1.5 days)

* Per-handler, per-mixin, per-section unit tests (target: 50+ new
  assertions).
* Update `docs/ARCHITECTURE.md` § 9 to reflect the new module
  boundaries.
* Update `docs/CODE_STYLE.md` with concrete examples of how the
  decomposed modules are organized (anti-pattern: god-widget).
* Update `docs/js_extensions_implementation_plan.md` "Final state"
  table with the new file layout.
* `flutter analyze` — 0 new errors.
* `flutter test` — all 132 existing + 50+ new = 180+ passing.
* One final PR, titled "refactor(ext): decompose god-objects from
  js-extension-bridge-sdk branch".

---

## 4. Out of scope

* **No new features.** This PR is structural only.
* **No public API changes.** All ext-blocks behavior is preserved.
* **No god-object that is < 500 lines is touched.** Examples: the
  `panel_host_service.dart` (already a focused service), the
  `audio_bridge_service.dart` (already small), the
  `command_registry.dart` (already a registry).
* **No new dependencies.** The ES module refactor in Phase 5 uses
  built-in browser support; no bundler (rollup / esbuild) is added.
* **No test deletion.** Existing 132 assertions must keep passing.

---

## 5. Risk register

| Risk | Mitigation |
|---|---|
| `flutter analyze` regressions during mixin extraction | Each Phase 1-4 ends with `flutter analyze <target files>` clean. CI gate: 0 new errors. |
| Existing tests break during refactor | Run `flutter test <target>` after every commit. If a test breaks, fix the refactor, not the test. |
| ES modules don't load on a specific platform | `bridge.legacy.js` fallback kept for one release. |
| Mixin lifecycle interactions (e.g. dispose order) | Add a `ChatWebViewHarness` test widget that asserts clean dispose. |
| Reviewer fatigue on 9-commit PR | Squash at PR time into 1 commit per phase. Phases are independent enough to merge separately if needed. |
| 8-12 day timeline slips | Each phase ships independent. If Monblant RFC is approved mid-refactor, Monblant work can start on already-refactored modules. |

---

## 6. Open questions

* **Mixin vs separate widgets in Phase 3:** are mixins the right call,
  or should we extract full sub-widgets (e.g. `BridgeHostWidget`)? Mixins
  keep the public widget tree flat; sub-widgets add a layer.
* **`bridge.legacy.js` fallback duration:** one release (Phase 5+1) or
  drop immediately after smoke test?
* **Section widgets in Phase 4:** keep them as private
  (`sections/_blocks_section.dart`) or expose as public for re-use by
  a future "preset card" home-screen widget?

---

## 7. Approval & sign-off

- [ ] Lead developer review of file boundaries
- [ ] Open questions answered (Section 6)
- [ ] Timeline confirmation (8-12 days, 9 phases)
- [ ] "bridge.legacy.js" fallback decision
