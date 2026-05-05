// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ChatMessageImpl _$$ChatMessageImplFromJson(Map<String, dynamic> json) =>
    _$ChatMessageImpl(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: (json['timestamp'] as num?)?.toInt(),
      personaId: json['personaId'] as String?,
      personaName: json['personaName'] as String?,
      imagePath: json['imagePath'] as String?,
      swipes:
          (json['swipes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      swipeId: (json['swipeId'] as num?)?.toInt() ?? 0,
      reasoning: json['reasoning'] as String?,
    );

Map<String, dynamic> _$$ChatMessageImplToJson(_$ChatMessageImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'role': instance.role,
      'content': instance.content,
      'timestamp': instance.timestamp,
      'personaId': instance.personaId,
      'personaName': instance.personaName,
      'imagePath': instance.imagePath,
      'swipes': instance.swipes,
      'swipeId': instance.swipeId,
      'reasoning': instance.reasoning,
    };

_$ChatSessionImpl _$$ChatSessionImplFromJson(Map<String, dynamic> json) =>
    _$ChatSessionImpl(
      id: json['id'] as String,
      characterId: json['characterId'] as String,
      sessionIndex: (json['sessionIndex'] as num).toInt(),
      messages:
          (json['messages'] as List<dynamic>?)
              ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$ChatSessionImplToJson(_$ChatSessionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'characterId': instance.characterId,
      'sessionIndex': instance.sessionIndex,
      'messages': instance.messages,
      'updatedAt': instance.updatedAt,
    };
