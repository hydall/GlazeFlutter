import 'package:freezed_annotation/freezed_annotation.dart';

part 'block_config.freezed.dart';
part 'block_config.g.dart';

enum BlockType {
  infoblock,
  imageGen,
  jsRunner,
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
    @Default('') String apiConfigId,
    @Default('') String model,
    // Image-specific
    @Default('') String imagePromptInstruction,
    @Default(true) bool imageGenEnabled,
  }) = _BlockConfig;

  factory BlockConfig.fromJson(Map<String, dynamic> json) =>
      _$BlockConfigFromJson(json);
}
