# Refactor Plan — Bridge, God-Widgets, God-Services

**Status:** Phase 2 in progress. Phase 1 complete.
**Scope:** Decompose 4 Dart god-objects and 3 JS god-scripts that grew during the
`js-extension-bridge-sdk` branch (22 feature commits) into focused modules.
**Goal:** Clean foundation for future feature work; no functional changes.
**Implementation timeline:** ~9-13 days, RFC + 9 implementation phases, split across small PRs.

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

**Constraints:**

1. Each phase must end with `flutter analyze` clean and
   `flutter test <target files>` 100% green.
2. Each phase must preserve the relevant invariants from
   `docs/INVARIANTS.md`, especially INV-EG1-8 and INV-JS1-6 for extension
   generation and JS bridge work.
3. Keep reviewable diffs by separating pure file moves from behavior edits.
   The JS phases may exceed 500 lines of churn because module extraction is
   mostly move churn; those commits must be move-only where possible.
4. Ship as multiple small PRs instead of one large PR:
   `js_bridge_service`, `extension_post_gen_service`, `chat_webview_widget`,
   `preset_editor_screen`, and JS assets.

---

## 3. Phases

### Phase 0.5 — ES module WebView spike (0.5 day)

**Goal:** prove that `type="module"` assets load correctly in the app WebView
before moving `bridge.js`, `renderer.js`, or `formatter.js`.

**Work:**

* Add a minimal temporary module asset imported from `index.html` behind a
  dev-only/static-test-visible hook.
* Verify it loads in the Windows WebView2 target with a manual smoke test.
* Add/update a static asset test so the module entrypoint is covered by tests.
* Remove the spike hook before continuing, unless it is useful as a permanent
  asset-loading guard.

**Gate:** do not start Phase 5-7 until this spike passes. If the spike fails,
keep single-file scripts for this refactor and defer ES modules to a separate
platform-compatibility task.

### Phase 1 — `js_bridge_service.dart` split (1 day) ✅ Done

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
    variables_handler.dart           (get/set/delete + atomic scope methods)
    generation_handler.dart          (generateText + triggerGeneration)
    prompt_injection_handler.dart    (injectPrompt + uninjectPrompt)
    audio_handler.dart               (playAudio)
    command_handler.dart             (executeCommand)
    toast_handler.dart               (showToast)
  capability_resolver.dart          (read/write/delete per scope → capability id)
  permission_gate.dart              (`_requireCapability` extracted)
```

**Pattern:** handlers are grouped by domain to avoid one-class-per-tiny-method
class explosion. Each handler exposes typed methods and the dispatcher in
`js_bridge_service.dart` maps bridge method names to the matching method. The
`JsBridgeContext` carries `(params, context, repos, handlers)` so handlers stay
testable in isolation.

**Test impact:** existing `test/js_bridge_service_test.dart` (13 cases)
keeps the dispatcher contract; add per-domain handler unit tests
(`test/js_bridge/variables_handler_test.dart`, etc.).

**Implemented:** `lib/features/extensions/services/js_bridge_service.dart` is now
a compatibility export. The implementation lives under
`lib/features/extensions/services/js_bridge/` with domain handlers for
variables, generation, prompt injection, audio, commands, and toast. Added
`test/js_bridge/generation_handler_test.dart`.

**Verification:** targeted analyze passed for the extracted bridge files and new
test. Targeted tests passed: `test/js_bridge/generation_handler_test.dart`,
`test/js_bridge_service_test.dart`, `test/play_audio_bridge_test.dart`,
`test/js_bridge_toast_test.dart`, `test/global_message_variables_test.dart`,
`test/trigger_generation_test.dart`, and `test/wired_command_registry_test.dart`
(63 tests).

### Phase 2 — `extension_post_gen_service.dart` → block processors (2 days) 🚧 In progress

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
  block_processor.dart              (≤200 lines: walks blocks, dispatches to handler)
  block_handler.dart                (abstract: `Future<void> handle(BlockContext)`)
  handlers/
    infoblock_handler.dart          (LLM → extract → persist)
    image_gen_handler.dart          (LLM agent → Image Gen service)
    js_runner_handler.dart          (headless engine preferred, visual fallback)
    interactive_handler.dart        (LLM → panel host)
  block_context.dart                (session, message, character, persona, previousOutput, etc.)
  block_status_tracker.dart         (InfoBlock status lifecycle, extracted)
```

