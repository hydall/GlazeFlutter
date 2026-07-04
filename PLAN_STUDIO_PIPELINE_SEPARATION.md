# Studio Pipeline Separation — Refactor Plan

**Branch:** `refactor/studio-pipeline-separation`
**Base:** `master` @ `d09a671d` (post PR #222)
**Goal:** Fully separate Studio and main pipeline; remove dead code/toggles; decompose god objects; unify pipeline as single sequence.

## Decisions (locked)

1. **Write-loop = Studio-only.** Without Studio, trackers don't update automatically (they already don't inject without Studio — only `scope='ledger'` trackers inject, and those are Studio-only). MemoryBook continues working via drafts/dedup/retrieval.
2. **4 model slots:**
   - **Expensive** (`expensiveApiConfigId` + `StudioAgentSettings.finalModelOverride`) → Studio final
   - **Cheap** (`cheapApiConfigId` + `StudioAgentSettings.trackerModelOverride`) → Studio agents
   - **Semi-expensive** (`cleanerApiConfigId` + `CleanerSettings.modelOverride`) → Cleaner + Fact-checker + Ledger + Write-loop
   - **MemoryBook** (`MemoryBookApiSettings.apiConfigId` + `modelOverride`) → Drafts + Dedup + Consolidation
3. **Fail explicitly** when Studio slot `apiConfigId` is empty/not found — no silent fallback to active chat config.
4. **Non-Studio cleaner path deleted.** Cleaner becomes Studio-only. `postCleanerSource/Endpoint/ApiKey`, `aux*`, `resolveConfigForCleaner`, `resolveConfigForAudit` — all removed.
5. **PipelineSettings split** into sub-models: `StudioAgentSettings`, `CleanerSettings`, `LedgerSettings`, `MemoryPipelineSettings`, `MemoryBookApiSettings`.
6. **Fact-checker stays inside cleaner** (Pass 0). Not a separate service.
7. **Write-loop moves AFTER cleaner** — sees canonical text, not raw LLM output.
8. **Image tags move AFTER cleaner** — operate on canonical text.
9. **3 dead dialogs deleted:** `post_building_menu_dialog.dart`, `studio_menu_dialog.dart`, `studio_settings_screen.dart`.
10. **`generation_pipeline.dart` decomposed** from 2397 lines into ~10 stage classes.
11. **Hardcoded live gates:**
    - `agentWriteApprovalRequired` → `true` (always)
    - `postCleanerCharacterCheckEnabled` → `true` (always)
    - `postCleanerContinuityEnabled` → `true` (always)
    - `messageRecallEnabled` → `true` (always)
    - `memoryDedupAutoEnabled` → `false` (always, manual dedup only)
12. **Embedding model** — from active API config (already works via `embeddingConfigProvider`).

## New Pipeline Order

### Studio ON
```
1.  Studio pre-gen agents              — cheap slot
2.  Final generation (SSE)             — expensive slot
3.  Sync + notification                — immediate
4.  Post-cleaner
    ├─ Fact-checker (Pass 0)           — semi slot
    ├─ Prose rewrite + beauty          — semi slot
    └─ Ext blocks launch               — bound to canonical swipe
5.  Image tags                         — on canonical text
6.  Write-loop                         — semi slot, on canonical text
7.  Ledger                             — semi slot
8.  Embed (parallel, fire-and-forget)  — active API config
9.  Auto-create drafts (parallel)      — no LLM
```

### Studio OFF
```
1.  Generation (SSE)                   — active chat config
2.  Sync + notification
3.  Image tags
4.  Ext blocks
5.  Embed (parallel)
6.  Auto-create drafts (parallel)
```

## Implementation Phases (all in one PR)

### Commit breakdown
1. `0445cade` — Phase 1+2: split PipelineSettings into 5 nested sub-models + delete dead dialogs
2. `06e7358d` — Phase 3a: StudioSlotResolver + idle timeout + service signature changes + remove routing fields
3. `06e7358d` — Phase 3a: StudioSlotResolver + idle timeout + service signature changes + remove routing fields
4. `78008aa7` — Phase 4: reorder pipeline stages ✅
5. *(pending)* — Phase 5: decompose generation_pipeline.dart ✅
6. *(pending)* — Phase 6: UI updates

