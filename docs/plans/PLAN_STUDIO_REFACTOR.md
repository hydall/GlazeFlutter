# Plan: Studio / Agent Subsystem Decomposition

> **Status:** ✅ CORE DONE — shared specialists (§1), decomposition (§3),
> TrackerBatcher (§4), MemoryStudioService pure/leaf specialists + brief cache
> (§2, 6/9), StudioMenuController (§5), MemorySettingsMapper +
> MemoryDraftGenerationController (§6). Deeply-coupled stateful clusters
> deferred as follow-up (see §2/§7 notes). §6 complete.
> **Goal:** Break up the studio/agent god objects into thin orchestrators + injected
> specialists per `docs/CODE_STYLE.md` (one class = one job, ~250 lines). No behavior
> change — pure structural refactor, gated by the existing test suite.
> **Branch:** Work directly on the current `plan/continuity-post-cleaner` branch — **no
> separate branch**. This refactor is one continuous body of work on the studio /
> agent / post-cleaner subsystem and lands as a **series of small commits** on that
> branch (one specialist extraction per commit, per §9).

---

## 0. Why

Several studio/agent files are 2–9× over the 250-line single-responsibility
guideline and mix multiple concerns. The two worst are chat-time
(`MemoryStudioService`) and build-time (`StudioDecompositionService`). The
subsystem is otherwise architecturally sound — the build-time vs chat-time split
and the `AgentRunner` (transport) vs prompt-builder boundary are already clean —
so this is a within-file decomposition, not a re-architecture.

### Current size map (logic files, excluding `.freezed.dart`)

| File | Lines | Verdict |
|---|---|---|
| `lib/core/llm/memory_studio_service.dart` | ~2359 | ⚠️ god object (chat-time orchestrator) |
| `lib/core/llm/studio_decomposition_service.dart` | ~1203 | ⚠️ god object (build-time) |
| `lib/features/chat/widgets/studio_menu_dialog.dart` | ~873 | ⚠️ UI with embedded business logic |
| `lib/core/llm/tracker_batcher.dart` | ~611 | ⚠️ 6 concerns in one class |
| `lib/features/memory/controllers/memory_book_controller.dart` | ~619 | ⚠️ 3 jobs |
| `lib/core/llm/agent_runner.dart` | ~500 | ⚠️ borderline (4 classes/file + dup) |
| `lib/core/llm/memory_agentic_write_service.dart` | ~438 | slightly over |
| `lib/core/llm/memory_agentic_tools.dart` | ~370 | grab-bag (3 themes) |
| `lib/core/llm/studio_request_preset.dart` | ~377 | ✅ data-driven, OK |
| `lib/core/llm/studio_block_router.dart` | ~231 | ✅ exemplary (the target shape) |
| `lib/core/models/studio_config.dart` | ~213 | ✅ model |

`studio_block_router.dart` is the reference shape: <250 lines, one job, a single
constructor-injected `RouterLlmCall` dependency.

---

## 1. Cross-cutting duplication to consolidate first

These are the highest-leverage fixes because they remove copies, not just move
code. Do them as shared specialists before/while splitting the god objects.

### 1.1 API-config resolution — **3 copies**
- `StudioDecompositionService._callLlm` (apiConfig vs sidecar vs active chat)
- `AgentRunner.resolveAgentConfig` (custom vs run vs active, with `runApiConfigId`)
- `_StudioMenuDialogState._resolveTrackerApiConfig` + `_resolveBuildApiConfig`
  (the comment already admits it mirrors `AgentRunner`)

→ Extract **`StudioApiConfigResolver`** (constructor-inject `Ref`). All three call
sites delegate. `AgentRunner.resolveAgentConfig` must stay overridable (a test
subclasses it) — have it delegate to the resolver internally.

### 1.2 Reasoning / `<think>` stripping — **2 near-identical regex sets**
- `StudioDecompositionService._stripPromptLevelReasoning`
- `AgentRunner._stripThinkDirective` / static `AgentRunner.stripPromptLevelReasoning`

→ Extract **`ReasoningStripper`** (pure static helper). Keep a static delegator on
`AgentRunner` (tests/call sites reference `AgentRunner.stripPromptLevelReasoning`).

