import 'package:freezed_annotation/freezed_annotation.dart';

part 'api_config.freezed.dart';
part 'api_config.g.dart';

@freezed
class ApiConfig with _$ApiConfig {
  const factory ApiConfig({
    required String id,
    @Default('') String name,
    @Default('openai_compatible') String providerId,
    @Default('') String endpoint,
    @Default('') String apiKey,
    @Default('') String model,
    @Default('chat') String mode,
    @Default(8000) int maxTokens,
    @Default(32000) int contextSize,
    @Default(0.7) double temperature,
    @Default(0.9) double topP,
    @Default(true) bool stream,
    @Default('medium') String reasoningEffort,
    @Default(false) bool requestReasoning,
    String? reasoningTagStart,
    String? reasoningTagEnd,
    @Default(false) bool omitTemperature,
    @Default(false) bool omitTopP,
    @Default(false) bool omitReasoning,
    @Default(false) bool omitReasoningEffort,
    @Default(true) bool embeddingUseSame,
    @Default(false) bool embeddingEnabled,
    @Default('') String embeddingEndpoint,
    @Default('') String embeddingApiKey,
    @Default('') String embeddingModel,
    @Default(512) int embeddingMaxChunkTokens,
  }) = _ApiConfig;

  factory ApiConfig.fromJson(Map<String, dynamic> json) =>
      _$ApiConfigFromJson(json);
}
