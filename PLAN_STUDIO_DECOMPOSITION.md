# Plan — Studio Decomposition & Deduplication

**Branch:** `refactor/studio-decomposition` (from `master` @ `3c16d41d`)
**Goal:** Decompose all Studio service files >500 lines, eliminate cross-cutting duplication, enforce constructor injection.
**Rule:** Each phase = one commit. `flutter analyze` 0 errors + `flutter test` green after each phase.

---

## Inventory — Files to address

### Tier 1 — Core LLM services (>500 lines)
| File | Lines | Role |
|------|-------|------|
| `prompt_builder.dart` | 1529 | 8 data classes + 11 top-level functions, no class, god-file |
| `prompt_payload_builder.dart` | 1005 | Input collection + payload build + arc state + ledger trackers |
| `post_cleaner_service.dart` | 924 | Cleaner prompt + audit prompt + apply + format recent |
| `memory_studio_service.dart` | 737 | Tracker cycle + activation + phase split |
| `memory_injection_service.dart` | 692 | Candidates + injection + vector search + catalog matches |
| `macro_engine.dart` | 690 | MacroContext + MacroResult + VariableMacroResult + expansion |
| `studio_message_builder.dart` | 579 | Agent messages + batch messages + history + block expansion + brief macros |
| `memory_excerpt_selector.dart` | 564 | Full entries + excerpts + chunk-first-global + chunking |
| `studio_ledger_service.dart` | 511 | Run + apply ops + durable facts + visible ledger |
| `agent_runner.dart` | 546 | Agent run + config resolve + reasoning strip |
| `memory_selector.dart` | 509 | Candidate selection + scoring + diversity |

### Tier 2 — Pipeline stages (>250 lines)
| File | Lines | Role |
|------|-------|------|
| `stream_generation_service.dart` | 962 | Stream + Studio intercept + memory agent ops + beauty state |
| `cleaner_stage.dart` | 912 | Cleaner run + execute+apply + fact checker + rerun |
| `ledger_stage.dart` | 304 | Ledger launch + result handling |
| `write_loop_stage.dart` | 268 | Write-loop cadence + execution |
| `generation_pipeline.dart` | 264 | Thin orchestrator (already done Phase 5) |

### Tier 3 — UI files (>800 lines, Studio-related)
| File | Lines | Role |
|------|-------|------|
| `memory_books_sheet.dart` | 1385 | 4 tabs + overview + search + actions + draft cards |
| `memory_generation_settings_sheet.dart` | 1141 | Memory generation settings |
| `studio_settings_sheet.dart` | 1124 | Studio config + slots + preset selector |
| `agentic_operations_log_dialog.dart` | 914 | Operations tab + last-turn tab + ledger rerun |

### Cross-cutting duplication
| Pattern | Scope | Fix |
|---------|-------|-----|
| `final Ref _ref` in 14 services | `agent_runner`, `aux_llm_client`, `memory_agentic_write_service`, `memory_dedup_service`, `memory_studio_service`, `post_cleaner_service`, `prompt_inputs_collector`, `prompt_payload_builder`, `studio_agent_executor`, `studio_batch_coordinator`, `studio_build_llm_client`, `studio_ledger_service`, `studio_prompt_resolver`, `studio_slot_resolver` | Constructor injection — pass deps, not Ref |
| 30+ Result/Outcome classes | All `core/llm/` | Unify into common `AuxResult<T>` pattern where shapes overlap |
| Prompt building in each service | `post_cleaner_service`, `memory_dedup_service`, `studio_ledger_service` | Extract to dedicated prompt builder classes |
| `_formatRecentMessages` / `_formatMessageRange` | `post_cleaner_service`, `memory_diagnostics` | Extract to shared `MessageRangeFormatter` |

---

## Phases

### Phase 1 — Extract data classes from `prompt_builder.dart`

**Problem:** `prompt_builder.dart` (1529 lines) contains 8 classes + 11 top-level functions in one file. No `PromptBuilder` class — just free functions.

