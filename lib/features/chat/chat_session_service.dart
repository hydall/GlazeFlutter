import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/persona.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import 'initial_message_builder.dart';

class ChatSessionService {
  final Ref _ref;

  ChatSessionService(this._ref);

  Future<ChatSession> createInitialSession(String charId) async {
    final repo = _ref.read(chatRepoProvider);
    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);
    final persona = await resolvePersona(charId);

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
    final repo = _ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(charId);
    if (sessions.isEmpty) return null;

    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);
    final currentIdx = character?.currentSessionIndex ?? 0;
    return sessions.where((s) => s.sessionIndex == currentIdx).firstOrNull ?? sessions.first;
  }

  Future<ChatSession> switchToSession(String charId, int sessionIndex) async {
    final repo = _ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(charId);
    final target = sessions.where((s) => s.sessionIndex == sessionIndex).firstOrNull;
    if (target != null) {
      await saveCurrentSessionIndex(charId, sessionIndex);
    }
    return target!;
  }

  Future<ChatSession> createNewSession(String charId) async {
    final repo = _ref.read(chatRepoProvider);
    final nextIndex = await _nextSessionIndex(charId);
    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);
    final persona = await resolvePersona(charId);
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
    );
    await repo.put(session);
    await saveCurrentSessionIndex(charId, nextIndex);
    return session;
  }

  Future<ChatSession> branchSession(String charId, ChatSession current, int messageIndex) async {
    final repo = _ref.read(chatRepoProvider);
    final nextIndex = await _nextSessionIndex(charId);
    final session = ChatSession(
      id: '${charId}_$nextIndex',
      characterId: charId,
      sessionIndex: nextIndex,
      messages: current.messages.sublist(0, messageIndex + 1),
      sessionVars: current.sessionVars,
      updatedAt: currentTimestampSeconds(),
    );
    await repo.put(session);
    await saveCurrentSessionIndex(charId, nextIndex);
    return session;
  }

  Future<ChatSession> clearChat(String charId, ChatSession session) async {
    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);
    final persona = await resolvePersona(charId);
    final initialMessages = InitialMessageBuilder.build(
      character: character,
      persona: persona,
      sessionId: session.id,
    );
    final clearedSession = session.copyWith(messages: initialMessages);
    await _ref.read(chatRepoProvider).put(clearedSession);
    return clearedSession;
  }

  Future<List<ChatSession>> getSessions(String charId) async {
    final repo = _ref.read(chatRepoProvider);
    return repo.getByCharacterId(charId);
  }

  Future<Persona?> resolvePersona(String charId) async {
    final personaRepo = _ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final connections = _ref.read(personaConnectionsProvider);
    return getEffectivePersona(personas, charId, null, activePersonaId, connections);
  }

  Future<void> saveCurrentSessionIndex(String charId, int index) async {
    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);
    if (character != null) {
      await charRepo.put(character.copyWith(currentSessionIndex: index));
    }
  }

  Future<int> _nextSessionIndex(String charId) async {
    final repo = _ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(charId);
    if (sessions.isEmpty) return 0;
    return sessions.map((s) => s.sessionIndex).reduce((a, b) => a > b ? a : b) + 1;
  }
}
