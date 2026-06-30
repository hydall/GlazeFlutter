import 'package:freezed_annotation/freezed_annotation.dart';

part 'pipeline_settings.freezed.dart';
part 'pipeline_settings.g.dart';

/// Global generation-pipeline LLM settings, separated from [MemoryBookSettings].
///
/// These fields configure LLM sidecars and post-generation passes that have
/// nothing to do with memory retrieval:
/// - Memory generation LLM (writes memory entries)
/// - Classifier LLM (classifies memory importance)
/// - Sidecar LLM (write-loop + reranker)
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

    // ── Classifier LLM ────────────────────────────────────────────────────
    @Default(false) bool classifierEnabled,
    @Default('current') String classifierSource,
    @Default('') String classifierModel,
    @Default('') String classifierEndpoint,
    @Default('') String classifierApiKey,
    @Default(2500) int classifierTimeoutMs,

    // ── Sidecar LLM (write-loop + reranker) ────────────────────────────────
    @Default(false) bool sidecarEnabled,
    @Default('current') String sidecarSource,
    @Default('') String sidecarModel,
    @Default('') String sidecarEndpoint,
    @Default('') String sidecarApiKey,
    @Default(60000) int sidecarTimeoutMs,

    // ── Agentic write-loop ────────────────────────────────────────────────
    @Default(false) bool agenticWriteEnabled,
    // Cadence: run the agentic write-loop every N assistant turns. 1 = every
    // turn. Mirrors Marinara-Engine's tracker-agent model, where built-in
    // trackers (`world-state`, `character-tracker`, `persona-stats`, `quest`,
    // `custom-tracker`) run unconditionally every turn — no cadence gate.
    // Higher values were considered for cost savings, but stale tracker
    // values between runs degraded the final response (the final responder
    // reads stale state, the post-cleaner audits against stale facts, and
    // the user sees outdated Tracker Values in the UI for N-1 turns). The
    // cadence knob is retained for users who want to opt back into the
    // throttled behavior via the UI.
    @Default(1) int runAgenticEveryN,
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
    // Max tokens for the Studio final generator (Main Responder). When > 0,
    // overrides the per-agent default (8000). Useful for reasoning models
    // (e.g. Gemini) that spend most of the budget on thinking and leave too
    // little for the actual reply. 0 = use the agent's own maxTokens.
    @Default(0) int studioFinalMaxTokens,
    // Temperature for the Studio final generator (Main Responder). When
    // >= 0, overrides the per-agent default (0.8 for the final agent, 0.3
    // for trackers). Negative = use the agent's own temperature.
    @Default(-1.0) double studioFinalTemperature,
    // When true, the final generator's request forces requestReasoning=false
    // and omitReasoning=true regardless of the ApiConfig. Targeted at Gemini
    // Flash thinking models that spend most of the token budget on a
    // think-block and leave too little for the actual reply, truncating the
    // visible prose mid-sentence. Intermediate agents are unaffected (they
    // still reason when the ApiConfig asks them to). Only effective for
    // Gemini-protocol endpoints; other transports ignore the override.
    @Default(false) bool studioFinalDisableReasoning,

    // ── Studio trackers (intermediate agents) ───────────────────────────
    // The 7 pre-gen controllers (continuity / agency / narrative / dialogue /
    // guard / world / meta) share one logical batch — they all produce compact
    // JSON briefs, not prose, so a cheap fast model is usually enough. These
    // four fields let the user configure them as a group from the Studio menu
    // instead of editing each of the 7 agents individually.
    // Model id override applied to ALL non-final Studio agents when non-empty.
    // Empty = use each agent's own `modelOverride` or the chat's run model.
    @Default('') String studioTrackerModelOverride,
    // Max tokens for ALL non-final Studio agents. When > 0, overrides the
    // per-agent default (1600). 0 = use the agent's own maxTokens.
    @Default(0) int studioTrackerMaxTokens,
    // Temperature for ALL non-final Studio agents. When >= 0, overrides the
    // per-agent default (0.3). Negative = use the agent's own temperature.
    @Default(-1.0) double studioTrackerTemperature,
    // When true, all non-final Studio agent requests force
    // requestReasoning=false and omitReasoning=true. Trackers emit compact
    // JSON briefs, so a hidden think-block wastes tokens without improving the
    // brief. Only effective for Gemini-protocol endpoints.
    @Default(false) bool studioTrackerDisableReasoning,

    // ── POST-cleaner ──────────────────────────────────────────────────────
    @Default(false) bool postCleanerEnabled,
    @Default(0.3) double postCleanerTemperature,
    @Default(0) int postCleanerMaxTokens,
    @Default('inherit') String postCleanerSource,
    @Default('') String postCleanerModel,
    @Default('') String postCleanerEndpoint,
    @Default('') String postCleanerApiKey,
    @Default(0) int postCleanerTimeoutMs,
    @Default(true) bool postCleanerContinuityEnabled,
    @Default(false) bool postCleanerCharacterCheckEnabled,
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

    // ── Studio Ledger ─────────────────────────────────────────────────────
    // Mandatory internal continuity ledger that runs after every final
    // assistant response when Studio is enabled. Writes compact entity/
    // relationship/arc/world state and durable MemoryBook facts.
    // See docs/plans/PLAN_STUDIO_LEDGER_MEMORY.md.
    @Default(false) bool studioLedgerEnabled,
    // Model for the ledger LLM call. When empty, inherits the sidecar model.
    @Default('') String studioLedgerModel,
    // Endpoint override for the ledger LLM. When empty, inherits sidecar.
    @Default('') String studioLedgerEndpoint,
    // API key override for the ledger LLM. When empty, inherits sidecar.
    @Default('') String studioLedgerApiKey,
    // Ledger LLM call timeout in milliseconds. 0 = use sidecarTimeoutMs.
    @Default(0) int studioLedgerTimeoutMs,
    // Max tokens for the ledger LLM call. 0 = use default (2000).
    @Default(0) int studioLedgerMaxTokens,
    // Temperature for the ledger LLM call. Negative = use default (0.2).
    @Default(-1.0) double studioLedgerTemperature,

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
