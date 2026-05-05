// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'character.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CharacterImpl _$$CharacterImplFromJson(Map<String, dynamic> json) =>
    _$CharacterImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarPath: json['avatarPath'] as String?,
      description: json['description'] as String?,
      personality: json['personality'] as String?,
      scenario: json['scenario'] as String?,
      firstMes: json['firstMes'] as String?,
      mesExample: json['mesExample'] as String?,
      systemPrompt: json['systemPrompt'] as String?,
      postHistoryInstructions: json['postHistoryInstructions'] as String?,
      creator: json['creator'] as String?,
      creatorNotes: json['creatorNotes'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      alternateGreetings:
          (json['alternateGreetings'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      color: json['color'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$CharacterImplToJson(_$CharacterImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'avatarPath': instance.avatarPath,
      'description': instance.description,
      'personality': instance.personality,
      'scenario': instance.scenario,
      'firstMes': instance.firstMes,
      'mesExample': instance.mesExample,
      'systemPrompt': instance.systemPrompt,
      'postHistoryInstructions': instance.postHistoryInstructions,
      'creator': instance.creator,
      'creatorNotes': instance.creatorNotes,
      'tags': instance.tags,
      'alternateGreetings': instance.alternateGreetings,
      'color': instance.color,
      'updatedAt': instance.updatedAt,
    };
