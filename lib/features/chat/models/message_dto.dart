import 'package:freezed_annotation/freezed_annotation.dart';

part 'message_dto.freezed.dart';
part 'message_dto.g.dart';

@freezed
abstract class MessageDto with _$MessageDto {
  const factory MessageDto({
    required String id,
    required String role,
    required String text,
    int? timestamp,
    @Default(false) bool isUser,
    @Default(false) bool isAssistant,
    @Default(false) bool isSystem,
    String? personaName,
    String? imagePath,
    String? avatarColor,
    String? avatarLetter,
    String? genTime,
    int? tokens,
    int? swipeIndex,
    int? swipeTotal,
    @Default(false) bool isTyping,
    @Default(false) bool isError,
    @Default([]) List<TriggeredItemDto> triggeredLorebooks,
    @Default([]) List<TriggeredItemDto> triggeredMemories,
  }) = _MessageDto;

  factory MessageDto.fromJson(Map<String, dynamic> json) =>
      _$MessageDtoFromJson(json);
}

@freezed
abstract class TriggeredItemDto with _$TriggeredItemDto {
  const factory TriggeredItemDto({
    required String id,
    required String name,
    required String lorebookName,
    required String source,
  }) = _TriggeredItemDto;

  factory TriggeredItemDto.fromJson(Map<String, dynamic> json) =>
      _$TriggeredItemDtoFromJson(json);
}