### Phase 1: Delete dead code + fields ✅ DONE
- [x] Delete `post_building_menu_dialog.dart` (1835 lines)
- [x] Delete `studio_menu_dialog.dart` (1464 lines)
- [x] Delete `studio_settings_screen.dart` (257 lines)
- [x] Remove all imports referencing them
- [x] Remove 12 fully-dead fields from `PipelineSettings` (was 9 — audit found 3 more: `consolidationEnabled/Threshold/TimeoutMs`)
- [x] Remove 6 bypassed enabled-toggles (`agenticWriteEnabled`, `postCleanerEnabled`, `studioLedgerEnabled`, `agenticWriteBlockNextGen`, `agenticWriteRunMode`, `runAgenticEveryN`)
- [x] Hardcode 5 live gates (`agentWriteApprovalRequired`→true, `postCleanerCharacterCheckEnabled`→true, `postCleanerContinuityEnabled`→true, `messageRecallEnabled`→true, `memoryDedupAutoEnabled`→false)
- [x] Simplify `pipeline_settings_provider.dart` migration (removed V1 migration + schema version tracking)
- [x] Update all affected tests (5 files: `memory_cadence_test`, `memory_budget_settings_test`, `post_cleaner_test`, `stage5_agentic_toggle_test`, `studio_ledger_infblock_warning_test`)
- [x] `build_runner` + `flutter analyze` (0 errors, 2 pre-existing warnings) + `flutter test` (1499/1499 passed)
- **Deferred to Phase 3:** Remove non-Studio cleaner config fields (`postCleanerSource/Endpoint/ApiKey`, `aux*`, `consolidation*`) — LIVE fields that require simultaneous resolver removal in `aux_llm_client.dart`
- **Note:** `ledger_diagnostics_sheet.dart` (854 lines) orphaned after `studio_menu_dialog.dart` deletion — not in plan, left as-is

### Phase 2: Split PipelineSettings into sub-models ✅ DONE
- [x] Create `StudioAgentSettings` freezed model (`lib/core/models/studio_agent_settings.dart`)
- [x] Create `CleanerSettings` freezed model (`lib/core/models/cleaner_settings.dart`)
- [x] Create `LedgerSettings` freezed model (`lib/core/models/ledger_settings.dart`)
- [x] Create `MemoryPipelineSettings` freezed model (`lib/core/models/memory_pipeline_settings.dart`)
- [x] Create `MemoryBookApiSettings` freezed model (`lib/core/models/memory_book_api_settings.dart`)
- [x] Rewrite `pipeline_settings.dart` — 80 flat fields → 5 nested sub-models (`studioAgent`, `cleaner`, `ledger`, `memoryPipeline`, `memoryBookApi`)
- [x] Rewrite `pipeline_settings_provider.dart` — flat→nested migration (idempotent, persists back after migration); single provider + single SP key (deviation from plan: plan called for 5 separate providers/SP keys, but nested sub-models with one provider achieves the same organizational goal with far less consumer churn)
- [x] Run `build_runner` — generated 6 new `.freezed.dart`/`.g.dart` file pairs
- [x] Update all consumers (22 files updated via scripted string replacements + manual copyWith/constructor fixes):
  - `agent_runner.dart`, `aux_llm_client.dart`, `post_cleaner_service.dart`, `studio_ledger_service.dart`, `memory_dedup_service.dart`, `memory_studio_service.dart`, `studio_agent_executor.dart`, `studio_build_llm_client.dart`, `agentic_write_request_parser.dart`
  - `generation_pipeline.dart`, `stream_generation_service.dart`
  - `studio_settings_sheet.dart` (4 inline copyWith + `applyTo` method with 3 nested copyWith cases), `memory_generation_settings_sheet.dart` (1 copyWith), `memory_books_sheet.dart`, `agentic_operations_log_dialog.dart`
  - `memory_draft_generator.dart`, `memory_book_controller.dart`
  - `agent_operation_record.dart` (AgentOperationKind enum false positive revert)
- [x] Update all test consumers: `memory_budget_settings_test.dart` (3 constructor calls + JSON assertion), `studio_3config_resolution_test.dart` (2 constructor calls), `memory_cadence_test.dart` (already correct), `agent_operations_log_test.dart` (enum revert), `aux_retry_test.dart` (enum revert)
- [x] `flutter analyze` — 0 errors, 2 pre-existing warnings
- [x] `flutter test` — 1499/1499 passed
- **Key design decision:** Nested sub-models within a single `PipelineSettings` root + single provider + single SP key, instead of 5 separate providers/SP keys. Rationale: `aux*` fields are shared across cleaner/ledger/write-loop, and `aux_llm_client.dart` resolver methods take `PipelineSettings` as a parameter — splitting into 5 providers would require multi-provider reads in single functions and signature changes. The nested approach achieves the same god-object decomposition with mechanical access-path changes only.
- **Migration:** Old flat `pipelineSettings` SP JSON → each sub-model's `fromJson` picks up its own fields from the flat map (unknown keys ignored by freezed). Nested JSON persisted back on first load. Idempotent.

