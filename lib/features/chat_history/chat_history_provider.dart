import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/repositories/character_repo.dart' show CharacterRepo;
import '../../core/models/chat_message.dart';
import '../../core/state/character_provider.dart'
    show revealHiddenCharactersProvider;
import '../../core/state/db_provider.dart';
import '../../core/utils/sync_deletion_tracker.dart';
import '../../shared/utils/time_formatter.dart';
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

  /// Mirrors [revealHiddenCharactersProvider]: while false, sessions belonging
  /// to hidden characters are dropped from the history list. Watched in
  /// [build] so toggling reveal rebuilds the list.
  bool _revealHidden = false;

  @override
  Future<List<ChatSessionInfo>> build() async {
    _revealHidden = ref.watch(revealHiddenCharactersProvider);
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

    final result = <ChatSessionInfo>[];
    for (final m in allMeta) {
      final char = charMap[m.characterId];
      // Hidden characters take their chats with them: sessions drop out of the
      // history list while the character is hidden and reappear when it's
      // revealed (same gesture as the My Characters list). Orphan sessions
      // (no character row) are always kept.
      if (char != null && char.hidden && !_revealHidden) continue;
      final baseName = char?.displayName?.trim().isNotEmpty == true
          ? char!.displayName!.trim()
          : (char?.name ?? 'Unknown');
      // Variations are separate history groups; surface the variation name on
      // the chip as "Name — Variation" so they stay distinguishable.
      final variant = char?.variantName?.trim();
      final characterName = (variant != null && variant.isNotEmpty)
          ? '$baseName — $variant'
          : baseName;
      // While the origin event (branch/creation) is the most recent thing to
      // have happened, surface it as the preview and sort key so a freshly
      // branched or created chat rises to the top with a "Branched on …" /
      // "Created on …" line instead of a stale copied message.
      var lastMessage = m.lastMessageContent;
      var lastMessageTime = m.lastMessageTimestamp;
      if (m.originKind != null &&
          m.originTimestamp > 0 &&
          m.originTimestamp >= m.lastMessageTimestamp) {
        lastMessage = formatOriginPreview(m.originKind!, m.originTimestamp);
        lastMessageTime = m.originTimestamp;
      }
      result.add(ChatSessionInfo(
        sessionId: m.sessionId,
        characterId: m.characterId,
        characterName: characterName,
        avatarPath: char?.avatarPath,
        lastMessage: lastMessage,
        lastMessageTime: lastMessageTime,
        messageCount: m.messageCount,
        sessionIndex: m.sessionIndex,
        sessionName: m.sessionName,
      ));
    }

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
    final studioConfig = await ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    await ref.read(chatRepoProvider).delete(sessionId);
    await ref.read(memoryBookRepoProvider).deleteBySessionId(sessionId);
    await ref.read(trackerRepoProvider).clearForSession(sessionId);
    await ref.read(trackerSnapshotRepoProvider).deleteBySessionId(sessionId);
    await ref
        .read(ledgerReconciliationCheckpointRepoProvider)
        .deleteBySessionId(sessionId);
    await ref.read(studioConfigRepoProvider).deleteBySessionId(sessionId);
    ChatSessionService.clearCache();
    await SyncDeletionTracker.record('chat', sessionId);
    await SyncDeletionTracker.record('memory_book', sessionId);
    await SyncDeletionTracker.record('tracker_value', sessionId);
    await SyncDeletionTracker.record('tracker_snapshot', sessionId);
    final studioProfileId = studioConfig?.profileId ?? '';
    if (studioConfig != null &&
        (studioProfileId.isEmpty || studioProfileId == sessionId)) {
      await SyncDeletionTracker.record('studio_config', sessionId);
    }
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
    await ref
        .read(ledgerReconciliationCheckpointRepoProvider)
        .deleteBySessionId(sessionId);
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