### 1.3 JSON object extraction — **3 copies**
- `MemoryStudioService._extractJsonObject`
- `StudioBlockRouter._extractJsonObject`
- `StudioDecompositionService` (fence-stripping variant)

→ Consolidate into a single `extractJsonObject(String)` top-level function next to
`repairJson` in `lib/core/llm/json_repair.dart` (already the JSON-hygiene home).

---

## 2. `MemoryStudioService` (chat-time) — extraction plan

The class is near-stateless: the **only** mutable field is `_briefCache`. Most
clusters are pure functions, so extraction is low-risk. Target: `runTrackerCycle`
shrinks from ~266 lines to ~80–100; the service becomes a thin orchestrator that
injects the specialists below.

| New specialist | Moves (clusters) | ~Lines | Constructor deps |
|---|---|---|---|
| **`StudioBriefParser`** | JSON/section parse, cleaning, prose-detection, fallbacks | ~210 | none (pure) |
| **`StudioBriefDeduper`** | cross-brief dedup + meta-policy brief sanitization | ~130 | none (pure) |
| **`StudioBriefCache`** | cache probe/persist, refresh-policy inference, scene/turn keys, **owns `_briefCache`** | ~180 | `StudioBriefParser` |
| **`StudioContextBucketizer`** | `PromptResult` → static/dynamic/history buckets, mandatory fallbacks | ~180 | none |
| **`StudioPromptText`** | the big prompt-text constants (runtime envelope, controller scope, final style contract, meta-policy text) | ~150 | none |
| **`StudioMessageBuilder`** | agent/batch/per-agent message assembly, history limits, macro expansion, role/text utils | ~250 | `StudioContextBucketizer`, `StudioPromptText` |
| **`StudioAgentExecutor`** | single-agent + post-gen + individual + final run adapters | ~190 | `Ref`, `StudioMessageBuilder`, `StudioBriefParser`, `StudioPromptText` |
| **`StudioBatchCoordinator`** | batch group exec + 2-layer retry/fallback | ~150 | `Ref`, `StudioMessageBuilder`, `StudioAgentExecutor` |
| **`StudioActivationGate`** | `matchesActivationKeywords`, `splitAgentsByPhase`, unify the duplicated inline runInterval/keyword gating into one `dueTrackers(...)` | ~80 | none |

**Orchestrator keeps:** `getEnabledConfig`, `runTrackerCycle` (slimmed), `_log`.

### Test constraint (HARD)
`MemoryStudioService.matchesActivationKeywords` and `splitAgentsByPhase` are
`static @visibleForTesting` and called by name in `test/studio_activation_test.dart`
(18 sites) and `test/studio_post_processing_test.dart` (7 sites). When they move to
`StudioActivationGate`, **keep static forwarding shims on `MemoryStudioService`** to
avoid test churn. `AgentPhaseSplit` must stay public at a stable import path.

---

## 3. `StudioDecompositionService` (build-time) — extraction plan

Stateless except `Ref`. All complexity is behavior.

| New specialist | Moves | ~Lines | Notes |
|---|---|---|---|
| **`StudioControllerOntology`** | `_controllerSpecs` (8 hard-coded controller defs) + `_specForAgent` | ~150 | pure data + lookup |
| **`StudioBlockClassifier`** | `isReasoningBlock`, `isBroadcastBlock`, `_bucketForBlock` (140-line keyword router), `collectBroadcastBlocks` | ~250 | pure; already characterization-tested; sibling of `StudioBlockRouter` |
| **`StudioBlockExpander`** | `expandBlocksForRouting` + setvar/getvar helpers | ~90 | pure block transform |
| **`StudioShardSynthesizer`** | verbatim + LLM-compiled shard synthesis, fence/refusal cleanup, agent normalization | ~250 | inject `StudioBuildLlmClient`, `ReasoningStripper` |
| **`StudioBuildLlmClient`** | `_callLlm` + config resolution | ~80 | inject `Ref` + `StudioApiConfigResolver`; shareable with `StudioBlockRouter` via `RouterLlmCall` |