**Pattern:** keep the abstraction minimal: `BlockProcessor.run(blocks, trigger)`
iterates blocks in order, resolves a handler from `Map<BlockType, BlockHandler>`,
and calls `handler.handle(ctx)`. Status transitions are centralized in
`BlockStatusTracker` so every handler follows the same
`pending → running → done | error | cancelled` flow. Do not introduce a
full chain-of-responsibility framework unless the current behavior needs it.

**Test impact:** existing `test/after_user_dispatch_test.dart` and
chain-filter tests stay; add per-handler unit tests
(`test/blocks/infoblock_handler_test.dart`, etc.).

**Implemented so far:** extracted `BlockProcessor` with filter/order/
`dependsOnPrevious` orchestration into
`lib/features/extensions/services/blocks/block_processor.dart`. Added
`BlockContext` and `BlockHandler` scaffolding. `ExtensionPostGenService._runChain`
now delegates orchestration to `BlockProcessor`. Extracted concrete handlers for
`infoblock`, `imageGen`, `interactive`, and `jsRunner` into `services/blocks/`.
The shared image pixel render step remains in `ExtensionPostGenService` because
`rerunImageOnly()` uses it too; JS execution/fallback helpers also remain there
for now because periodic `runJsBlock()` shares the same headless/visual fallback
semantics. Extracted shared panel update/throttling plumbing into
`BlockPanelUpdater`, placeholder/error/dedupe lifecycle into
`BlockStatusTracker`, and shared image pixel rendering/persistence into
`ImagePixelRenderer`. Extracted message-bound `jsRunner` execution/headless
fallback persistence into `JsBlockExecutor`; periodic `runJsBlock()` still stays
on `ExtensionPostGenService` because it is the public scheduler entry point.

**Verification so far:** targeted analyze passed for
`extension_post_gen_service.dart`, `services/blocks`, and
`test/blocks/block_processor_test.dart`. Targeted tests passed:
`test/blocks/block_processor_test.dart`, `test/after_user_dispatch_test.dart`,
`test/periodic_trigger_scheduler_test.dart`, `test/periodic_lifecycle_test.dart`,
`test/panel_host_service_test.dart`, and `test/js_engine_service_test.dart` (27
tests) after extracting all four concrete handlers.

### Phase 3 — `chat_webview_widget.dart` → controllers/services (2 days)

**Before:** one 1630-line `ConsumerStatefulWidget` doing WebView setup,
bridge wiring, panel lifecycle, audio lifecycle, swipe handling, periodic
tick consumption, afterUser, theme application, scrollback.

**After:**

```
lib/features/chat/widgets/chat_webview/
  chat_webview_widget.dart          (≤300 lines: build, lifecycle delegation)
  chat_webview_controller.dart      (coordinates WebView state + disposal order)
  bridge_host_controller.dart       (register handlers, generate bridge text)
  panel_lifecycle_controller.dart   (openPanel, closePanel, postToPanel, stream)
  swipe_controller.dart             (swipe detection, regeneration flow)
  periodic_dispatch_controller.dart (subscribe to PeriodicTriggerScheduler)
  theme_applier.dart                (apply theme tokens to WebView)
  chat_webview_preload.dart         (already separate, no changes)
```

**Pattern:** keep `ChatWebViewWidget` as a thin `ConsumerStatefulWidget` that
owns lifecycle hooks and delegates to focused controllers/services. Avoid
mixins as the primary decomposition mechanism because they hide dependencies
and make `initState`/`dispose` ordering fragile. Cross-controller state goes
through an explicit `ChatWebViewContext` or constructor dependencies.

