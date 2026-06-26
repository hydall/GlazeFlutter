import 'package:freezed_annotation/freezed_annotation.dart';

part 'pipeline_global_settings.freezed.dart';
part 'pipeline_global_settings.g.dart';

/// Global pipeline defaults, stored in SharedPreferences (mirror of
/// [PipelineSettings] for per-session overrides).
///
/// Loaded once at startup and merged with per-session [PipelineSettings] in
/// `pipeline_settings_repo.dart`: per-session non-default values override
/// global ones.
@freezed
abstract class PipelineGlobalSettings with _$PipelineGlobalSettings {
  const factory PipelineGlobalSettings({
    // ── Memory generation LLM ──────────────────────────────────────────────
    @Default('current') String generationSource,
    @Default('') String generationModel,
    @Default(false) bool generationUseCurrentModelOverride,
    @Default('') String generationEndpoint,
    @Default('') String generationApiKey,
    double? generationTemperature,
    int? generationMaxTokens,

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

    // ── Consolidation LLM ────────────────────────────────────────────────
    @Default(false) bool consolidationEnabled,
    @Default(5) int consolidationThreshold,
    @Default('current') String consolidationSource,
    @Default('') String consolidationModel,
    @Default('') String consolidationEndpoint,
    @Default('') String consolidationApiKey,
    @Default(4000) int consolidationTimeoutMs,
  }) = _PipelineGlobalSettings;

  factory PipelineGlobalSettings.fromJson(Map<String, dynamic> json) =>
      _$PipelineGlobalSettingsFromJson(json);
}