**Action:**
1. Extract data classes to separate files:
   - `RuntimePromptBlock` → `lib/core/llm/prompt/runtime_prompt_block.dart`
   - `RecalledMessageChunk` → `lib/core/llm/prompt/recalled_message_chunk.dart`
   - `PromptPayload` → `lib/core/llm/prompt/prompt_payload.dart`
   - `PromptResult` → `lib/core/llm/prompt/prompt_result.dart`
   - `_ResolvedDepthBlock` / `_ResolvedRelativeBlock` → `lib/core/llm/prompt/resolved_block.dart` (make public)
   - `_DeferredMemoryResult` → `lib/core/llm/prompt/deferred_memory_result.dart` (make public)
   - `_RebuiltMemoryContent` → `lib/core/llm/prompt/rebuilt_memory_content.dart` (make public)
2. Keep `prompt_builder.dart` as re-export barrel for backward compat
3. No logic changes — pure file split

**Result:** `prompt_builder.dart` shrinks from 1529 to ~900 lines (functions only). Data classes in focused files.

---

### Phase 2 — Decompose `prompt_builder.dart` functions

**Problem:** `buildPrompt()` (line 307) and `_assembleMessages()` (line 746) are giant functions doing block resolution + lore injection + memory injection + regex application + macro expansion.

**Action:**
1. Extract specialists (following CODE_STYLE.md "Giant function" pattern):
   - `PromptBlockResolver` — depth/relative block resolution (`_ResolvedDepthBlock` / `_ResolvedRelativeBlock` logic) — **merge with existing `prompt_block_resolver.dart`**
   - `LorebookInjector` — `_injectLoreBefore` / `_injectLoreAfter` / `_calculateLorebookReserve`
   - `MemoryBlockInjector` — `_injectMemoryBlock` / `_injectRecalledMessagesBlock` / `_injectStudioSessionStateBlock` / `_replaceDeferredMemoryPlaceholders` / `_finalizeMemoryCoverage`
   - `FactualContinuityGuard` — `_shouldInjectFactualContinuityGuard`
2. `buildPrompt()` becomes thin orchestrator: resolve blocks → inject lore → inject memory → apply regex → assemble
3. `_assembleMessages()` delegates to specialists

**Result:** `prompt_builder.dart` ~300 lines (thin orchestrator + re-exports). Specialists 100-200 lines each.

---

### Phase 3 — Decompose `prompt_payload_builder.dart` (1005 lines)

**Problem:** `PromptPayloadBuilder` does input collection + payload building + vector search + ledger tracker loading + arc state computation.

**Action:**
1. Extract:
   - `ArcStateBuilder` — `_buildArcState` / `_loadEffectiveLedgerTrackers` / arc field filtering (lines 579-730)
   - `LedgerTrackerLoader` — `_loadEffectiveLedgerTrackers` (lines 579-618)
   - Vector search stays in `PromptPayloadBuilder` or moves to existing `lorebook_vector_search.dart`
2. `PromptPayloadBuilder.buildFromSession` / `buildFromPreFetched` become thin orchestrators
3. Constructor injection — remove `Ref`, pass repos/callbacks

**Result:** `prompt_payload_builder.dart` ~400 lines. Specialists 100-200 lines.

---

### Phase 4 — Decompose `post_cleaner_service.dart` (924) + `cleaner_stage.dart` (912)

**Problem:** `PostCleanerService` mixes prompt building + LLM call + text comparison + audit + apply logic. `CleanerStage` mixes cleaner execution + fact-checker + beauty state + pre-created swipe management.

**Action:**
4a. `post_cleaner_service.dart`:
1. Extract:
   - `CleanerPromptBuilder` — `buildCleanerPrompt` (static, 280 lines!) → dedicated class
   - `AuditPromptBuilder` — `buildAuditPrompt` (static, 130 lines) → dedicated class
   - `CleanerTextGuard` — `textRewriteDropsProtectedMarkup` / `lumiaoocDropped` / `_hasHtmlOrXmlTag` / `_hasFencedBlock` → static helper class
   - `MessageRangeFormatter` — `_formatRecentMessages` → shared utility (also used by `memory_diagnostics`)
