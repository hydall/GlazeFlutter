import 'package:freezed_annotation/freezed_annotation.dart';

part 'pipeline_settings.freezed.dart';
part 'pipeline_settings.g.dart';

/// Generation-pipeline LLM settings, separated from [MemoryBookSettings].
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
/// Per-session, stored in `pipeline_settings_rows`. Global defaults mirror a
/// subset via [PipelineGlobalSettings] (SharedPreferences) and merge in
/// `pipeline_settings_repo.dart`.
@freezed
abstract class PipelineSettings with _$PipelineSettings {
  const factory PipelineSettings({
    // ── Memory generation LLM ──────────────────────────────────────────────
    @Default('current') String generationSource,
    @Default('') String generationModel,
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
