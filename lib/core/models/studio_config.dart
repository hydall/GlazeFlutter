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
    @Default('') String finalPresetId,
    @Default('') String agentStudioPresetId,
    @Default('') String finalStudioPresetId,
    @Default([]) List<StudioPresetOverride> studioPresetOverrides,
    @Default('') String sourcePresetHash,
    @Default('') String buildApiConfigId,
    @Default('') String runApiConfigId,
    @Default([]) List<String> selectedBlockIds,
    @Default(false) bool selectedBlockIdsInitialized,
    @Default(0) int createdAt,
    @Default(0) int updatedAt,
  }) = _StudioConfig;

  factory StudioConfig.fromJson(Map<String, dynamic> json) =>
      _$StudioConfigFromJson(json);
}

@freezed
abstract class StudioPresetOverride with _$StudioPresetOverride {
  const factory StudioPresetOverride({
    required String id,
    @Default('') String name,
    @Default('') String intermediateInstruction,
    @Default('') String finalInstruction,
    @Default([]) List<StudioPresetBlock> blocks,
  }) = _StudioPresetOverride;

  factory StudioPresetOverride.fromJson(Map<String, dynamic> json) =>
      _$StudioPresetOverrideFromJson(json);
}

@freezed
abstract class StudioPresetBlock with _$StudioPresetBlock {
  const factory StudioPresetBlock({
    required String id,
    @Default('') String title,
    @Default('custom_text') String kind,
    @Default('system') String role,
    @Default('') String content,
    @Default(true) bool enabled,
    @Default(0) int order,
  }) = _StudioPresetBlock;

  factory StudioPresetBlock.fromJson(Map<String, dynamic> json) =>
      _$StudioPresetBlockFromJson(json);
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
    @Default(8000) int maxTokens,
    @Default('') String sourceBlockNames,
  }) = _StudioAgent;

  factory StudioAgent.fromJson(Map<String, dynamic> json) =>
      _$StudioAgentFromJson(json);
}