**Orchestrator keeps:** `decompose`, `regenerateAgentInstruction`, `_assignBlocks`,
`_routeBlocks` (thin glue).

### Test constraint (HARD)
`StudioDecompositionService.{isReasoningBlock, isBroadcastBlock,
expandBlocksForRouting, computePresetHash}` are static and called by
`test/studio_block_router_test.dart` and `test/studio_verbatim_routing_test.dart`.
Keep static delegators on `StudioDecompositionService` after the move.

---

## 4. `TrackerBatcher` — split

Six concerns; the build+parse pair and the concurrency limiter are cleanly
separable and fully test-covered.

| New specialist | Moves | Notes |
|---|---|---|
| **`TrackerBatchProtocol`** | `buildBatchSystemPrompt`, `parseBatchResponse`, `_extractResultBlock`, `_matchLegacyResultTag`, XML escapes | pure serializer pair |
| **`ConcurrencyLimiter`** | `settleWithConcurrencyLimit` + impl | generic, reusable (also used by `MemoryStudioService` retry path) |

**`TrackerBatcher` keeps:** grouping + budget math (`groupAgents`, `_capBatchMaxTokens`,
`_minTemperature`, `_maxContextSize`), parallel-job split, `shouldRunIndividually`.

### Test constraint (HARD)
`test/characterization/tracker_batcher_test.dart` uses the **no-arg constructor** and
calls `buildBatchSystemPrompt`/`parseBatchResponse`/`shouldRunIndividually`/
`normalizeMaxParallelJobs`/`splitGroupForParallelJobs` directly. Preserve the no-arg
ctor and the runner-free method surface (delegate to the new specialists internally,
or re-expose them).

---

## 5. `studio_menu_dialog.dart` — extract a controller

Per CODE_STYLE "UI Files — Only Extract Logic": the widget is allowed to stay large,
but business logic must move out. Extract **`StudioMenuController`** (mirror the
existing `MemoryBookController` pattern):

- `_buildStudio` (decompose + collect broadcast + hash + assemble config + upsert)
- `_regenerateAgentInstruction` (service call + rebuild agents + rehash + upsert)
- `_resolveTrackerApiConfig` / `_resolveBuildApiConfig` → delegate to
  `StudioApiConfigResolver` (§1.1)
- `_toggleEnabled` / `_toggleAgent` / `_setAgentModelOverride` / `_setAgentPromptShard`
  (read-modify-write `StudioConfig.agents` + upsert)
- the `/models` fetch in `_editAgentModel`

The widget keeps `build`, the private `_TrackerRow`/`_StatusChip` widgets, and thin
callbacks. No unit tests pin this file → low constraint.

---

## 6. `MemoryBookController` — split (memory domain, lower priority)

Three jobs:
- **`MemoryDraftGenerationController`** — draft-generation lifecycle (owns the mutable
  state: timers, cancel tokens, active/generating sets). Preserve `generateDraft`
  INV-M3 mutex (pinned by `test/characterization/memory_draft_mutex_test.dart`).
- **`MemorySettingsMapper`** — `globalSettingsAsBookSettings` + `updateSettings` (pure
  bidirectional mapper, ~95 lines).
- Controller orchestrates + keeps entry/index CRUD.

Note: this is the only file in the set using `WidgetRef` (the rest use `Ref`).

---

## 7. Lower-priority

- `agent_runner.dart`: optionally extract `AgentStreamRunner` (the 180-line streaming
  state machine), leaving `AgentRunner` as resolver + failure-wrapper. Move
  reasoning-stripping to `ReasoningStripper` (§1.2).
- `memory_agentic_write_service.dart`: extract `AgenticWriteRequestParser`
  (`_askLlmForWrites` prompt+parse) from the write-execution.
- `memory_agentic_tools.dart`: split into tool-defs / search-handler / write-DTOs
  files (no single class is over 250; cosmetic).
- `studio_request_preset.dart`: optionally move legacy migration helpers to
  `StudioPresetMigration` so the data file is pure data. Low priority.

---

## 8. Suggested order (impact × test-safety)

Each numbered step below is **one or more commits on `plan/continuity-post-cleaner`**
(one specialist extraction per commit). Land them incrementally — never one giant
commit. After every commit, analyze + test must be green before the next.

