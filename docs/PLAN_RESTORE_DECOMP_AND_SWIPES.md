# PLAN: Restore Studio decomposition (auto + manual) and full agentSwipes hierarchy

STATUS: NOT STARTED
BRANCH: continue on `plan/continuity-post-cleaner` (or branch `feat/restore-decomp-swipes` off it)
PR TARGET: `hydall/GlazeFlutter:master`

## Why this plan exists

During the Agentic Studio refactor (`docs/PLAN_AGENTIC_STUDIO.md`, Phase 2,
commit `0a9e6cd`) two user-facing capabilities were intentionally deleted to
simplify the pipeline. The user has since asked for BOTH back:

1. **Preset decomposition** — building Studio trackers FROM the user's active
   preset (auto), PLUS manual editing of each tracker's prompt shard. Right now
   trackers run on hardcoded lanes (`_controllerScope` in
   `memory_studio_service.dart`) and their `promptShard` is whatever was already
   in the DB from before the refactor. There is no builder and no manual editor.

2. **Full `agentSwipes` hierarchy** — the nested swipe variations (POST-cleaner
   output and final-regen output stored as colour-coded sub-swipes under a
   message, with blue/white colour coding in the WebView). Right now the cleaner
   appends a flat green swipe (`appendCleanerSwipe`) with empty `swipesMeta`, so
   there is no colour coding and no nested structure.

User decisions (explicit):
- Decomposition: "вернуть и ручной и авто-декомпозишн" → restore BOTH auto
  decompose AND manual shard editing.
- Swipes: "Полная иерархия agentSwipes" → restore the full nested system, not
  just colour coding.

## Ground truth: what was deleted and where to recover it from

