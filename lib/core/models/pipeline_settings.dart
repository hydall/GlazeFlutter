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

    // ── Studio agents ────────────────────────────────────────────────────
    // Per-agent idle timeout (ms) before the model emits its first chunk.
    // Once any chunk (text or reasoning) arrives, the idle timer is
    // cancelled entirely so a long generation is never cut off. 0 = use the
    // per-agent fallback (final generator: 90s, trackers: 60s).
    @Default(0) int studioTimeoutMs,

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