**Test impact:** controllers are tested in isolation where possible
(`test/chat_webview/bridge_host_controller_test.dart`, etc.). Add one widget
harness test that asserts clean init/dispose ordering. End-to-end behavior is
still covered by the manual `flutter run` smoke test.

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
  block_edit_dialog.dart            (same UX as current _BlockEditDialog)
  widgets/
    api_config_selector.dart        (reusable, used in block editor + elsewhere)
    model_field.dart                (with fetch button)
    block_type_picker.dart
    block_trigger_picker.dart
    profile_picker_sheet.dart
```

**Pattern:** each section is a `ConsumerWidget` with its own state. This phase
is structural only: keep the current dialog UX while extracting it into a file.
A full-screen block editor sheet can be done later as a separate UX PR because
it changes behavior.

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

**Risk:** ES module loading from Flutter/WebView asset URLs must be verified
on the target WebView implementation before this phase starts.
**Mitigation:** Phase 0.5 gates this phase. If it passes, keep a fallback
`bridge.legacy.js` (the current file) for one release or until platform smoke
tests confirm the module entrypoint is stable.

**Test impact:** add `test/webview_assets_module_test.dart` that asserts
each new module is referenced from `index.js` and that no required asset is
orphaned. Syntax validation should use a static check available in the repo
environment; do not depend on `dart:js_util` in VM Flutter tests.

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

### Phase 8 — Test coverage, docs sync, release gates (1.5 days)

* Per-handler, per-controller, per-section unit tests (target: 50+ new
  assertions).
* Run the `docs/INVARIANTS.md` refactor checklist for affected areas,
  especially INV-EG1-8 and INV-JS1-6.
* Update `docs/ARCHITECTURE.md` § 9 to reflect the new module
  boundaries.
* Update `docs/CODE_STYLE.md` with concrete examples of how the
  decomposed modules are organized (anti-pattern: god-widget).
* Update `docs/js_extensions_implementation_plan.md` "Final state"
  table with the new file layout.
* `flutter analyze` — 0 new errors.
* `flutter test` — all 132 existing + 50+ new = 180+ passing.
* Final PR in the series updates docs and removes any temporary fallback or
  spike-only hooks that are no longer needed.

---

## 4. Out of scope

* **No new features.** This PR is structural only.
* **No UX changes in structural PRs.** For example, replacing the block edit
  dialog with a full-screen sheet is a separate follow-up UX PR.
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
| `flutter analyze` regressions during controller extraction | Each Phase 1-4 ends with `flutter analyze <target files>` clean. CI gate: 0 new errors. |
| Existing tests break during refactor | Run `flutter test <target>` after every commit. If a test breaks, fix the refactor, not the test. |
| ES modules don't load on a specific platform | Phase 0.5 spike gates Phase 5-7. If it fails, keep single-file scripts and defer ES modules. |
| Controller lifecycle interactions (e.g. dispose order) | Add a `ChatWebViewHarness` test widget that asserts clean init/dispose ordering. |
| Reviewer fatigue on a large PR | Ship as multiple PRs by subsystem. Keep pure moves separate from behavior edits. |
| 9-13 day timeline slips | Each phase ships independent. If Monblant RFC is approved mid-refactor, Monblant work can start on already-refactored modules. |

---

## 6. Open questions

* **`bridge.legacy.js` fallback duration:** if Phase 0.5 passes, keep the
  fallback for one release or drop immediately after platform smoke tests?
* **Section widgets in Phase 4:** keep them private initially
  (`sections/_blocks_section.dart`) or expose as public now? Default: private
  until a second real consumer exists.

---

## 7. Approval & sign-off

- [ ] Lead developer review of file boundaries
- [ ] Open questions answered (Section 6)
- [ ] Timeline confirmation (9-13 days, RFC + 9 implementation phases)
- [ ] Phase 0.5 ES module WebView spike result recorded
- [ ] "bridge.legacy.js" fallback decision
