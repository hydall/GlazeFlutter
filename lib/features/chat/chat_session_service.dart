import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/persona.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/lorebook_provider.dart';
import '../../core/state/shared_prefs_provider.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import 'initial_message_builder.dart';

class ChatSessionService {
  final Ref _ref;

  static final int _maxCacheSize = 20;
  static final Map<String, ChatSession> _cache = {};
  static final List<String> _cacheAccessOrder = [];

  static int get cacheSize => _cache.length;

  ChatSessionService(this._ref);

  static void _touchCacheKey(String key) {
    _cacheAccessOrder.remove(key);
    _cacheAccessOrder.add(key);
    while (_cache.length > _maxCacheSize && _cacheAccessOrder.isNotEmpty) {
      final evict = _cacheAccessOrder.removeAt(0);
      _cache.remove(evict);
    }
  }

  static void updateCache(ChatSession session) {
    _cache[session.id] = session;
    _touchCacheKey(session.id);
  }

  static void clearCache({String? charId}) {
    if (charId == null) {
      _cache.clear();
      _cacheAccessOrder.clear();
    } else {
      final keysToRemove = _cache.keys
          .where((k) => k.startsWith('${charId}_'))
          .toList();
      for (final k in keysToRemove) {
        _cache.remove(k);
        _cacheAccessOrder.remove(k);
      }
    }
  }

