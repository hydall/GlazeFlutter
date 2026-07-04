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

### Phase 3: Model routing — 4 slots + fail explicitly
- [ ] Create `StudioSlotResolver` — `resolveSlot()` throws if empty/not found
- [ ] Remove `resolveConfigForCleaner`, `resolveConfigForAudit`, `resolveConfigForConsolidation`, `resolveConfigForMemoryGeneration` from `AuxLlmClient`
- [ ] `PostCleanerService.runCleaner` — accept `AuxApiConfig` directly, remove `studioApiConfigId`/`useStudioApiConfigSlot` params
- [ ] `PostCleanerService.runCharacterAudit` — same
- [ ] `StudioLedgerService` — resolve via `StudioSlotResolver` (cleaner slot)
- [ ] `MemoryAgenticWriteService` — resolve via `StudioSlotResolver` (cleaner slot), gate by `studioConfig.enabled`
- [ ] `MemoryDraftGenerator` — resolve via `MemoryBookApiSettings`
- [ ] `MemoryDedupService` — resolve via `MemoryBookApiSettings`
- [ ] Remove non-Studio cleaner branch from `generation_pipeline.dart`
- [ ] Remove unconditional `StudioConfigRepo` read for non-Studio sessions

### Phase 4: Reorder pipeline stages
- [ ] Move `_runPostCleaner` before image tags and ext blocks
- [ ] Extract image tags from `_runPostTextSide` into separate stage after cleaner
- [ ] Ext blocks always after cleaner (remove `book == null` condition in PostTextSide)
- [ ] Move `_runAgenticWriteLoop` after cleaner
- [ ] Keep embed + auto-create drafts as parallel fire-and-forget

### Phase 5: Decompose generation_pipeline.dart
- [ ] Create `PipelineStage` abstract interface + `StageContext`
- [ ] `RegenResolver` — regen success/rollback/restoration
- [ ] `PostTextHandler` — sync + notification
- [ ] `ImageTagStage` — processImageTags
- [ ] `CleanerStage` — fact-checker + cleaner + beauty + ext blocks launch
- [ ] `ExtBlocksStage` — _launchExtensionsForSwipe
- [ ] `WriteLoopStage` — cadence + runWriteLoop + orphan cleanup (Studio-only)
- [ ] `LedgerStage` — cadence + run + diag (Studio-only)
- [ ] `ChatEmbedStage` — embed chat messages
- [ ] `MemoryDraftStage` — auto-create memory drafts
- [ ] `PostGenCoordinator` — postGenFutures + wake-lock + notifications
- [ ] `GenerationPipeline` — thin sequencer calling stages
- [ ] Move `rerunCleaner` → `CleanerStage.rerun()`

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
