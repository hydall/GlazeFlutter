import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/repositories/character_repo.dart' show CharacterRepo;
import '../../core/models/chat_message.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/sync_deletion_tracker.dart';
import '../chat/chat_session_service.dart';

class ChatSessionInfo {
  final String sessionId;
  final String characterId;
  final String characterName;
  final String? avatarPath;
  final String lastMessage;
  final int lastMessageTime;
  final int messageCount;
  final int sessionIndex;
  final String? sessionName;

  const ChatSessionInfo({
    required this.sessionId,
    required this.characterId,
    required this.characterName,
    this.avatarPath,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.messageCount,
    required this.sessionIndex,
    this.sessionName,
  });
}

final chatHistoryProvider =
    AsyncNotifierProvider<ChatHistoryNotifier, List<ChatSessionInfo>>(
      ChatHistoryNotifier.new,
    );

class ChatHistoryNotifier extends AsyncNotifier<List<ChatSessionInfo>> {
  StreamSubscription<dynamic>? _sub;
  StreamSubscription<dynamic>? _charactersSub;
  List<ChatSessionInfo>? _lastResult;

  @override
  Future<List<ChatSessionInfo>> build() async {
    final chatRepo = ref.read(chatRepoProvider);
    final charRepo = ref.read(characterRepoProvider);
    await _sub?.cancel();
    await _charactersSub?.cancel();
    _sub = chatRepo.watchAllSessionMetadata().listen((allMeta) {
      _updateFromMetadata(allMeta, charRepo);
    });
    _charactersSub = charRepo.watchAll().listen((_) async {
      final allMeta = await chatRepo.getAllSessionMetadata();
      await _updateFromMetadata(allMeta, charRepo);
    });
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      unawaited(_charactersSub?.cancel());
    });

    final allMeta = await chatRepo.getAllSessionMetadata();
    return _buildFromMetadata(allMeta, charRepo);
  }

  Future<List<ChatSessionInfo>> _buildFromMetadata(
    List<SessionMetadata> allMeta,
    CharacterRepo charRepo,
  ) async {
    final charIds = allMeta.map((m) => m.characterId).toSet();
    final charMap = await charRepo.getByIds(charIds);

    final result = allMeta.map((m) {
      final char = charMap[m.characterId];
      final baseName = char?.displayName?.trim().isNotEmpty == true
          ? char!.displayName!.trim()
          : (char?.name ?? 'Unknown');
      // Variations are separate history groups; surface the variation name on
      // the chip as "Name — Variation" so they stay distinguishable.
      final variant = char?.variantName?.trim();
      final characterName = (variant != null && variant.isNotEmpty)
          ? '$baseName — $variant'
          : baseName;
      return ChatSessionInfo(
        sessionId: m.sessionId,
        characterId: m.characterId,
        characterName: characterName,
        avatarPath: char?.avatarPath,
        lastMessage: m.lastMessageContent,
        lastMessageTime: m.lastMessageTimestamp,
        messageCount: m.messageCount,
        sessionIndex: m.sessionIndex,
        sessionName: m.sessionName,
      );
    }).toList();

    result.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return result;
  }

  Future<void> _updateFromMetadata(
    List<SessionMetadata> allMeta,
    CharacterRepo charRepo,
  ) async {
    final data = await _buildFromMetadata(allMeta, charRepo);
    if (_lastResult != null &&
        _lastResult!.length == data.length &&
        _listEquals(_lastResult!, data)) {
      return;
    }
    _lastResult = data;
    state = AsyncData(data);
  }

  static bool _listEquals(List<ChatSessionInfo> a, List<ChatSessionInfo> b) {
    for (int i = 0; i < a.length; i++) {
      final ai = a[i], bi = b[i];
      if (ai.sessionId != bi.sessionId ||
          ai.characterName != bi.characterName ||
          ai.avatarPath != bi.avatarPath ||
          ai.lastMessageTime != bi.lastMessageTime ||
          ai.messageCount != bi.messageCount ||
          ai.lastMessage != bi.lastMessage ||
          ai.sessionName != bi.sessionName) {
        return false;
      }
    }
    return true;
  }

  Future<void> deleteSession(String sessionId) async {
    await ref.read(chatRepoProvider).delete(sessionId);
    await ref.read(memoryBookRepoProvider).deleteBySessionId(sessionId);
    await ref.read(trackerSnapshotRepoProvider).deleteBySessionId(sessionId);
    ChatSessionService.clearCache();
    await SyncDeletionTracker.record('chat', sessionId);
    await SyncDeletionTracker.record('memory_book', sessionId);
    await SyncDeletionTracker.record('tracker_snapshot', sessionId);
  }

  Future<void> clearChat(String sessionId) async {
    final chatRepo = ref.read(chatRepoProvider);
    final sessions = await chatRepo.getAllSessionMetadata();
    final meta = sessions.where((s) => s.sessionId == sessionId).firstOrNull;
    if (meta == null) return;

    final clearedSession = ChatSession(
      id: sessionId,
      characterId: meta.characterId,
      sessionIndex: meta.sessionIndex,
      messages: [],
    );
    await chatRepo.put(clearedSession);
    // Wipe tracker snapshots so stale state from before the clear does not
    // leak into the fresh chat.
    await ref.read(trackerSnapshotRepoProvider).deleteBySessionId(sessionId);
  }

  Future<void> renameSession(String sessionId, String newName) async {
    final chatRepo = ref.read(chatRepoProvider);
    final session = await chatRepo.getById(sessionId);
    if (session == null) return;
    final updatedVars = Map<String, String>.from(session.sessionVars);
    updatedVars['sessionName'] = newName;
    await chatRepo.put(session.copyWith(sessionVars: updatedVars));
    state = state.whenData(
      (sessions) => [
        for (final item in sessions)
          item.sessionId == sessionId
              ? ChatSessionInfo(
                  sessionId: item.sessionId,
                  characterId: item.characterId,
                  characterName: item.characterName,
                  avatarPath: item.avatarPath,
                  lastMessage: item.lastMessage,
                  lastMessageTime: item.lastMessageTime,
                  messageCount: item.messageCount,
                  sessionIndex: item.sessionIndex,
                  sessionName: newName,
                )
              : item,
      ],
    );
  }
}