2. `PostCleanerService` becomes thin: `runCleaner` → `runCharacterAudit` → `applyCleanedText`

4b. `cleaner_stage.dart`:
1. Extract:
   - `CleanerSwipeManager` — pre-created swipe lifecycle (create/fill/remove/revert)
   - `FactCheckerRunner` — `_recordFactCheckerOperation` + fact-checker LLM call
   - `BeautyStateHandler` — beauty marker detection + state JSON parsing
2. `CleanerStage.run` / `rerun` become thin orchestrators

**Result:** `post_cleaner_service.dart` ~300 lines. `cleaner_stage.dart` ~350 lines. Specialists 100-200 lines.

---

### Phase 5 — Decompose `memory_studio_service.dart` (737) + `studio_message_builder.dart` (579)

**Problem:** `MemoryStudioService` mixes tracker cycle orchestration + activation keywords + phase splitting + batch coordination. `StudioMessageBuilder` mixes message building + history limiting + block expansion + brief macro rendering.

**Action:**
5a. `memory_studio_service.dart`:
1. Extract:
   - `StudioActivationGate` — `matchesActivationKeywords` (already exists `studio_activation_gate.dart` — **merge into it**)
   - `StudioPhaseSplitter` — `splitAgentsByPhase` / `_firstFailedTrackerResult` / `_trackerResultsToBriefs` / `_trackerFailureMessage`
2. `runTrackerCycle` / `runTrackersOnly` become thin orchestrators
3. Constructor injection — remove `Ref`

5b. `studio_message_builder.dart`:
1. Extract:
   - `StudioBlockExpander` — `_expandStudioBlockContent` / `_isRuntimeComputedBlock` / `_blockAppliesToAgent` / `_trackerInstructionAppliesToAgent` (merge with existing `studio_block_expander.dart`)
   - `StudioBriefMacroRenderer` — `_replaceStudioBriefMacros` / `_hasStudioBriefMacro` / `_finalBriefsForMacros` / `_briefsForController` / `_renderBriefs`
   - `StudioHistoryLimiter` — `limitFinalHistory` / `limitTrackerHistory` / `truncateAgentText` / `stripHtmlTags`
2. `StudioMessageBuilder.buildAgentMessages` / `buildSharedBatchMessages` become thin

**Result:** `memory_studio_service.dart` ~350 lines. `studio_message_builder.dart` ~200 lines.

---

### Phase 6 — Decompose `memory_injection_service.dart` (692) + `memory_excerpt_selector.dart` (564)

**Problem:** `MemoryInjectionService` mixes candidate building + vector search + catalog matching + keyword matching + injection assembly. `MemoryExcerptSelector` is 564 lines of static methods doing chunking + sentence splitting + scoring.

**Action:**
6a. `memory_injection_service.dart`:
1. Extract:
   - `MemoryVectorSearcher` — `_vectorSearchMemory` / `_decodeMemoryChunkTexts` / `_legacyVectorQuery` (lines 380-620)
   - `MemoryCatalogMatcher` — `_catalogMatches` / `_selectorScanText` / `_keywordMatches` / `_matchedCatalogTerms` / `_catalogScore` (lines 550-690)
2. `buildCandidates` / `buildCandidatesWithDiagnostics` / `buildInjection` become thin
3. Already uses constructor injection — verify no `Ref`

6b. `memory_excerpt_selector.dart`:
1. Extract:
   - `MemoryChunker` — `_chunk` / `_sentences` / `countChunks` (text chunking logic)
   - `ExcerptScorer` — `_vectorChunkBoost` / `_entryChunkPrior` / `_termsFor` (scoring helpers)
2. `select` / `selectChunkFirstGlobal` / `fullEntries` stay in `MemoryExcerptSelector` but delegate

**Result:** `memory_injection_service.dart` ~300 lines. `memory_excerpt_selector.dart` ~250 lines.

---

