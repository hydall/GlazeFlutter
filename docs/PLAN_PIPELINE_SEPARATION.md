# PLAN: Pipeline Settings Separation from Memory Books

Status: **SHIPPED** (commit `9579d7e`). All items below are done unless
marked otherwise.

Post-ship additions:
- DB schema v49: Studio Build/Run model overrides (`buildModelOverride`,
  `runModelOverride`) added to `studio_config_rows` (commit `fdef2d5`).
- Memory mode ↔ sidecar lock: Deep/Agentic modes now force-lock the sidecar
  toggle ON in Post-Building, with a status hint in Memory Books UI
  (commit `9e7bb99`).
- Post-cleaner current-API model dropdown + Studio model dropdowns + i18n
  (commit `fdef2d5`).
- Consolidation: service + repo + table + UI exist, but
  `consolidateSession` is **not yet wired** into the post-turn pipeline and
  summaries are **not yet injected**. UI shows a "not yet functional" banner.
  See §7 below.

---

## 1. Why

`MemoryBookSettings` currently holds 60+ fields spanning three unrelated
concerns:

1. **Memory retrieval** — budget, packing, cadence, consolidation, vector
   search, diversity, recency, importance, injection target. These belong to
   the memory book.
2. **Memory generation LLM** — `generationSource/Model/Endpoint/ApiKey/...`.
   These configure the LLM that writes memory entries. Borderline — related to
   memory but is an LLM config, not a retrieval param.
3. **Post-generation pipeline** — sidecar LLM (write-loop + reranker),
   classifier, POST-cleaner, agentic write-loop. These have nothing to do with
   memory retrieval. They are generation-pipeline settings that happen to be
   stored alongside memory because the memory book was the first place they
   were wired.

### Problems this causes

- **Misleading ownership.** A user opening "Memory Books" to configure the
  POST-cleaner model is confused. The cleaner is not a memory feature.
- **Coupling.** Changing memory retrieval defaults risks breaking pipeline
  config and vice versa. A bug in the cleaner migration path can corrupt memory
  settings.
- **UI scattering.** Pipeline settings are spread across `studio_menu_dialog`
  (write-loop, sidecar model), the new Post-Building menu (cleaner), and
  memory settings (classifier, consolidation). No single source of truth.
- **Per-session vs global confusion.** `MemoryBookSettings` is per-session
  (stored in `memory_book_rows.settings_json`). `MemoryGlobalSettings`
  (SharedPreferences) mirrors a subset. The merge logic in
  `memory_book_repo.dart` is fragile and grows with every new field.
- **Migration surface.** Every new pipeline field requires updating
  `MemoryGlobalSettings`, `MemoryBookSettings`, the merge in `memory_book_repo`,
  the freezed/json serialization, and sometimes a DB migration. This is
  excessive for a single toggle.

---

## 2. What

Split into two independent settings models:

### `MemoryBookSettings` (retrieval only)

Fields that describe how memory is retrieved, scored, packed, and injected:

```
enabled, memoryMode, autoCreateEnabled, autoGenerateEnabled,
maxInjectedEntries, memoryExcerpting*, chunkFirst*,
maxInjectionBudgetPercent, maxInjectedTokens, memoryBudgetPreset,
autoCreateInterval, autoCreateLagMessages, useDelayedAutomation,
injectionTarget, batchSize, vectorSearchEnabled, keyMatchMode,
diversityAware, diversityPenalty, recencyBoost, recencyHalfLifeDays,
importanceBoost, importanceWeight, sourceWindowExclusion,
factualContinuityGuardEnabled, queryIncludeAssistant, queryRecentTurns,
queryMaxChars, cadenceInterval, consolidationEnabled,
consolidationThreshold, promptPreset
```

### `PipelineSettings` (new — generation pipeline)

Fields that configure LLM sidecars and post-generation passes:

