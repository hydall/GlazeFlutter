import 'package:freezed_annotation/freezed_annotation.dart';

part 'api_config.freezed.dart';
part 'api_config.g.dart';

@freezed
abstract class ApiConfig with _$ApiConfig {
  const factory ApiConfig({
    required String id,
    @Default('') String name,
    @Default('openai_compatible') String providerId,
    @Default('openai') String protocol,
    @Default('') String endpoint,
    @Default('') String apiKey,
    @Default('') String model,
    @Default('chat') String mode,
    @Default(8000) int maxTokens,
    @Default(32000) int contextSize,
    @Default(0.7) double temperature,
    @Default(0.9) double topP,
    @Default(0) int topK,
    @Default(0.0) double frequencyPenalty,
    @Default(0.0) double presencePenalty,
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
    @Default('off') String cacheControlTtl,
    @Default('depth') String cacheBreakpointMode,
    @Default('openrouter') String sessionIdMode,
    @Default(60000) int firstChunkTimeoutMs,
  }) = _ApiConfig;

  factory ApiConfig.fromJson(Map<String, dynamic> json) =>
      _$ApiConfigFromJson(json);
}
