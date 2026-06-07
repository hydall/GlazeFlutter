import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

class TriggeredEntry {
  final String id;
  final String name;
  final String lorebookName;
  final String lorebookId;
  final String source;

  const TriggeredEntry({
    required this.id,
    required this.name,
    this.lorebookName = '',
    this.lorebookId = '',
    this.source = 'keyword',
  });

  factory TriggeredEntry.fromJson(Map<String, dynamic> json) => TriggeredEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        lorebookName: json['lorebookName'] as String? ?? '',
        lorebookId: json['lorebookId'] as String? ?? '',
        source: json['source'] as String? ?? 'keyword',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lorebookName': lorebookName,
        'lorebookId': lorebookId,
        'source': source,
      };
}

@freezed
abstract class ChatMessage with _$ChatMessage {
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
    @Default(false) bool isAllReasoning,
    @Default(false) bool isHidden,
    @Default(false) bool isError,
    String? genTime,
    int? tokens,
    int? greetingIndex,
    @Default([]) List<String> contextRefs,
    @Default('none') String swipeDirection,
    @Default(false) bool isEditing,
    @Default(false) bool isTyping,
    String? guidanceText,
    @Default('GENERATION') String guidanceType,
    @Default([]) List<TriggeredEntry> triggeredLorebooks,
    @Default([]) List<TriggeredEntry> triggeredMemories,
    @Default([]) List<Map<String, dynamic>> swipesMeta,
    @Default({}) Map<String, dynamic> memoryCoverage,
    String? time,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}

@freezed
abstract class AuthorsNote with _$AuthorsNote {
  const factory AuthorsNote({
    @Default('') String content,
    @Default('system') String role,
    @Default('relative') String insertionMode,
    @Default(0) int depth,
    @Default(true) bool enabled,
  }) = _AuthorsNote;

  factory AuthorsNote.fromJson(Map<String, dynamic> json) =>
      _$AuthorsNoteFromJson(json);
}

@freezed
abstract class ChatSummary with _$ChatSummary {
  const factory ChatSummary({
    @Default('') String content,
    @Default('system') String role,
    @Default('relative') String insertionMode,
    @Default(4) int depth,
    @Default('Summary: ') String prefix,
  }) = _ChatSummary;

  factory ChatSummary.fromJson(Map<String, dynamic> json) =>
      _$ChatSummaryFromJson(json);
}

@freezed
abstract class ChatSession with _$ChatSession {
  const factory ChatSession({
    required String id,
    required String characterId,
    required int sessionIndex,
    @Default([]) List<ChatMessage> messages,
    @Default(0) int updatedAt,
    @Default({}) Map<String, String> sessionVars,
    AuthorsNote? authorsNote,
    ChatSummary? summary,
    String? draft,
    @Default({}) Map<String, dynamic> lastScrollAnchor,
  }) = _ChatSession;

  factory ChatSession.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionFromJson(json);
}

class SessionMetadata {
  final String sessionId;
  final String characterId;
  final int sessionIndex;
  final int updatedAt;
  final int messageCount;
  final String lastMessageContent;
  final int lastMessageTimestamp;
  final String? sessionName;

  const SessionMetadata({
    required this.sessionId,
    required this.characterId,
    required this.sessionIndex,
    required this.updatedAt,
    required this.messageCount,
    required this.lastMessageContent,
    required this.lastMessageTimestamp,
    this.sessionName,
  });
}

extension ChatSessionX on ChatSession {
  String get historyText => messages
      .where((m) => (m.role == 'user' || m.role == 'assistant') && !m.isHidden)
      .map((m) => m.content)
      .join('\n');
}