### Phase 7 — Decompose `studio_ledger_service.dart` (511) + `agent_runner.dart` (546)

**Problem:** `StudioLedgerService` mixes run orchestration + op application + durable fact writing + visible ledger storage. `AgentRunner` mixes agent execution + config resolution + reasoning stripping.

**Action:**
7a. `studio_ledger_service.dart`:
1. Extract:
   - `LedgerOpApplier` — `_applyOp` / `_containsValue` (op application logic)
   - `DurableFactWriter` — `_writeDurableFacts` / `_hashFact` (durable fact logic)
   - `VisibleLedgerStore` — `_storeVisibleLedger` / `_buildLedgerProvenance` (visible ledger logic)
2. `StudioLedgerService.run` becomes thin orchestrator
3. Constructor injection — remove `Ref`

7b. `agent_runner.dart`:
1. Extract:
   - `AgentConfigResolver` — `resolveAgentConfig` / `_readRunApiConfigId` (config resolution, lines 205-290)
   - `PromptLevelReasoningStripper` — `stripPromptLevelReasoning` (static, merge with existing `reasoning_stripper.dart`)
2. `AgentRunner.runAgent` / `_runAgentInner` become thin
3. Constructor injection — remove `Ref`

**Result:** `studio_ledger_service.dart` ~200 lines. `agent_runner.dart` ~250 lines.

---

### Phase 8 — Decompose `stream_generation_service.dart` (962)

**Problem:** `StreamGenerationService` mixes streaming + Studio intercept + memory agent operation recording + beauty state + helper methods.

**Action:**
1. Extract:
   - `StudioStreamInterceptor` — Studio intercept logic + `computeStudioFinalVisibleMessageIds` / `_maxStudioTrackerContextSize` / `_payloadWithSourceWindow` / `_studioOutputsToJson` / `_studioFinalState` / `_studioStatusToOp`
   - `MemoryAgentRecorder` — `_recordMemoryAgentOperation` / `_appendOperation` / `_recordStudioTrackerOperation` / `_memoryAgentStatusToOp`
   - `BeautyStateDetector` — `_BeautyStateResult` + beauty state parsing (merge with `beauty_state_parser.dart`)
2. `StreamGenerationService.run` becomes thin orchestrator
3. Keep `_lastRequestsBySession` / `_rememberRequest` in service (static cache)

**Result:** `stream_generation_service.dart` ~400 lines. Specialists 150-250 lines.

---

### Phase 9 — Constructor injection sweep

**Problem:** 14 services still hold `final Ref _ref` and do `ref.read(...)` inside methods — violates "Constructor injection only" from CODE_STYLE.md.

**Action:**
1. For each service with `final Ref _ref`:
   - Identify all `ref.read(...)` calls
   - Replace with constructor-injected callbacks/repos
   - Wire from provider layer
