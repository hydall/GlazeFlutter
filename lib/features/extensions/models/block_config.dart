import 'package:freezed_annotation/freezed_annotation.dart';

part 'block_config.freezed.dart';
part 'block_config.g.dart';

enum BlockType {
  infoblock,
  imageGen,
  jsRunner,
  interactive,
}

enum BlockTrigger {
  afterUser,
  afterAssistant,
  periodic,
}

@freezed
class BlockConfig with _$BlockConfig {
  const factory BlockConfig({
    required String id,
    required String name,
    @Default(BlockType.infoblock) BlockType type,
    @Default(true) bool enabled,
    @Default(BlockTrigger.afterAssistant) BlockTrigger trigger,
    @Default('') String prompt,
    @Default(0) int order,
    @Default(false) bool dependsOnPrevious,
    @Default(true) bool inject,
    @Default(1) int injectLastN,
    /// Optional text inserted after `\\n\\n` and before the injected block body
    /// in main chat history (e.g. a note that the block is reference-only).
    @Default('') String injectPrefix,
    @Default('') String apiConfigId,
    @Default('') String model,
    /// When true, LLM output is pushed to the ext-blocks panel incrementally
    /// during generation (infoblock + image agent steps).
    @Default(false) bool streamToPanel,
    // Image-specific
    @Default('') String imagePromptInstruction,
    @Default(true) bool imageGenEnabled,
    // Context control (Phase 9)
    /// Number of recent messages to include as context for this block,
    /// counted backward from the message the block is attached to (inclusive).
    /// 0 = only character card + system prompt, -1 = entire history up to anchor.
    @Default(10) int contextMessageCount,
    /// Additional system text prepended before chat history.
    /// Supports macros: {{char}}, {{user}}, {{description}}, {{personality}}.
    @Default('') String contextSystemPrompt,
    // JS Runner (Phase 10)
    /// Legacy static script (used only when [prompt] is empty). Prefer LLM prompt.
    @Default('') String script,
    // Template (upstream parity)
    /// XML-like skeleton that defines the block's shape. Sent to the LLM as
    /// part of the system message so the model knows the exact tag layout to
    /// output. Supports `{{name}}` macro (substituted with [name] at runtime).
    /// When non-empty, the LLM response is also extracted by parsing this
    /// template's tag pair out of the raw reply.
    @Default('<{{name}}>\n\n</{{name}}>') String template,
    // Periodic trigger (Phase 11)
    /// Number of seconds between runs when [trigger] is
    /// [BlockTrigger.periodic]. The block's JS script is executed in the
    /// headless engine every `periodicIntervalSeconds` seconds while
    /// extensions are enabled. Ignored for other trigger types.
    @Default(60) int periodicIntervalSeconds,
  }) = _BlockConfig;

  factory BlockConfig.fromJson(Map<String, dynamic> json) =>
      _$BlockConfigFromJson(json);
}
