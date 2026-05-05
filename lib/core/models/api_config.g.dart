// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ApiConfigImpl _$$ApiConfigImplFromJson(Map<String, dynamic> json) =>
    _$ApiConfigImpl(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      providerId: json['providerId'] as String? ?? 'openai_compatible',
      endpoint: json['endpoint'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 8000,
      contextSize: (json['contextSize'] as num?)?.toInt() ?? 32000,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
      stream: json['stream'] as bool? ?? true,
      reasoningEffort: json['reasoningEffort'] as String? ?? 'medium',
      requestReasoning: json['requestReasoning'] as bool? ?? false,
      reasoningTagStart: json['reasoningTagStart'] as String?,
      reasoningTagEnd: json['reasoningTagEnd'] as String?,
    );

Map<String, dynamic> _$$ApiConfigImplToJson(_$ApiConfigImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'providerId': instance.providerId,
      'endpoint': instance.endpoint,
      'apiKey': instance.apiKey,
      'model': instance.model,
      'maxTokens': instance.maxTokens,
      'contextSize': instance.contextSize,
      'temperature': instance.temperature,
      'topP': instance.topP,
      'stream': instance.stream,
      'reasoningEffort': instance.reasoningEffort,
      'requestReasoning': instance.requestReasoning,
      'reasoningTagStart': instance.reasoningTagStart,
      'reasoningTagEnd': instance.reasoningTagEnd,
    };