The last commit BEFORE deletion is **`f49e78a`** ("feat: post-cleaner streams
rewrite into chat bubble"). Everything below can be read with:

```
git show f49e78a:<path>
```

The deletion commit is **`0a9e6cd`**. Read its body for the exact list:

```
git show 0a9e6cd --stat
git show 0a9e6cd            # full diff of what was removed
```

### Files deleted outright in 0a9e6cd (recover from f49e78a)
- `lib/core/llm/studio_decomposition_service.dart` (1191 lines) — the auto
  decompose engine. Contains `_ControllerSpec`, `_controllerSpecs` (the 8
  built-in lanes), `StudioDecompositionService.decompose(...)`,
  `.regenerateAgentInstruction(...)`, `studioDecompositionServiceProvider`.
- `test/nested_swipes_test.dart` (238 lines) — agentSwipes behaviour tests.
- `test/post_cleaner_mapper_test.dart` (65 lines) — cleaner→swipe mapping tests.
- `test/studio_block_router_test.dart` (510 lines) — block-routing tests.
- `test/studio_verbatim_routing_test.dart` (252 lines) — verbatim routing tests.

### Files heavily gutted in 0a9e6cd (diff against f49e78a to see what to re-add)
- `lib/core/models/chat_message.dart` (−75 lines): the `AgentSwipe` class +
  `agentSwipes` / `agentSwipeId` / `studioOutputs` fields on `ChatMessage`.
- `lib/core/db/repositories/chat_repo.dart` (−84/+25): `appendAgentSwipe({kind})`
  with `kind: 'cleaned' | 'final'`, parent-swipe linking, and
  `_syncAgentSwipesToMeta(...)`. (Current code has `appendCleanerSwipe` instead.)
- `lib/features/chat/chat_message_service.dart` (−250 lines): agentSwipe wiring.
- `lib/features/chat/controllers/chat_message_ops_controller.dart` (−91 lines).
- `lib/features/chat/controllers/chat_swipe_controller.dart` (−40 lines).
- `lib/features/chat/bridge/chat_message_mapper.dart` (−12 lines): mapped
  `agentSwipes` / `agentSwipeId` / `kind` into the JS payload (current mapper
  only sends `swipeIndex` + `swipeTotal`).
- `lib/features/chat/widgets/chat_message_sync.dart` (−22 lines).
- `lib/features/chat/widgets/post_cleaner_diff_dialog.dart` (−59 lines): used
  to diff the cleaner sub-swipe vs its parent.
- `lib/features/chat/widgets/studio_menu_dialog.dart` (−2303 lines!): the full
  decompose UI ("Build Studio" button → `_buildStudio()` → `decompose()`;
  per-agent "regenerate instruction" → `_regenerateAgentInstruction()`; the
  advanced editor section `_buildStudioAdvancedSection()` with shard editing).
  NOTE: this file was REWRITTEN AGAIN in Phase 7 (`6eb46ee`) and AGAIN by the
  bugfix commit `e350038` (added the inline model picker). Do NOT blindly revert
  it — merge the old decompose/editor UI INTO the current lightweight dialog.
- `lib/features/chat/widgets/chat_input_bar.dart` (−11 lines).
- `lib/features/chat/widgets/prompt_preview_screen.dart` (−27 lines).
- `lib/features/chat/widgets/post_cleaner_status_card.dart` (−1 line).

### JS / WebView side gutted in 0a9e6cd
- `assets/chat_webview/bridge/interaction_dispatch.js` (−22): `agent-swipe-left`
  / `agent-swipe-right` actions + `onAgentSwipe` dispatch.
- `assets/chat_webview/renderer/message_renderer.js` (−141): the agent-switcher
  rendering (`kind === 'agent-swipe'` branch in `_createSwitcher`, the
  `agent-switcher` CSS class, colour coding). `_createSwitcher` STILL has the
  `kind` param and the `agent-swipe` branches partially — verify current state.
- `assets/chat_webview/bridge/chat_bridge_controller.js` (−40): handlers
  `onAgentSwipe`, `onStudioOutputEdit`, `onStudioOutputRegen`.
- `assets/chat_webview/bridge/edit_controller.js` (−4).

  After ANY change under `assets/chat_webview/`, the user must HOT RESTART
  (press `R`), not hot reload — see CLAUDE.md.

## IMPORTANT constraints carried over from the refactor

- The current pipeline is **tracker-around-generator** (one generator + N
  trackers batched by `(provider, model)`), NOT the old 8-controller
  sequential ontology. Decomposition must produce `StudioAgent`s that slot into
  the CURRENT `runTrackerCycle` (the last enabled agent = the generator, the
  rest = trackers). Do NOT resurrect `runPipeline` / the 8-slot orchestration.
- `StudioAgent` already has all needed fields (`promptShard`, `modelOverride`,
  `contextSize`, `runInterval`, `runIndividually`, `role`, `order`,
  `sourceBlockNames`). The decompose engine just needs to POPULATE them. No
  Drift schema change expected for decomposition.
- `StudioConfig` already carries `sourcePresetId`, `sourcePresetHash`,
  `broadcastBlocks`, `studioPresetOverrides`, `routingMode`,
  `builderPromptTemplate`, `buildApiConfigId`, `buildModelOverride` — these were
  kept precisely so decompose can be restored without a migration. Verify in
  `lib/core/models/studio_config.dart`.
- For `agentSwipes`: the model fields were REMOVED, so this DOES need a
  freezed regen (`dart run build_runner build`). `.freezed.dart`/`.g.dart` are
  gitignored — regenerate, don't commit them.
- Keep the `<think>` stripping the bugfix commit `e350038` added to the cleaner.
  When restoring `appendAgentSwipe`, the cleaner swipe content must STILL be
  the think-stripped text.
- Cleaner already works (HTTP path, retry, ops log). Restoring agentSwipes is
  about HOW the result is STORED and DISPLAYED, not about re-running the cleaner.

## Suggested phasing (each phase = its own commit; analyze + test between)

### Phase A — Restore preset decomposition (auto)
A.1 Recover `studio_decomposition_service.dart` from `f49e78a`. Read it fully
    first — it references `PresetBlock`, `pipeline_settings_provider`,
    `api_list_provider`, `studio_block_router.dart`. Confirm those still exist
    and the signatures still match (the router survived: `studio_block_router.dart`).
A.2 Re-register `studioDecompositionServiceProvider`.
A.3 Confirm `decompose()` output (`List<StudioAgent>`) is compatible with the
    current `runTrackerCycle` consumer ordering (last = generator). Adjust the
    `order` assignment if the old engine assumed the 8-slot order.
A.4 Re-add the "Build Studio" entry point. Old UI lived in
    `studio_menu_dialog.dart` `_buildStudio()` (see `f49e78a` lines ~108-205).
    Integrate into the CURRENT dialog (don't revert the file). Wire
    `decompose()` → `studioConfigRepo.upsert(config.copyWith(agents: ...))`.
A.5 Capture `broadcastBlocks` + `sourcePresetHash` at build time (the old
    `_buildStudio` did this — it feeds the cleaner's authoritative rules).
A.6 Restore deleted tests where still relevant: `studio_block_router_test.dart`,
    `studio_verbatim_routing_test.dart` (recover from `f49e78a`, fix any API
    drift). Run `flutter test`.

### Phase B — Restore manual shard editing
B.1 Old per-agent editor + `_regenerateAgentInstruction()` lived in
    `studio_menu_dialog.dart` (`f49e78a` lines ~207-250 + the advanced section
    ~825+). Recover the shard TextField editor + the "regenerate this agent's
    instruction" button (calls `regenerateAgentInstruction`).
B.2 Integrate into the current dialog next to the model chip from `e350038`.
    Keep it lightweight; the old file was 2354 lines — do NOT restore all of it,
    only the shard-edit + regenerate affordances.
B.3 Persist edits via `studioConfigRepo.upsert`.

### Phase C — Restore agentSwipes data model
C.1 Re-add `AgentSwipe` class + `agentSwipes` / `agentSwipeId` / `studioOutputs`
    to `chat_message.dart` (recover from `f49e78a`). `dart run build_runner build`.
C.2 Restore `chat_repo.dart` `appendAgentSwipe({required String kind, ...})`
    (kind: 'cleaned' | 'final') + `_syncAgentSwipesToMeta(...)`. Decide whether
    to KEEP `appendCleanerSwipe` as a thin wrapper or replace its call sites.
    The cleaner call site is `post_cleaner_service.dart` `applyCleanedText` and
    `generation_pipeline.dart` ~814. Make the cleaner write a `kind: 'cleaned'`
    agent swipe again (with think-stripped text from `e350038`).
C.3 Restore `chat_message_service.dart`, `chat_message_ops_controller.dart`,
    `chat_swipe_controller.dart`, `chat_message_sync.dart` agentSwipe wiring
    (diff each against `f49e78a`).

### Phase D — Restore agentSwipes display (JS WebView)
D.1 `chat_message_mapper.dart`: map `agentSwipes` / `agentSwipeId` / per-swipe
    `kind` into the JS payload again (recover the −12 lines from `f49e78a`).
D.2 `message_renderer.js`: restore the agent-switcher rendering + blue/white
    colour coding (`kind === 'agent-swipe'` / `agent-switcher` class). Check
    current state first — `_createSwitcher` still has partial `agent-swipe`
    branches.
D.3 `interaction_dispatch.js`: restore `agent-swipe-left` / `agent-swipe-right`
    + `onAgentSwipe`.
D.4 `chat_bridge_controller.js`: restore `onAgentSwipe` (and decide on
    `onStudioOutputEdit` / `onStudioOutputRegen` — only if Phase B/E needs them).
D.5 `edit_controller.js`: restore the 4 removed lines.
D.6 Verify `webview_assets_test` still passes (it was updated in 0a9e6cd to drop
    `onStudioOutput` — re-add expectations as needed).
    REMIND THE USER: hot RESTART (R) after JS changes.

### Phase E — diff dialog + tests + docs
E.1 `post_cleaner_diff_dialog.dart`: restore diffing the cleaner sub-swipe vs
    its parent (the −59 lines). Current version diffs current vs previous green
    swipe — reconcile with the restored nested model.
E.2 Recover `nested_swipes_test.dart` + `post_cleaner_mapper_test.dart` from
    `f49e78a`; fix API drift; `flutter test`.
E.3 Update docs: `ARCHITECTURE.md` (Studio Mode Pipeline + swipes),
    `INVARIANTS.md` (the INV-ST* set claims AgentSwipe was removed — revise
    INV-ST4 and add swipe/ decomposition invariants), `rules/generation.md`,
    `rules/database.md` (appendAgentSwipe atomic method + swipesMeta kind),
    and mark `docs/PLAN_NESTED_SWIPES.md` no longer SUPERSEDED if applicable.

## Verification gates (run for every phase)
- `& "Z:\GlazeProject\flutter\bin\flutter.bat" analyze`  → 0 errors
- `& "Z:\GlazeProject\flutter\bin\flutter.bat" test`     → all pass
- `dart run build_runner build` after editing chat_message.dart (freezed)
- Ask the user to `flutter run` for runtime smoke (the agent cannot run it):
  - Build Studio from a preset → trackers appear with shards.
  - Edit a tracker shard + regenerate instruction → persists.
  - Generate a turn → cleaner produces a BLUE sub-swipe, original preserved,
    swipe switcher colour-coded, no raw `<think>` leakage.

## Watch-outs / gotchas
- `studio_menu_dialog.dart` has been rewritten THREE times (Phase 2, Phase 7,
  bugfix e350038). NEVER `git checkout f49e78a -- studio_menu_dialog.dart` —
  you will lose the model picker + lightweight layout. Cherry-pick code by hand.
- The HTTP-400 batch fix (e350038) added a mandatory `user` turn in
  `memory_studio_service.dart` `_runBatchGroup`. Keep it.
- The Tracker-values tab fix (e350038) moved `_SessionScope` reads to
  `didChangeDependencies`. Keep it.
- The MemoryBooks `SizedBox(82%)` fix (e350038) — keep it.
- `INVARIANTS.md` currently asserts AgentSwipe is GONE (INV-ST4). Restoring it
  contradicts that invariant — update the doc, don't leave it stale.
- Confirm there is no Drift migration needed for decomposition (fields already
  exist). agentSwipes lives inside `messagesJson` (JSON blob), so NO Drift
  schema bump there either — only a freezed model regen.

## Reference commits
- `f49e78a` — last commit WITH decomposition + agentSwipes (recover source here).
- `0a9e6cd` — Phase 2 deletion (read its diff for the exact removal list).
- `6eb46ee` — Phase 7 rewrote studio_menu_dialog into the lightweight dialog.
- `e350038` — the 5 bugfixes (model picker, batch 400, spinner, cleaner think,
  sheet layout). Build on top of this; do not undo it.