  Future<ChatSession> createInitialSession(String charId) async {
    final repo = _ref.read(chatRepoProvider);
    final charRepo = _ref.read(characterRepoProvider);
    final personaRepo = _ref.read(personaRepoProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final connections = _ref.read(personaConnectionsProvider);
    final character = await charRepo.getById(charId);
    final personas = await personaRepo.getAll();
    final persona = getEffectivePersona(
      personas,
      charId,
      null,
      activePersonaId,
      connections,
    );

    final sessionId = '${charId}_0';
    final initialMessages = InitialMessageBuilder.build(
      character: character,
      persona: persona,
      sessionId: sessionId,
    );

    final session = ChatSession(
      id: sessionId,
      characterId: charId,
      sessionIndex: 0,
      messages: initialMessages,
    );
    await repo.put(session);
    return session;
  }

  Future<ChatSession?> findExistingSession(String charId) async {
    final charRepo = _ref.read(characterRepoProvider);
    final repo = _ref.read(chatRepoProvider);
    final character = await charRepo.getById(charId);
    final currentIdx = character?.currentSessionIndex ?? 0;

    final directId = '${charId}_$currentIdx';
    var session = await repo.getById(directId);
    if (session != null) return session;

    final sessions = await repo.getByCharacterId(charId);
    if (sessions.isEmpty) return null;
    return sessions.first;
  }

  Future<ChatSession> switchToSession(String charId, int sessionIndex) async {
    final cacheKey = '${charId}_$sessionIndex';

    final cached = _cache[cacheKey];
    if (cached != null) {
      _touchCacheKey(cacheKey);
      await saveCurrentSessionIndex(charId, sessionIndex);
      _prefetchAdjacent(charId, sessionIndex);
      return cached;
    }

    final repo = _ref.read(chatRepoProvider);
    final session = await repo.getById(cacheKey);
    if (session == null) {
      final sessions = await repo.getByCharacterId(charId);
      final target = sessions
          .where((s) => s.sessionIndex == sessionIndex)
          .firstOrNull;
      if (target == null) {
        throw StateError('Session $charId#$sessionIndex not found');
      }
      _cache[target.id] = target;
      _touchCacheKey(target.id);
      await saveCurrentSessionIndex(charId, sessionIndex);
      _prefetchAdjacent(charId, target.sessionIndex);
      return target;
    }

    _cache[cacheKey] = session;
    _touchCacheKey(cacheKey);
    await saveCurrentSessionIndex(charId, sessionIndex);
    _prefetchAdjacent(charId, sessionIndex);
    return session;
  }

  void _prefetchAdjacent(String charId, int currentIdx) {
    if (!_ref.mounted) return;
    final repo = _ref.read(chatRepoProvider);
    () async {
      try {
        final futures = <Future<void>>[];

        if (currentIdx > 0) {
          final prevKey = '${charId}_${currentIdx - 1}';
          if (!_cache.containsKey(prevKey)) {
            futures.add(
              repo.getById(prevKey).then((s) {
                if (s != null) {
                  _cache[prevKey] = s;
                  _touchCacheKey(prevKey);
                }
              }),
            );
          }
        }

        final nextKey = '${charId}_${currentIdx + 1}';
        if (!_cache.containsKey(nextKey)) {
          futures.add(
            repo.getById(nextKey).then((s) {
              if (s != null) {
                _cache[nextKey] = s;
                _touchCacheKey(nextKey);
              }
            }),
          );
        }

        if (futures.isNotEmpty) await Future.wait(futures);
      } catch (e) {
        debugPrint('[ChatSessionService] _prefetchAdjacent error: $e');
      }
    }();
  }

  Future<ChatSession> createNewSession(String charId) async {
    final repo = _ref.read(chatRepoProvider);
    final charRepo = _ref.read(characterRepoProvider);
    final personaRepo = _ref.read(personaRepoProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final connections = _ref.read(personaConnectionsProvider);
    final nextIndex = await _nextSessionIndex(charId);
    final character = await charRepo.getById(charId);
    final personas = await personaRepo.getAll();
    final persona = getEffectivePersona(
      personas,
      charId,
      null,
      activePersonaId,
      connections,
    );
    final sessionId = '${charId}_$nextIndex';
    final initialMessages = InitialMessageBuilder.build(
      character: character,
      persona: persona,
      sessionId: sessionId,
    );
    final session = ChatSession(
      id: sessionId,
      characterId: charId,
      sessionIndex: nextIndex,
      messages: initialMessages,
      // Stamp creation time so the new chat carries a real "last activity"
      // date for the session list (display + sorting) instead of 0.
      updatedAt: currentTimestampSeconds(),
    );
    await repo.put(session);
    await saveCurrentSessionIndex(charId, nextIndex);
    return session;
  }

  Future<ChatSession> branchSession(
    String charId,
    ChatSession current,
    int messageIndex,
  ) async {
    final repo = _ref.read(chatRepoProvider);
    final nextIndex = await _nextSessionIndex(charId);
    final session = ChatSession(
      id: '${charId}_$nextIndex',
      characterId: charId,
      sessionIndex: nextIndex,
      messages: current.messages.sublist(0, messageIndex + 1),
      // Stamp the branch time (ms, to match message timestamps) so the WebView
      // can render a "Branched on …" separator at the top of the new session.
      // Overrides any inherited marker from the parent — this is the new
      // session's own branch point.
      sessionVars: {
        ...current.sessionVars,
        'branchedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      },
      // Carry the chat-scoped author's note and summary into the branch —
      // both are session state that the user set for this conversation and
      // expects to continue in the fork.
      authorsNote: current.authorsNote,
      summary: current.summary,
      updatedAt: currentTimestampSeconds(),
    );
    await repo.put(session);
    // Carry chat-scoped connections (persona / preset / lorebook activations)
    // keyed by the parent session id onto the new session id. Without this the
    // branch loses its bound persona, preset and enabled lorebooks and silently
    // falls back to character/global defaults.
    _copyChatConnections(fromSessionId: current.id, toSessionId: session.id);
    await _ref
        .read(memoryBookRepoProvider)
        .copyForSessionBranch(
          fromSessionId: current.id,
          toSessionId: session.id,
        );
    await _ref
        .read(studioConfigRepoProvider)
        .copyForSessionBranch(
          fromSessionId: current.id,
          toSessionId: session.id,
        );
    // Copy tracker snapshots for the sliced message range into the new
    // sessionId. Messages are not re-id'd on branch, so the sessionId prefix
    // in the snapshot PK isolates each branch's rows (no cross-session
    // aliasing). Without this, a branched session would lose all tracker
    // provenance — the read path (getLatestCommitted) would find no snapshots
    // and fall back to an empty tracker list.
    final branchedMessageIds = session.messages.map((m) => m.id).toSet();
    await _ref
        .read(trackerSnapshotRepoProvider)
        .copyForSessionBranch(
          fromSessionId: current.id,
          toSessionId: session.id,
          messageIds: branchedMessageIds,
        );
    await _ref
        .read(characterKnowledgeFactRepoProvider)
        .copyForSessionBranch(
          fromSessionId: current.id,
          toSessionId: session.id,
          messageIds: branchedMessageIds,
        );
    await _ref
        .read(ledgerReconciliationCheckpointRepoProvider)
        .copyForSessionBranch(
          fromSessionId: current.id,
          toSessionId: session.id,
          messageIds: branchedMessageIds,
        );
    await saveCurrentSessionIndex(charId, nextIndex);
    return session;
  }

  /// Copies the chat-scoped connection bindings from [fromSessionId] to
  /// [toSessionId]: the bound persona, preset and enabled lorebooks. Each is
  /// keyed by session id, so a fresh branch id starts unbound unless we
  /// duplicate the parent's entries here. No-op for any binding the parent
  /// session did not have.
  void _copyChatConnections({
    required String fromSessionId,
    required String toSessionId,
  }) {
    final personaId = _ref
        .read(personaConnectionsProvider)
        .chat[fromSessionId];
    if (personaId != null) {
      setPersonaConnectionRef(_ref, 'chat', toSessionId, personaId);
    }

    final presetId = _ref.read(presetConnectionsProvider).chat[fromSessionId];
    if (presetId != null) {
      setPresetConnectionRef(_ref, 'chat', toSessionId, presetId);
    }

    final activations = _ref.read(lorebookActivationsProvider);
    final lorebookIds = activations.chat[fromSessionId];
    if (lorebookIds != null && lorebookIds.isNotEmpty) {
      final chatMap = Map<String, List<String>>.from(activations.chat);
      chatMap[toSessionId] = List<String>.from(lorebookIds);
      final updated = activations.copyWith(chat: chatMap);
      _ref.read(lorebookActivationsProvider.notifier).state = updated;
      saveLorebookActivations(
        updated,
        _ref.read(sharedPreferencesProvider).value,
      );
    }
  }

  Future<ChatSession> clearChat(String charId, ChatSession session) async {
    final charRepo = _ref.read(characterRepoProvider);
    final personaRepo = _ref.read(personaRepoProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final connections = _ref.read(personaConnectionsProvider);
    final character = await charRepo.getById(charId);
    final personas = await personaRepo.getAll();
    final persona = getEffectivePersona(
      personas,
      charId,
      null,
      activePersonaId,
      connections,
    );
    final initialMessages = InitialMessageBuilder.build(
      character: character,
      persona: persona,
      sessionId: session.id,
    );
    // Drop the branch stamp so a cleared session reads as freshly created
    // ("Created on …" from the new greeting) rather than keeping a stale
    // "Branched on …" marker.
    final clearedVars = Map<String, String>.from(session.sessionVars)
      ..remove('branchedAt');
    final clearedSession = session.copyWith(
      messages: initialMessages,
      sessionVars: clearedVars,
    );
    await _ref.read(chatRepoProvider).put(clearedSession);
    // Wipe tracker snapshots so stale state from before the clear does not
    // leak into the fresh chat.
    await _ref.read(trackerSnapshotRepoProvider).deleteBySessionId(session.id);
    await _ref
        .read(characterKnowledgeFactRepoProvider)
        .deleteBySessionId(session.id);
    await _ref
        .read(ledgerReconciliationCheckpointRepoProvider)
        .deleteBySessionId(session.id);
    // Also wipe the live `tracker_rows` store. Without this, the UI
    // ("Tracker values" tab) falls back to
    // `trackerRepo.getBySessionId` when no snapshot is found and shows the
    // pre-clear trackers. Both stores are session-scoped and must be cleared
    // together.
    await _ref.read(trackerRepoProvider).clearForSession(session.id);
    updateCache(clearedSession);
    return clearedSession;
  }

  Future<List<ChatSession>> getSessions(String charId) async {
    final repo = _ref.read(chatRepoProvider);
    return repo.getByCharacterId(charId);
  }

  Future<Persona?> resolvePersona(String charId) async {
    final personaRepo = _ref.read(personaRepoProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final connections = _ref.read(personaConnectionsProvider);
    final personas = await personaRepo.getAll();
    return getEffectivePersona(
      personas,
      charId,
      null,
      activePersonaId,
      connections,
    );
  }

  Future<void> saveCurrentSessionIndex(String charId, int index) async {
    if (!_ref.mounted) return;
    final charRepo = _ref.read(characterRepoProvider);
    try {
      final character = await charRepo.getById(charId);
      if (character != null) {
        await charRepo.put(character.copyWith(currentSessionIndex: index));
      }
    } catch (e) {
      debugPrint('[ChatSessionService] saveCurrentSessionIndex error: $e');
    }
  }

  Future<int> _nextSessionIndex(String charId) async {
    final repo = _ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(charId);
    if (sessions.isEmpty) return 0;
    return sessions.map((s) => s.sessionIndex).reduce((a, b) => a > b ? a : b) +
        1;
  }
}