2. Services to fix (in priority order):
   - `prompt_payload_builder.dart` (done in Phase 3)
   - `post_cleaner_service.dart` (done in Phase 4)
   - `memory_studio_service.dart` (done in Phase 5)
   - `studio_ledger_service.dart` (done in Phase 7)
   - `agent_runner.dart` (done in Phase 7)
   - `studio_agent_executor.dart` — pass `AuxLlmClient` + config
   - `studio_batch_coordinator.dart` — pass `AuxLlmClient` + config
   - `studio_build_llm_client.dart` — pass config directly
   - `studio_prompt_resolver.dart` — pass preset/character
   - `studio_slot_resolver.dart` — pass `ApiConfigRepo` callback
   - `memory_agentic_write_service.dart` — pass repos + `AuxLlmClient`
   - `memory_dedup_service.dart` — pass `AuxLlmClient`
   - `prompt_inputs_collector.dart` — pass repos
   - `aux_llm_client.dart` — keep `Ref` (it's the LLM transport, needs `ref.read` for config)

**Note:** `aux_llm_client.dart` is the boundary exception — it reads API config from `ref` and makes HTTP calls. This is the provider-layer adapter; `Ref` is acceptable here.

**Result:** All services use constructor injection. Only `AuxLlmClient` retains `Ref`.

---

### Phase 10 — UI decomposition

**Problem:** 4 Studio UI files >900 lines each, mixing business logic with widget code.

**Action:**
10a. `memory_books_sheet.dart` (1385):
1. Extract business logic to provider/service:
   - `_scanChat` / `_startGeneration` / `_stopGeneration` / `_rebuildVector` → `MemoryBookController` (already exists — verify and extend)
   - `_sourceKey` → model class
2. Extract sub-widgets to separate files if >200 lines:
   - `_buildApprovedTab` / `_buildScanDraftsTab` / `_buildAgentMemoriesTab` / `_buildStudioMemoriesTab` → `memory_books_tabs/` directory
3. Keep `MemoryBooksSheet` as shell with tab switching

10b. `memory_generation_settings_sheet.dart` (1141):
1. Extract settings sections to sub-widgets if independent
2. Move any business logic to provider

10c. `studio_settings_sheet.dart` (1124):
1. Extract:
   - `_buildModelSlot` / `_slotApiConfig` / `_modelCacheKey` / `_clearSlotModelCache` / `_apiConfigLabel` / `_openApiConfigSelector` → `studio_slot_settings_widget.dart`
   - `_buildPresetSelector` / `_openStudioPresetSelector` / `_createStudioPreset` → `studio_preset_selector_widget.dart`
2. Keep `StudioSettingsSheet` as shell

10d. `agentic_operations_log_dialog.dart` (914):
1. Extract:
   - `_OperationsTab` → `agentic_operations_tab.dart`
   - `_LastTurnTab` → `agentic_last_turn_tab.dart`
2. Keep `AgenticOperationsLogDialog` as shell with tab switching

**Result:** Each UI file <500 lines. Business logic in providers/services. Sub-widgets in focused files.

---

### Phase 11 — Shared utilities & final cleanup

**Action:**
1. Create `lib/core/llm/shared/message_range_formatter.dart` — unified `_formatMessageRange` / `_formatRecentMessages` (used by `post_cleaner_service`, `memory_diagnostics`)
2. Audit all Result classes — unify shapes where possible (common `status` / `error` / `elapsedMs` / `attempts` fields → consider a shared mixin or base)
3. Remove any dead code discovered during decomposition
4. Update `docs/ARCHITECTURE.md` with new file structure
5. Update `docs/CODE_STYLE.md` refactor patterns table with new examples
6. Final `flutter analyze` + `flutter test` + `dart run build_runner build`

---

## Execution order & dependencies

```
Phase 1 (data class extract) ──→ Phase 2 (function decompose)
                                      │
Phase 3 (payload builder) ────────────┤
                                      │
Phase 4 (cleaner + stage) ────────────┤
                                      │
Phase 5 (studio + msg builder) ───────┤
                                      │
Phase 6 (memory injection) ───────────┤
                                      │
Phase 7 (ledger + agent runner) ──────┤
                                      │
Phase 8 (stream gen) ─────────────────┤
                                      │
Phase 9 (constructor injection) ──────┤
                                      │
Phase 10 (UI) ────────────────────────┤
                                      │
Phase 11 (cleanup) ───────────────────┘
```

Phases 1-8 are independent (can be done in any order, but 1→2 must be sequential).
Phase 9 depends on 3-7 (those phases already fix injection for some services).
Phase 10 depends on 9 (UI calls services with new signatures).
Phase 11 is final.

**Recommended commit cadence:** One commit per phase. If a phase is large (4, 5, 8), split into sub-commits (e.g., `4a`, `4b`).

---

## Verification checklist (after each phase)

- [ ] `flutter analyze` — 0 errors
- [ ] `flutter test` — all pass
- [ ] No new warnings introduced
- [ ] `dart run build_runner build` — clean (if models touched)
- [ ] No `Ref` added to services that didn't have it before (Phase 9 fixes existing ones)
- [ ] Re-exports maintain backward compat (no import breakage)
