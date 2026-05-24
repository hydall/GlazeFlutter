import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:glaze_flutter/core/models/chat_message.dart';

part 'chat_message_mapper.freezed.dart';

@freezed
sealed class ChatMessageMapperContext with _$ChatMessageMapperContext {
  const factory ChatMessageMapperContext({
    String? currentCharName,
    String? currentCharColor,
    String? currentPersonaName,
    String? charAvatarDataUrl,
    String? personaAvatarDataUrl,
    required bool isGenerating,
    @Default({}) Set<String> coveredMemoryIds,
    @Default({}) Set<String> pendingMemoryIds,
    @Default({}) Set<String> draftMemoryIds,
  }) = _ChatMessageMapperContext;
}

class ChatMessageMapper {
  static const _imgResultRegex = r'\[IMG:RESULT:(.*?)\]';

  static Map<String, dynamic> toMap(
    ChatMessage m,
    ChatMessageMapperContext ctx, {
    bool isLast = false,
    int? messageIndex,
    bool isStreamingUpdate = false,
  }) {
    final isAssistant = m.role == 'assistant' || m.role == 'character';
    final isUser = m.role == 'user';

    String? displayName;
    String? avatarColor;
    String? avatarUrl;

    if (isAssistant) {
      displayName = ctx.currentCharName ?? m.personaName ?? 'Character';
      avatarColor = ctx.currentCharColor;
      if (!isStreamingUpdate) avatarUrl = ctx.charAvatarDataUrl;
    } else if (isUser) {
      displayName = m.personaName ?? ctx.currentPersonaName ?? 'You';
      if (!isStreamingUpdate) avatarUrl = ctx.personaAvatarDataUrl;
    } else {
      displayName = m.personaName ?? 'System';
    }

    String? memoryStatus;
    if (m.memoryCoverage.isNotEmpty) {
      final needsRebuild = m.memoryCoverage['needsRebuild'] as bool? ?? false;
      final stale = m.memoryCoverage['stale'] as bool? ?? false;
      if (needsRebuild) {
        memoryStatus = 'REBUILD';
      } else if (stale) {
        memoryStatus = 'STALE';
      }
    }
    if (memoryStatus == null && ctx.coveredMemoryIds.contains(m.id)) {
      memoryStatus = 'MEM';
    }
    if (memoryStatus == null && ctx.pendingMemoryIds.contains(m.id)) {
      memoryStatus = 'PENDING';
    }
    if (memoryStatus == null && ctx.draftMemoryIds.contains(m.id)) {
      memoryStatus = 'DRAFT';
    }

    return {
      'id': m.id,
      'role': m.role,
      'text': m.content,
      'timestamp': m.timestamp,
      'isUser': isUser,
      'isAssistant': isAssistant,
      'isSystem': m.role == 'system',
      'displayName': displayName,
      if (avatarColor != null) 'avatarColor': avatarColor,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (m.imagePath != null) 'imagePath': m.imagePath,
      if (m.personaName != null) 'personaName': m.personaName,
      if (m.swipes.isNotEmpty) 'swipeIndex': m.swipeId,
      if (m.swipes.isNotEmpty) 'swipeTotal': m.swipes.length,
      if (m.genTime != null) 'genTime': m.genTime,
      if (m.tokens != null) 'tokens': m.tokens,
      'isError': m.isError,
      if (m.isTyping) 'isTyping': true,
      if (m.reasoning != null && m.reasoning!.isNotEmpty) 'reasoning': m.reasoning,
      if (m.isHidden) 'isHidden': true,
      if (isLast) 'isLast': true,
      if (messageIndex != null) 'messageIndex': messageIndex,
      if (m.guidanceText != null && m.guidanceText!.isNotEmpty) 'guidanceText': m.guidanceText,
      if (m.guidanceType != 'GENERATION') 'guidanceType': m.guidanceType,
      if (m.greetingIndex != null) 'greetingIndex': m.greetingIndex,
      if (memoryStatus != null) 'memoryStatus': memoryStatus,
      if (m.triggeredLorebooks.isNotEmpty) 'triggeredLorebooks': m.triggeredLorebooks.map((e) => e.toJson()).toList(),
      if (m.triggeredMemories.isNotEmpty) 'triggeredMemories': m.triggeredMemories.map((e) => e.toJson()).toList(),
      'isGenerating': ctx.isGenerating,
    };
  }
}
