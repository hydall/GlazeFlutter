// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preset.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PresetBlockImpl _$$PresetBlockImplFromJson(Map<String, dynamic> json) =>
    _$PresetBlockImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      enabled: json['enabled'] as bool? ?? true,
      isStatic: json['isStatic'] as bool? ?? false,
      insertionMode: json['insertionMode'] as String? ?? 'relative',
      depth: (json['depth'] as num?)?.toInt(),
      prefix: json['prefix'] as String?,
      isStashed: json['isStashed'] as bool? ?? false,
    );

Map<String, dynamic> _$$PresetBlockImplToJson(_$PresetBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'role': instance.role,
      'content': instance.content,
      'enabled': instance.enabled,
      'isStatic': instance.isStatic,
      'insertionMode': instance.insertionMode,
      'depth': instance.depth,
      'prefix': instance.prefix,
      'isStashed': instance.isStashed,
    };

_$PresetRegexImpl _$$PresetRegexImplFromJson(Map<String, dynamic> json) =>
    _$PresetRegexImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      regex: json['regex'] as String,
      replacement: json['replacement'] as String? ?? '',
      trimOut: json['trimOut'] as String? ?? '',
      placement: (json['placement'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [1, 2],
      ephemerality: (json['ephemerality'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [1, 2],
      disabled: json['disabled'] as bool? ?? false,
      macroRules: json['macroRules'] as String? ?? '0',
      minDepth: (json['minDepth'] as num?)?.toInt(),
      maxDepth: (json['maxDepth'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$PresetRegexImplToJson(_$PresetRegexImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'regex': instance.regex,
      'replacement': instance.replacement,
      'trimOut': instance.trimOut,
      'placement': instance.placement,
      'ephemerality': instance.ephemerality,
      'disabled': instance.disabled,
      'macroRules': instance.macroRules,
      'minDepth': instance.minDepth,
      'maxDepth': instance.maxDepth,
    };

_$PresetImpl _$$PresetImplFromJson(Map<String, dynamic> json) => _$PresetImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      author: json['author'] as String?,
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((e) => PresetBlock.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      regexes: (json['regexes'] as List<dynamic>?)
              ?.map((e) => PresetRegex.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      reasoningStart: json['reasoningStart'] as String?,
      reasoningEnd: json['reasoningEnd'] as String?,
      guidedGenerationPrompt: json['guidedGenerationPrompt'] as String?,
      guidedImpersonationPrompt: json['guidedImpersonationPrompt'] as String?,
      summaryPrompt: json['summaryPrompt'] as String?,
      mergePrompts: json['mergePrompts'] as bool? ?? false,
      mergeRole: json['mergeRole'] as String? ?? 'system',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$PresetImplToJson(_$PresetImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'author': instance.author,
      'blocks': instance.blocks,
      'regexes': instance.regexes,
      'reasoningEnabled': instance.reasoningEnabled,
      'reasoningStart': instance.reasoningStart,
      'reasoningEnd': instance.reasoningEnd,
      'guidedGenerationPrompt': instance.guidedGenerationPrompt,
      'guidedImpersonationPrompt': instance.guidedImpersonationPrompt,
      'summaryPrompt': instance.summaryPrompt,
      'mergePrompts': instance.mergePrompts,
      'mergeRole': instance.mergeRole,
      'createdAt': instance.createdAt,
    };
