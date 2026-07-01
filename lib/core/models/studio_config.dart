import 'package:flutter/foundation.dart';
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
    @Default('') String buildModelOverride,
    @Default('') String runModelOverride,
    @Default('') String builderPromptTemplate,

    /// Maximum number of trailing user/assistant chat messages forwarded to the
    /// FINAL Studio agent (the generator). Trackers (intermediate agents) are
    /// trimmed per their own [StudioAgent.contextSize]. The final writer leans
    /// on the tracker briefs instead of re-reading the whole transcript.
    /// 0 = no limit.
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

/// One structured block inside an agent's [StudioAgent.promptShard].
///
/// At build time, `_synthesizeRoutedShard` produces one [PromptShardBlock] per
/// assigned preset block (preserving `blockName` / `blockId` / `role`), so
/// `buildAgentMessages` can emit each block as a SEPARATE API system message
/// instead of one concatenated blob. This gives the provider's prompt cache a
/// long stable prefix (char_card / persona / scenario never change between
/// turns; only the last volatile block invalidates) and lets the LLM navigate
/// the shard structure. See docs/plans/PLAN_STUDIO_SHARD_BLOCKS.md.
@freezed
abstract class PromptShardBlock with _$PromptShardBlock {
  const factory PromptShardBlock({
    @Default('system') String role,
    @Default('') String content,
    @Default('') String blockName,
    @Default('') String blockId,
  }) = _PromptShardBlock;

  factory PromptShardBlock.fromJson(Map<String, dynamic> json) =>
      _$PromptShardBlockFromJson(json);
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
    @Default('pregen') String section,
  }) = _StudioPresetBlock;

  factory StudioPresetBlock.fromJson(Map<String, dynamic> json) =>
      _$StudioPresetBlockFromJson(json);
}

/// A complete Studio preset: a flat list of [StudioPresetBlock]s grouped by
/// `section` (`pregen`, `final`, `cleaner`, `ledger`, `writeloop`, `build`,
/// `brief_parser`). Stored in `studio_preset_rows` as a JSON blob.
@freezed
abstract class StudioPreset with _$StudioPreset {
  const factory StudioPreset({
    required String id,
    @Default('') String name,
    @Default([]) List<StudioPresetBlock> blocks,
    @Default(0) int updatedAt,
  }) = _StudioPreset;

  factory StudioPreset.fromJson(Map<String, dynamic> json) =>
      _$StudioPresetFromJson(json);
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
    @Default([]) List<PromptShardBlock> promptShard,
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

    /// Number of trailing chat messages forwarded to this tracker (intermediate
    /// agent). Default 5 (Marinara DEFAULT_AGENT_CONTEXT_SIZE). Hard-capped at
    /// 200 (MAX_AGENT_CONTEXT_MESSAGES) on normalization. The final agent
    /// (generator) ignores this and uses [StudioConfig.maxFinalHistoryMessages]
    /// instead. 0 = no limit (not recommended for trackers).
    @Default(5) int contextSize,

    /// How often this tracker runs, in assistant turns. 1 = every turn
    /// (default), 3 = every 3rd turn, etc. Useful for "director"-style
    /// trackers whose guidance changes slowly. The final agent (generator)
    /// always runs every turn regardless of this field.
    ///
    /// Port of Marinara `AgentSettings.runInterval`. We do not keep
    /// `BUILT_IN_AGENT_RUN_INTERVAL_DEFAULTS` (Marinara's per-type defaults)
    /// because GlazeFlutter trackers are arbitrary user-defined agents, not
    /// built-in typed controllers. Default 1 = run every turn.
    @Default(1) int runInterval,

    /// Maximum number of parallel jobs this agent can be split into inside a
    /// batch group (Marinara `AgentSettings.maxParallelJobs`, clamped to
    /// `[1, 16]` on use). For MVP this is effectively always 1 — one batch
    /// group = one LLM request — but the field is kept so the model can grow
    /// later without a migration. See docs/PLAN_AGENTIC_STUDIO.md Phase 5.7.3.
    @Default(1) int maxParallelJobs,

    /// Force this tracker to run as its own individual LLM request, never
    /// batched with others. Set heuristically for "heavy" trackers whose large
    /// private extras must not leak into other trackers' batch prompt
    /// (Marinara `shouldRunAgentIndividually`). Default false.
    ///
    /// Heuristic: [MemoryStudioService._shouldRunIndividually] sets this
    /// implicitly for trackers whose name matches `expression` /
    /// `illustrator` / `lorebook` patterns, even when this field is false,
    /// for forward compatibility with existing configs.
    @Default(false) bool runIndividually,

    /// Optional keyword-activation gate for this tracker. When non-empty,
    /// the tracker activates ONLY on turns where at least one of these
    /// keywords appears in the last [activationScanDepth] chat messages
    /// (case-insensitive, whole-word-optional substring match). When empty
    /// (the default), the tracker always activates (subject to
    /// [runInterval] and [enabled]).
    ///
    /// Port of Marinara `agent-activation.ts:matchCustomAgentActivation`.
    /// Use case: a "weather tracker" that should only run when weather is
    /// mentioned in the recent chat, not on every turn; a "combat tracker"
    /// that activates only on fight scenes. Combined with `runInterval`
    /// (turn-count gate) for two-layer gating.
    @Default([]) List<String> activationKeywords,
    /// Number of trailing chat messages scanned for [activationKeywords].
    /// Default 5 (matches `DEFAULT_AGENT_CONTEXT_SIZE`). 0 = scan the
    /// entire available history (not recommended — expensive and stale).
    @Default(5) int activationScanDepth,

    /// Which phase this agent runs in. `pre_generation` (default) = runs
    /// before the final generator, produces a brief that feeds into the
    /// generator's prompt. `post_processing` = runs after the generator
    /// produces its response, receives the response as `mainResponse`, and
    /// can produce an edited/rewritten version. Port of Marinara
    /// `AgentPhase`. The final generator (last enabled agent with
    /// `phase: 'pre_generation'`) always runs. Post-processing agents run
    /// after, in their own batch group (the `postProcessingDataKey` —
    /// pre-gen and post-gen agents on the same `(provider, model)` do NOT
    /// batch together, because the post-gen one needs `mainResponse` in
    /// its context). See docs/PLAN_AGENTIC_STUDIO.md §5.7.1 + Feature 6.
    @Default('pre_generation') String phase,
  }) = _StudioAgent;

  factory StudioAgent.fromJson(Map<String, dynamic> json) =>
      _$StudioAgentFromJson(json);

  /// Forces certain agent types to a specific phase regardless of user
  /// config. Port of Marinara `normalizeAgentPhaseForType`. Currently a
  /// no-op stub: GlazeFlutter agents are arbitrary user-defined (no
  /// built-in typed controllers like Marinara's `prose-guardian` /
  /// `continuity`), so the user's configured [configuredPhase] is always
  /// respected. When built-in typed agents are added in the future, this
  /// is where `prose-guardian` and `continuity` would be forced to
  /// `post_processing`. Kept as a named, documented seam so the future
  /// change is localized to this method.
  static String normalizeAgentPhaseForType(
    String agentId,
    String configuredPhase,
  ) {
    return configuredPhase;
  }
}