```
// Memory generation LLM
generationSource, generationModel, generationEndpoint, generationApiKey,
generationTemperature, generationMaxTokens,

// Classifier LLM
classifierEnabled, classifierSource, classifierModel, classifierEndpoint,
classifierApiKey, classifierTimeoutMs,

// Sidecar LLM (write-loop + reranker)
sidecarEnabled, sidecarSource, sidecarModel, sidecarEndpoint, sidecarApiKey,
sidecarTimeoutMs,

// Agentic write-loop
agenticWriteEnabled,

// POST-cleaner
postCleanerEnabled, postCleanerTemperature, postCleanerMaxTokens,
postCleanerSource, postCleanerModel, postCleanerEndpoint, postCleanerApiKey,
postCleanerTimeoutMs, postCleanerContinuityEnabled,
postCleanerCharacterCheckEnabled, postCleanerHistoryMessages,
postCleanerMaxCharsPerMessage,

// Consolidation LLM
consolidationSource, consolidationModel, consolidationEndpoint,
consolidationApiKey, consolidationTimeoutMs,
```

### `MemoryGlobalSettings` → split accordingly

- `MemoryGlobalSettings` — retrieval-only globals (SharedPreferences).
- `PipelineGlobalSettings` — pipeline globals (SharedPreferences).

---

## 3. How

### 3.1 Storage

`PipelineSettings` is per-session (like `MemoryBookSettings`), stored in a new
DB table `pipeline_settings_rows`:

| Column | Type | Description |
|--------|------|-------------|
| `session_id` | TEXT PK | FK to `chat_sessions` |
| `settings_json` | TEXT | Serialized `PipelineSettings` |
| `updated_at` | INTEGER | Timestamp |

On branch/session copy, `pipeline_settings_rows` is copied alongside
`memory_book_rows` and `chat_summaries`.

### 3.2 Migration

One-time DB migration (new schema version):

1. Create `pipeline_settings_rows` table.
2. For each `memory_book_rows` row, extract pipeline fields from
   `settings_json` and write them to `pipeline_settings_rows.settings_json`.
3. Remove pipeline fields from `memory_book_rows.settings_json` (leave only
   retrieval fields). Old JSON entries for removed fields are harmless —
   `fromJson` ignores unknown keys.
4. `MemoryBookSettings.fromJson` stops reading pipeline fields (they default
   via freezed if present, but are never used).

### 3.3 Repository

New `PipelineSettingsRepo`:
- `getBySessionId(sessionId)` → `PipelineSettings?`
- `ensureForSession(sessionId)` → `PipelineSettings` (creates with defaults if
  absent)
- `updateSettings(sessionId, settings)` → void
- `copyToSession(srcSessionId, dstSessionId)` → void (for branch copy)
- `deleteBySession(sessionId)` → void

### 3.4 Provider

New `pipelineSettingsProvider` (Riverpod):
- `FutureProvider<PipelineSettings>` per session.
- Invalidated when `PipelineSettingsRepo.updateSettings` is called.

### 3.5 Callers

Every file that reads `settings.sidecarModel`, `settings.postCleanerEnabled`,
`settings.classifierEnabled`, etc. switches to `pipelineSettings.*`.

Key files:
- `generation_pipeline.dart` — reads `pipelineSettings.postCleanerEnabled`,
  `postCleanerHistoryMessages`, etc.
- `post_cleaner_service.dart` — receives `PipelineSettings` instead of
  `MemoryBookSettings`.
- `sidecar_llm_client.dart` — `resolveConfig` takes `PipelineSettings`.
- `memory_agentic_service.dart`, `memory_agentic_write_service.dart` — read
  sidecar config from `PipelineSettings`.
- `memory_injection_service.dart` — reads classifier config from
  `PipelineSettings`.
- `studio_menu_dialog.dart` — write-loop + sidecar model from
  `PipelineSettings`.
- `post_building_menu_dialog.dart` — all cleaner settings from
  `PipelineSettings`.
- `memory_book_repo.dart` — merge logic simplified: only retrieval fields.

### 3.6 UI

- **Post-Building menu** reads/writes `PipelineSettings` (cleaner section).
- **Studio menu** reads/writes `PipelineSettings` (write-loop + sidecar model).
- **Memory Books sheet** reads/writes `MemoryBookSettings` (retrieval only).
  Pipeline settings disappear from the memory books UI entirely.

---