### Phase 3: Model routing — 4 slots + fail explicitly + idle timeout ✅ DONE
- [x] Create `StudioSlotResolver` (`lib/core/llm/studio_slot_resolver.dart`) — `resolve()` throws if empty/not found; `resolveFromList()` static helper for widget contexts
- [x] Remove `resolveConfig`, `resolveConfigForCleaner`, `resolveConfigForAudit`, `resolveConfigForConsolidation`, `resolveConfigForMemoryGeneration`, `resolveStudioSlotConfig` from `AuxLlmClient` (all 6 resolvers removed)
- [x] `PostCleanerService.runCleaner` — accept `AuxApiConfig` directly, remove `studioApiConfigId`/`useStudioApiConfigSlot` params
- [x] `PostCleanerService.runCharacterAudit` — same
- [x] `StudioLedgerService.run` — accept `AuxApiConfig` directly, remove `studioCleanerApiConfigId` param
- [x] `MemoryAgenticWriteService.runWriteLoop` — accept `AuxApiConfig` directly, gated by `studioConfig.enabled` in caller
- [x] `MemoryDedupService` — inline `_resolveMemoryBookConfig` (resolves `memoryBookApi.*` directly)
- [x] `MemoryDraftGenerator` — already resolved `memoryBookApi.*` inline (Phase 2)
- [x] Remove non-Studio cleaner branch from `generation_pipeline.dart` — cleaner gated by `studioConfig.enabled`
- [x] Write-loop gated by `studioConfig.enabled` in `_runAgenticWriteLoop` + `tracker_memory_recovery_service.dart`
- [x] `agentic_operations_log_dialog.dart` + `ledger_diagnostics_sheet.dart` — use `StudioSlotResolver.resolveFromList`
- [x] `studio_build_llm_client.dart` — simplified config resolution (removed `aux*` fallback, uses active chat config only)
- [x] Remove routing fields from sub-models: `postCleanerSource/Endpoint/ApiKey` from `CleanerSettings`; `auxSource/Model/Endpoint/ApiKey` + `consolidationSource/Model/Endpoint/ApiKey` from `MemoryPipelineSettings`
- [x] `build_runner` + `flutter analyze` (0 errors) + `flutter test` (1499/1499 passed)
- **Idle timeout for aux LLM calls** (bonus — mirrors `AgentStreamRunner` pattern):
  - New `IdleTimeoutGuard` helper (`lib/core/llm/idle_timeout_guard.dart`)
  - `AuxLlmClient._callOnce` + `_callStream`: idle timeout instead of hard total timeout
  - Timer cancelled on first chunk (text OR reasoning delta) — long generation never cut off
  - 60s default = first-byte timeout, not total generation timeout
  - Affects: cleaner, fact-checker, ledger, write-loop, dedup

### Phase 4: Reorder pipeline stages ✅ DONE
- [x] Split `_runPostTextSide` into `_runSyncAndNotification` (sync + notification only) + `_runImageTagsStage` (image tags only)
- [x] Remove `book == null` ext blocks branch from old `_runPostTextSide` — ext blocks now always launch from cleaner (Studio ON) or explicit `_launchExtensionsForSwipe` call (Studio OFF)
- [x] Create `_runPostGenTasks` shared method (replaces inline postGenFutures in both normal + regen paths)
- [x] Move `_runPostCleaner` before image tags — cleaner runs first, then image tags chained via `cleanerTask.then(...)`
- [x] Image tags re-read session from DB after cleaner completes → operates on canonical text (cleaned swipe)
- [x] Move `_runAgenticWriteLoop` after cleaner — chained via `cleanerTask.then(...)` (on canonical text)
- [x] Keep embed + auto-create drafts as parallel fire-and-forget (independent of cleaner)
- [x] Studio ON: cleaner → image tags + write-loop (chained); embed + drafts (parallel); ledger + ext blocks launched from inside cleaner
- [x] Studio OFF: image tags + ext blocks run immediately (no cleaner); embed + drafts (parallel)
- [x] Delete dead `ChatGenerationService.processExtensions` (no callers remain — `_launchExtensionsForSwipe` calls `extensionPostGenServiceProvider` directly)
- [x] Remove unused imports: `api_config.dart`, `api_list_provider.dart`
- [x] Update class docstring with new pipeline order
- [x] Update stale comments in `_executeAndApplyCleaner` (removed `_runPostTextSide` references)
- [x] `flutter analyze` (0 errors) + `flutter test` (1499/1499 passed)

