import 'package:freezed_annotation/freezed_annotation.dart';

part 'pipeline_settings.freezed.dart';
part 'pipeline_settings.g.dart';

/// Global generation-pipeline LLM settings, separated from [MemoryBookSettings].
///
/// These fields configure auxiliary LLM calls and post-generation passes that have
/// nothing to do with memory retrieval:
/// - Memory generation LLM (writes memory entries)
/// - Auxiliary LLM defaults (write-loop + cleaner + ledger fallback)
/// - Agentic write-loop
/// - POST-cleaner (anti-cliche rewrite + continuity audit)
/// - Consolidation LLM (merges memory entries)
///
/// Singleton global, persisted in SharedPreferences under the 'pipelineSettings'
/// key (see `pipeline_settings_provider.dart`). Previously per-session in the
/// `pipeline_settings_rows` Drift table; that table was dropped in schema v52
/// because pipeline settings are configured once via Build Studio and applied
/// uniformly across all chats.
@freezed
abstract class PipelineSettings with _$PipelineSettings {
  const factory PipelineSettings({
    // ── Memory generation LLM ──────────────────────────────────────────────
    @Default('current') String generationSource,
    @Default('') String generationModel,
    @Default(false) bool generationUseCurrentModelOverride,
    @Default('') String generationEndpoint,
    @Default('') String generationApiKey,
    @Default(null) double? generationTemperature,
    @Default(null) int? generationMaxTokens,

    // ── Auxiliary LLM defaults ─────────────────────────────────────────────
    // Shared fallback config for non-streaming helper LLM calls such as the
    // write-loop, POST-cleaner, Studio Ledger, and consolidation. MemoryBook
    // retrieval does not use this; it is local/vector-only.
    @Default('current') String auxSource,
    @Default('') String auxModel,
    @Default('') String auxEndpoint,
    @Default('') String auxApiKey,
    @Default(60000) int auxTimeoutMs,

    // ── Agentic write-loop ────────────────────────────────────────────────
    @Default(true) bool agenticWriteEnabled,
    // Cadence: run the agentic write-loop every N assistant turns. 5 = every
    // 5th turn (batch mode — the LLM analyzes 5 U-A turns at once and writes
    // a concise short-term memory summary, not per-turn entries).
    @Default(5) int runAgenticEveryN,
    // ── Agentic write-loop cadence (plan §Model Cadence) ────────────────
    // Run mode: 'every_turn' | 'conditional' | 'every_n' | 'manual' | 'disabled'.
    // 'every_n' is the default (batch 5 turns → 1 LLM call).
    @Default('every_n') String agenticWriteRunMode,
    // When true, block the next user-message generation until the write-loop
    // finishes (or times out). Default false = fire-and-forget.
    @Default(true) bool agenticWriteBlockNextGen,
    // Conditional triggers (plan §Model Cadence Memory write-loop). Only
    // consulted when runMode == 'conditional'.
    @Default(true) bool agenticWriteRunWhenMentionedEntitiesChanged,
    @Default(false) bool agenticWriteRunWhenMemoryBookCandidatesExist,
    // When true, agent writes land in `pendingDrafts` for manual user
    // approval instead of being auto-approved as `MemoryEntry`. The user
    // reviews drafts in the existing MemoryBook UI ("Pending drafts"
    // section) and promotes or rejects them. Append-only updates to
    // existing entries are also deferred — the newFacts are written as a
    // new draft whose content is the appended text, NOT merged into the
    // existing entry until the user approves. Mirrors Marinara's
    // `agentWriteApprovalRequired` per-chat flag. Default false = legacy
    // auto-approve behavior.
    // See docs/plans/PLAN_MEMORY_CONTINUITY.md §4 (agentWriteApprovalRequired).
    @Default(false) bool agentWriteApprovalRequired,
    // Enable raw-message recall (cosine search over chat_message embeddings).
    // Pairs with `ChatMessageEmbeddingService` + `MessageRecallService` as the
    // lossless backstop for the lossy MemoryBook compression. Auto-disables
    // when the embedding endpoint is empty (see `_embedChatMessages` and
    // `MessageRecallService.recall`). Mirrors Marinara's `enableMemoryRecall`
    // per-chat flag, but global here for simplicity.
    // See docs/plans/PLAN_MEMORY_CONTINUITY.md §1 (patch #3) and §2.1 (ADR).
    @Default(true) bool messageRecallEnabled,

    // ── Studio agents ────────────────────────────────────────────────────
    // Per-agent idle timeout (ms) before the model emits its first chunk.
    // Once any chunk (text or reasoning) arrives, the idle timer is
    // cancelled entirely so a long generation is never cut off. 0 = use the
    // per-agent fallback (final generator: 90s, trackers: 60s).
    @Default(0) int studioTimeoutMs,
    // Final-generator idle timeout (ms). 0 = use agent/global fallback.
    @Default(0) int studioFinalTimeoutMs,
    // Max tokens for the Studio final generator (Main Responder). When > 0,
    // overrides the per-agent default (8000). Useful for reasoning models
    // (e.g. Gemini) that spend most of the budget on thinking and leave too
    // little for the actual reply. 0 = use the agent's own maxTokens.
    @Default(0) int studioFinalMaxTokens,
    @Default(0.9) double studioFinalTopP,
    @Default(0) int studioFinalTopK,
    @Default(0.0) double studioFinalFrequencyPenalty,
    @Default(0.0) double studioFinalPresencePenalty,
    // Chat history messages override for the Studio final generator (Main
    // Responder). When > 0, overrides StudioConfig.maxFinalHistoryMessages.
    // 0 = use per-session StudioConfig default (15).
    @Default(0) int studioFinalContextSize,
    // Temperature for the Studio final generator (Main Responder). When
    // >= 0, overrides the per-agent default (0.8 for the final agent, 0.3
    // for trackers). Negative = use the agent's own temperature.
    @Default(1.0) double studioFinalTemperature,
    @Default(false) bool studioFinalRequestReasoning,
    @Default('auto') String studioFinalReasoningEffort,
    @Default(false) bool studioFinalOmitTemperature,
    @Default(false) bool studioFinalOmitTopP,
    @Default(true) bool studioFinalOmitReasoning,
    @Default(true) bool studioFinalOmitReasoningEffort,
    // When true, the final generator's request forces requestReasoning=false
    // and omitReasoning=true regardless of the ApiConfig. Targeted at Gemini
    // Flash thinking models that spend most of the token budget on a
    // think-block and leave too little for the actual reply, truncating the
    // visible prose mid-sentence. Intermediate agents are unaffected (they
    // still reason when the ApiConfig asks them to). Only effective for
    // Gemini-protocol endpoints; other transports ignore the override.
    @Default(false) bool studioFinalDisableReasoning,
    // Model id override for the Studio final generator. Empty = use the
    // selected Studio final API config model, or the active chat model when no
    // final API config is selected. This is intentionally separate from
    // [generationModel], which belongs to MemoryBook generation.
    @Default('') String studioFinalModelOverride,

    // ── Studio trackers (intermediate agents) ───────────────────────────
    // The 7 pre-gen controllers (continuity / agency / narrative / dialogue /
    // guard / world / meta) share one logical batch — they all produce compact
    // JSON briefs, not prose, so a cheap fast model is usually enough. These
    // four fields let the user configure them as a group from the Studio menu
    // instead of editing each of the 7 agents individually.
    // Model id override applied to ALL non-final Studio agents when non-empty.
    // Empty = use each agent's own `modelOverride` or the chat's run model.
    @Default('') String studioTrackerModelOverride,
    // Tracker idle timeout (ms). 0 = use agent/global fallback.
    @Default(0) int studioTrackerTimeoutMs,
    // Max tokens for ALL non-final Studio agents. When > 0, overrides the
    // per-agent default (1600). 0 = use the agent's own maxTokens.
    @Default(0) int studioTrackerMaxTokens,
    @Default(0.9) double studioTrackerTopP,
    @Default(0) int studioTrackerTopK,
    @Default(0.0) double studioTrackerFrequencyPenalty,
    @Default(0.0) double studioTrackerPresencePenalty,
    // Temperature for ALL non-final Studio agents. When >= 0, overrides the
    // per-agent default (0.3). Negative = use the agent's own temperature.
    @Default(0.5) double studioTrackerTemperature,
    @Default(false) bool studioTrackerRequestReasoning,
    @Default('auto') String studioTrackerReasoningEffort,
    @Default(false) bool studioTrackerOmitTemperature,
    @Default(false) bool studioTrackerOmitTopP,
    @Default(true) bool studioTrackerOmitReasoning,
    @Default(true) bool studioTrackerOmitReasoningEffort,
    // When true, all non-final Studio agent requests force
    // requestReasoning=false and omitReasoning=true. Trackers emit compact
    // JSON briefs, so a hidden think-block wastes tokens without improving the
    // brief. Only effective for Gemini-protocol endpoints.
    @Default(false) bool studioTrackerDisableReasoning,

    // Context size override for ALL non-final Studio agents (batch and
    // individual). When > 0, overrides the per-agent contextSize and the
    // batch MAX-of-all-agents logic. 0 = use per-agent contextSize (default
    // 5 per agent, batch = max across group).
    @Default(0) int studioTrackerContextSize,

    // ── Post-processing trackers ─────────────────────────────────────────
    // Number of trailing chat messages forwarded to post-processing
    // (post-gen) trackers. Default 1 (only the response to edit).
    @Default(1) int studioPostTrackerContextSize,

    // ── POST-cleaner ──────────────────────────────────────────────────────
    @Default(true) bool postCleanerEnabled,
    @Default(0.7) double postCleanerTemperature,
    @Default(0) int postCleanerMaxTokens,
    @Default(0.9) double postCleanerTopP,
    @Default(0) int postCleanerTopK,
    @Default(0.0) double postCleanerFrequencyPenalty,
    @Default(0.0) double postCleanerPresencePenalty,
    @Default('inherit') String postCleanerSource,
    @Default('') String postCleanerModel,
    @Default('') String postCleanerEndpoint,
    @Default('') String postCleanerApiKey,
    @Default(0) int postCleanerTimeoutMs,
    @Default(true) bool postCleanerContinuityEnabled,
    @Default(true) bool postCleanerCharacterCheckEnabled,
    @Default(12) int postCleanerHistoryMessages,
    @Default(3000) int postCleanerMaxCharsPerMessage,
    // Optional model override for the character/world audit pass. When empty,
    // the audit inherits the cleaner's resolved model (Fix 2). Endpoint / key /
    // source / protocol are always inherited from the cleaner config — only
    // the model can differ.
    @Default('') String postCleanerAuditModel,
    // Global prose-guardian style overrides (Marinara
    // `applyProseGuardianChatSettings` port, adapted to our global-only
    // pipeline settings). When non-empty, these flow into the cleaner
    // prompt ALONGSIDE the preset's broadcastBlocks: the cleaner avoids
    // words in [postCleanerBannedWords], follows
    // [postCleanerAvoidInstructions], and prefers style described in
    // [postCleanerStyleInstructions]. Empty = no override; the broadcast
    // rules from the preset remain authoritative.
    @Default('') String postCleanerBannedWords,
    @Default('') String postCleanerAvoidInstructions,
    @Default('') String postCleanerStyleInstructions,
    // When true, the POST-cleaner request forces omitReasoning=true so
    // Gemini Flash thinking models cannot spend the rewrite budget on a
    // think-block. Only affects the cleaner LLM call, not the audit.
    @Default(false) bool postCleanerDisableReasoning,
    @Default(false) bool postCleanerRequestReasoning,
    @Default('auto') String postCleanerReasoningEffort,
    @Default(false) bool postCleanerOmitTemperature,
    @Default(false) bool postCleanerOmitTopP,
    @Default(true) bool postCleanerOmitReasoning,
    @Default(true) bool postCleanerOmitReasoningEffort,

    // ── Studio Ledger ─────────────────────────────────────────────────────
    // Mandatory internal continuity ledger that runs after every final
    // assistant response when Studio is enabled. Writes compact entity/
    // relationship/arc/world state and durable MemoryBook facts.
    // See docs/plans/PLAN_STUDIO_LEDGER_MEMORY.md.
    @Default(true) bool studioLedgerEnabled,
    // Model for the ledger LLM call. When empty, inherits the aux model.
    @Default('') String studioLedgerModel,
    // Endpoint override for the ledger LLM. When empty, inherits aux.
    @Default('') String studioLedgerEndpoint,
    // API key override for the ledger LLM. When empty, inherits aux.
    @Default('') String studioLedgerApiKey,
    // Ledger LLM call timeout in milliseconds. 0 = use auxTimeoutMs.
    @Default(0) int studioLedgerTimeoutMs,
    // Max tokens for the ledger LLM call. 0 = use default (2000).
    @Default(0) int studioLedgerMaxTokens,
    // Temperature for the ledger LLM call. Negative = use default (0.2).
    @Default(-1.0) double studioLedgerTemperature,
    // ── Studio Ledger cadence (plan §Model Cadence) ──────────────────────
    // Run mode: 'every_turn' | 'conditional' | 'every_n' | 'manual' | 'disabled'.
    // 'every_turn' is the default. Studio forces it on regardless of this
    // setting when StudioConfig.enabled is true; this field is only consulted
    // for non-Studio generations (standalone ledger) or when the user opts
    // into a low-power cadence inside Studio.
    @Default('every_turn') String studioLedgerRunMode,
    // Interval N assistant turns when runMode == 'every_n'. 1 = every turn.
    @Default(1) int studioLedgerIntervalN,
    // When true, block the next user-message generation until the ledger
    // finishes (or times out). Default false = fire-and-forget; the next
    // generation uses the previous committed canon if Ledger is still
    // running (plan §Failure Behavior).
    @Default(false) bool studioLedgerBlockNextGen,
    // Conditional triggers (plan §Model Cadence Studio Ledger). Only
    // consulted when runMode == 'conditional'. All must be true for the
    // ledger to run; false on any one skips the run.
    @Default(true) bool studioLedgerRunWhenMentionedEntitiesChanged,
    @Default(true) bool studioLedgerRunWhenSceneChanged,
    @Default(false) bool studioLedgerRunWhenMemoryBookCandidatesExist,

    // ── Memory dedup ─────────────────────────────────────────────────────
    // When true, the dedup pass runs automatically after each agentic
    // write-loop cycle (delayed, fire-and-forget). When false, dedup only
    // runs when the user clicks the "Dedup" button in the memory book UI.
    @Default(false) bool memoryDedupAutoEnabled,
    // Cosine similarity threshold for candidate pairs (0.0-1.0).
    // Pairs with cosine >= this value are sent to the LLM for merge/drop/keep.
    @Default(0.85) double memoryDedupThreshold,

    // ── Consolidation LLM ────────────────────────────────────────────────
    @Default(false) bool consolidationEnabled,
    @Default(5) int consolidationThreshold,
    @Default('current') String consolidationSource,
    @Default('') String consolidationModel,
    @Default('') String consolidationEndpoint,
    @Default('') String consolidationApiKey,
    @Default(4000) int consolidationTimeoutMs,
  }) = _PipelineSettings;

  factory PipelineSettings.fromJson(Map<String, dynamic> json) =>
      _$PipelineSettingsFromJson(json);
}