## 4. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Migration corrupts existing settings | Migration is additive: extract fields to new table, leave old JSON intact. Unknown keys in old `MemoryBookSettings.fromJson` are ignored. |
| Callers break during refactor | Do it in a single feature branch with `flutter analyze` + full test suite. No incremental merge — ship when complete. |
| Session copy misses pipeline settings | `copyToSession` in `PipelineSettingsRepo` mirrors `memory_book_repo` copy logic. Test with characterization tests. |
| Global settings merge becomes complex | Keep the merge simple: `PipelineGlobalSettings` → `PipelineSettings` for per-session overrides, same pattern as current global → session merge. |

---

## 5. Rollout

1. Create `PipelineSettings` model + freezed.
2. Create `pipeline_settings_rows` table + migration.
3. Create `PipelineSettingsRepo` + provider.
4. Migrate existing data (extract from `memory_book_rows.settings_json`).
5. Update all callers to read from `PipelineSettings`.
6. Update UI (Post-Building, Studio, Memory Books).
7. Clean up `MemoryBookSettings` (remove pipeline fields).
8. Clean up `MemoryGlobalSettings` (remove pipeline fields).
9. `flutter analyze` + `flutter test`.
10. Manual test: cleaner, write-loop, classifier, consolidation all work.

---

## 6. Success Criteria

- `MemoryBookSettings` contains only retrieval fields.
- `PipelineSettings` contains all pipeline LLM config.
- No file reads `settings.sidecarModel` or `settings.postCleanerEnabled` from
  `MemoryBookSettings`.
- Memory Books UI has no pipeline controls.
- Post-Building UI and Studio UI read from `PipelineSettings`.
- Existing user settings survive the migration (no data loss).
- `flutter analyze` passes.
- All existing tests pass (with updated mocks/fixtures).

---

## 7. Completion Status (post-ship audit)

| Item | Status |
|------|--------|
| `PipelineSettings` model + freezed | Done |
| `pipeline_settings_rows` table + migration (v48) | Done |
| `PipelineSettingsRepo` + provider | Done |
| Migrate existing data (extract from `memory_book_rows.settings_json`) | Done |
| Update all callers to read from `PipelineSettings` (15 lib files) | Done |
| Update UI (Post-Building, Studio, Memory Books) | Done |
| Clean up `MemoryBookSettings` (remove pipeline fields) | Done |
| Clean up `MemoryGlobalSettings` (remove pipeline fields) | Done |
| `flutter analyze` + `flutter test` | 0 errors, 1334/1334 pass |
| Studio Build/Run model overrides (schema v49) | Done |
| Memory mode ↔ sidecar lock (Deep/Agentic) | Done |
| Post-cleaner current-API model dropdown | Done |
| i18n for all Post-Building strings (en + ru) | Done |

### Consolidation — not yet functional

The consolidation service (`memory_consolidation_service.dart`), repo
(`memory_consolidation_repo.dart`), DB table (`memory_consolidation_rows`),
PipelineSettings fields (`consolidationEnabled/Threshold/Source/Model/Endpoint/
ApiKey/TimeoutMs`), and UI section (Post-Building menu) all exist and are
wired into the settings model. However:

- `consolidateSession()` is **never called** — no file invokes it. The
  provider (`memoryConsolidationServiceProvider`) is defined but unused.
- Consolidation summaries (tier 1 = scene, tier 2 = arc) are saved to
  `memory_consolidation_rows` when the service runs, but the service never
  runs because nothing triggers it.
- Summaries are **not injected** — `MemoryInjectionService` reads only
  `book.entries` (status='active'), not `memory_consolidation_rows`.

The UI section in Post-Building shows a "Not yet functional" banner to set
user expectations. The settings are preserved so the feature can be completed
in a future task without a DB migration.

**To ship consolidation, two things are needed:**
1. Call `consolidateSession()` from `MemoryPostTurnService.runPostTurn()`
   (or `GenerationPipeline`) when `consolidationEnabled` and threshold met.
2. Inject tier 1/2 summaries into the generation prompt (either as a new
   `{{consolidation}}` macro or by adding them to `MemoryInjectionService`
   selection alongside `book.entries`).