### Phase 5: Decompose generation_pipeline.dart ✅ DONE
- [x] Create `StageContext` value class (`stages/stage_context.dart`)
- [x] `RegenResolver` — regen success/rollback/restoration (`stages/regen_resolver.dart`)
- [x] `SyncNotificationStage` — sync + notification (`stages/sync_notification_stage.dart`)
- [x] `ImageTagStage` — processImageTags (`stages/image_tag_stage.dart`)
- [x] `CleanerStage` — fact-checker + cleaner + beauty + ext blocks launch + ledger launch (`stages/cleaner_stage.dart`)
- [x] `ExtBlocksStage` — _launchExtensionsForSwipe (`stages/ext_blocks_stage.dart`)
- [x] `WriteLoopStage` — cadence + runWriteLoop + orphan cleanup (`stages/write_loop_stage.dart`)
- [x] `LedgerStage` — cadence + run + diag (`stages/ledger_stage.dart`)
- [x] `ChatEmbedStage` — embed chat messages (`stages/chat_embed_stage.dart`)
- [x] `MemoryDraftStage` — auto-create memory drafts (`stages/memory_draft_stage.dart`)
- [x] `PostGenCoordinator` — postGenFutures + wake-lock + notifications (`stages/post_gen_coordinator.dart`)
- [x] `GenerationPipeline` — thin sequencer calling stages (264 lines, down from 2437)
- [x] Move `rerunCleaner` → `CleanerStage.rerun()`
- [x] Extract `pipeline_utils.dart` — `extractRecentHistoryText`, `selectStudioLedgerTextAfterCleaner`, status mappers, `assembleLorebooksContent`
- [x] Remove dead `abortPostCleaner()` method (Stop button uses `cleanerCancelTokenProvider` directly)
- [x] Remove `@visibleForTesting` from `selectStudioLedgerTextAfterCleaner` (used in production `CleanerStage`)
- [x] Re-export `extractRecentHistoryText` + `selectStudioLedgerTextAfterCleaner` from `generation_pipeline.dart` for backward compat
- [x] Update `tracker_memory_recovery_service.dart` import
- [x] Update stale doc comments referencing `GenerationPipeline._runPostCleaner`
- [x] `flutter analyze` (0 errors, 0 new warnings) + `flutter test` (1499/1499 passed)

### Phase 6: UI updates
- [ ] `StudioSettingsSheet` — update reads/writes to new sub-model providers
- [ ] Add MemoryBook API config selector
- [ ] `MemoryBooks sheet` — dedup threshold from `MemoryPipelineSettings`
- [ ] Clean orphaned references (`studio_status_card.dart`, `block_edit_dialog.dart`, etc.)

## Testing

After each phase:
- `flutter analyze` — 0 errors
- `flutter test` — all pass
- Update affected tests
- New tests for `StudioSlotResolver` (fail-explicit)
- New tests for PipelineSettings migration

## Files to Delete
- `lib/features/chat/widgets/post_building_menu_dialog.dart`
- `lib/features/chat/widgets/studio_menu_dialog.dart`
- `lib/features/studio/screens/studio_settings_screen.dart`

## Key Files to Modify
- `lib/core/models/pipeline_settings.dart` → split into 5 models
- `lib/core/state/pipeline_settings_provider.dart` → migration + new providers
- `lib/core/llm/aux_llm_client.dart` → remove 4 resolvers, keep transport
- `lib/core/llm/post_cleaner_service.dart` → remove Studio routing params
- `lib/core/llm/studio_ledger_service.dart` → use StudioSlotResolver
- `lib/core/llm/memory_agentic_write_service.dart` → use StudioSlotResolver, Studio-only
- `lib/features/chat/services/generation_pipeline.dart` → decompose into stages
- `lib/features/chat/widgets/studio_settings_sheet.dart` → update to new providers
- `lib/core/llm/agent_runner.dart` → read from new sub-models
- `lib/features/chat/memory_draft_generator.dart` → MemoryBookApiSettings
- `lib/core/llm/memory_dedup_service.dart` → MemoryBookApiSettings

## DB Notes
- No DB schema changes (PipelineSettings is SharedPreferences)
- Migration is SP-only, idempotent
- User DB backups unaffected