1. ✅ **Shared specialists** `StudioApiConfigResolver`, `ReasoningStripper`,
   `extractJsonObject` (§1) — removes 3+2+3 copies, unblocks the rest.
2. ✅ **`StudioDecompositionService`** (§3) — biggest single win; classifiers already
   have characterization tests.
3. ✅ **`TrackerBatcher`** (§4) — fully test-covered, safe split.
4. ⚠️ **`MemoryStudioService`** (§2) — pure/leaf specialists + brief cache done (6/9:
   ActivationGate, PromptText, BriefParser, ContextBucketizer, BriefDeduper,
   BriefCache); message builder + executors + batch coordinator deferred (see §10).
5. ✅ **`studio_menu_dialog`** (§5) — `StudioMenuController` extracted; removes the 3rd
   config-resolver copy.
6. ✅ **`MemoryBookController`** (§6) — `MemorySettingsMapper` +
   `MemoryDraftGenerationController` extracted. §7 items not done.

## 9. Guardrails

- Work on the current `plan/continuity-post-cleaner` branch — do **not** cut a separate
  refactor branch. The studio / agent / post-cleaner work is one continuous effort that
  lands as a series of small commits on that branch.
- One specialist extraction per commit; run `flutter analyze` (must stay
  `No issues found!`) + `flutter test` (1409 green) after **each** commit.
- Constructor injection only; no new upward `Ref` dependencies in pure specialists
  (pass values/callbacks, per CODE_STYLE row "Component depends on Riverpod `Ref`").
- Keep all `@visibleForTesting` static methods reachable via delegators (see the HARD
  constraints in §2/§3/§4) — do not edit tests as part of a "no behavior change"
  refactor unless a delegator is genuinely impossible.
- Regenerate `build_runner` only if a model changes (none planned here).

## 10. Deferred follow-up (stateful clusters)

The remaining extractions share mutable host state (`_ref`, `_log`, `_briefCache`,
`_book` + `save()`/`updateBook()`) across multiple methods. Extracting them under the
"no behavior change" mandate would require threading that state through a fragile
callback/interface with no net readability win at the current size. They are deferred
to a follow-up that can pair the extraction with the necessary interface design (and
optionally characterization tests for the moved cluster).

### §2 — MemoryStudioService (chat-time), 3 remaining specialists
- ✅ `StudioBriefCache` (owns `_briefCache`, cache probe/persist + refresh-policy) — DONE.
- `StudioMessageBuilder` (agent/batch/per-agent message assembly, history limits,
  macro expansion).
- `StudioAgentExecutor` (single-agent + post-gen + individual + final run adapters).
- `StudioBatchCoordinator` (batch group exec + 2-layer retry/fallback).
The remaining three are glued through `runTrackerCycle` + the shared `_ref`/`_log`,
and extracting them materially restructures the orchestrator (not just moving
isolated helpers, as the cache was). They are deferred to a follow-up that can pair
the extraction with interface design + streaming behavior characterization tests.
`MemoryStudioService` is now ~1222 lines (from ~2346, a 48% reduction from the 6
completed specialists).

### §6 — MemoryBookController ✅ COMPLETE
- ✅ `MemorySettingsMapper` (pure bidirectional settings mapper) — DONE.
- ✅ `MemoryDraftGenerationController` (draft-generation lifecycle: timers, cancel
  tokens, active/generating sets, `generateDraft`/`batchGenerate`/`cancelDraftGeneration`)
  — DONE. INV-M3 mutex pinned by `test/characterization/memory_draft_mutex_test.dart`
  (tests the shared `memoryActiveDraftsProvider` contract, not the controller directly).
  The `_book` reads + `save()`/`updateBook()` writes threaded through injected
  `bookGetter`/`persistAndSet` closures. `MemoryBookController` is now 322 lines (from
  619, a 48% reduction) — a thin orchestrator.

### §7 — lower-priority items
- `agent_runner.dart`: `AgentStreamRunner` extraction (streaming state machine).
- `memory_agentic_write_service.dart`: `AgenticWriteRequestParser`.
- `memory_agentic_tools.dart`: file split (cosmetic).
