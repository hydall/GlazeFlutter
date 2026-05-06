import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String role,
    required String content,
    int? timestamp,
    String? personaId,
    String? personaName,
    String? imagePath,
    @Default([]) List<String> swipes,
    @Default(0) int swipeId,
    String? reasoning,
    @Default(false) bool isHidden,
    @Default(false) bool isError,
    String? genTime,
    int? tokens,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}

@freezed
class ChatSession with _$ChatSession {
  const factory ChatSession({
    required String id,
    required String characterId,
    required int sessionIndex,
    @Default([]) List<ChatMessage> messages,
    @Default(0) int updatedAt,
    @Default({}) Map<String, String> sessionVars,
  }) = _ChatSession;

  factory ChatSession.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionFromJson(json);
}

extension ChatSessionX on ChatSession {
  String get historyText => messages
      .where((m) => m.role == 'user' || m.role == 'assistant')
      .map((m) => m.content)
      .join('\n');
}
