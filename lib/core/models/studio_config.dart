import 'package:freezed_annotation/freezed_annotation.dart';

part 'studio_config.freezed.dart';
part 'studio_config.g.dart';

/// Per-session Studio configuration. Bound to a chat session — copied on branch.
///
/// Created when the user clicks "Build Studio" in the MagicDrawer Studio menu.
/// The LLM decomposes the active preset into agent tasks, each with its own
/// prompt shard and optional model override.
@freezed
abstract class StudioConfig with _$StudioConfig {
  const factory StudioConfig({
    required String sessionId,
    @Default(false) bool enabled,
    @Default([]) List<StudioAgent> agents,
    @Default('') String sourcePresetId,
    @Default('') String sourcePresetHash,
    @Default('') String buildApiConfigId,
    @Default('') String runApiConfigId,
    @Default(0) int createdAt,
    @Default(0) int updatedAt,
  }) = _StudioConfig;

  factory StudioConfig.fromJson(Map<String, dynamic> json) =>
      _$StudioConfigFromJson(json);
}

/// A single agent in the Studio pipeline.
///
/// Each agent receives:
/// - Its [promptShard] (instructions extracted from the preset)
/// - Compact memory context (from Memory Book)
/// - Briefs from previous agents in the pipeline
///
/// The [order] field determines pipeline execution order.
@freezed
abstract class StudioAgent with _$StudioAgent {
  const factory StudioAgent({
    required String id,
    @Default('') String name,
    @Default('') String role,
    @Default('') String promptShard,
    @Default(0) int order,
    @Default(true) bool enabled,
    @Default('current') String modelSource,
    @Default('') String model,
    @Default('') String modelOverride,
    @Default('') String endpoint,
    @Default(4000) int timeoutMs,
    @Default(0.3) double temperature,
    @Default(500) int maxTokens,
    @Default('') String sourceBlockNames,
  }) = _StudioAgent;

  factory StudioAgent.fromJson(Map<String, dynamic> json) =>
      _$StudioAgentFromJson(json);
}
