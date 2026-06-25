import 'package:freezed_annotation/freezed_annotation.dart';

part 'studio_config.freezed.dart';
part 'studio_config.g.dart';

/// Reusable Studio configuration profile.
///
/// Created when the user clicks "Build Studio" in the MagicDrawer Studio menu.
/// The LLM decomposes the active preset into agent tasks, each with its own
/// prompt shard and optional model override.
@freezed
abstract class StudioConfig with _$StudioConfig {
  const factory StudioConfig({
    /// Storage id. Older rows used the chat session id; profile rows use a
    /// stable Studio profile id and can be reused by many sessions.
    required String sessionId,
    @Default('') String profileId,
    @Default('') String profileName,
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
    @Default('') String builderPromptTemplate,

    /// Maximum number of trailing user/assistant chat messages forwarded to the
    /// FINAL Studio agent. Intermediate agents always see full history; the
    /// final writer is intentionally limited so it leans on the agent briefs
    /// instead of re-reading the whole transcript. 0 = no limit.
    @Default(15) int maxFinalHistoryMessages,
    /// How preset blocks are turned into agent instructions during
    /// decomposition. `'verbatim'` (default) = blocks are concatenated
    /// verbatim into the promptShard, no LLM call — the preset is the source
    /// of truth. `'compiled'` = LLM synthesizes a compiled instruction from
    /// the blocks (legacy behavior). See docs/PLAN_AGENTIC_STUDIO.md §11.
    @Default('verbatim') String routingMode,

    /// Verbatim content of "broadcast" preset blocks — cross-cutting rules
    /// (output language + prose-quality guards: anti-loop/echo/cliché/slop,
    /// banlists) that must govern not only their primary agent but also the
    /// POST-cleaner rewrite. Captured at build time so the POST-cleaner can
    /// apply the user's own rules verbatim without re-running any LLM. Each
    /// entry is one block's `[Block: name]\n<content>` text. See
    /// docs/PLAN_AGENTIC_STUDIO.md §11.
    @Default([]) List<String> broadcastBlocks,
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

    /// Controls whether an intermediate agent should be refreshed every turn
    /// or can reuse a previous brief. Supported values: static, scene, turn.
    /// Final agents always run every turn.
    @Default('turn') String refreshPolicy,
    @Default([]) List<String> invalidationSignals,
  }) = _StudioAgent;

  factory StudioAgent.fromJson(Map<String, dynamic> json) =>
      _$StudioAgentFromJson(json);
}
