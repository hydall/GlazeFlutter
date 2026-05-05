import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/chat_message.dart';

class ChatRepo {
  final AppDatabase _db;
  ChatRepo(this._db);

  Future<List<ChatSession>> getByCharacterId(String charId) async {
    final rows = await (_db.select(_db.chatSessions)
          ..where((t) => t.characterId.equals(charId)))
        .get();
    return rows.map(_toModel).toList();
  }

  Future<ChatSession?> getById(String sessionId) async {
    final row = await (_db.select(_db.chatSessions)
          ..where((t) => t.sessionId.equals(sessionId)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<void> put(ChatSession session) async {
    await _db.into(_db.chatSessions).insertOnConflictUpdate(_toCompanion(session));
  }

  Future<void> delete(String sessionId) async {
    await (_db.delete(_db.chatSessions)..where((t) => t.sessionId.equals(sessionId))).go();
  }

  ChatSession _toModel(ChatSessionRow c) => ChatSession(
        id: c.sessionId,
        characterId: c.characterId,
        sessionIndex: c.sessionIndex,
        messages: (jsonDecode(c.messagesJson) as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: c.updatedAt,
      );

  ChatSessionsCompanion _toCompanion(ChatSession m) => ChatSessionsCompanion(
        sessionId: Value(m.id),
        characterId: Value(m.characterId),
        sessionIndex: Value(m.sessionIndex),
        messagesJson: Value(jsonEncode(m.messages.map((e) => e.toJson()).toList())),
        updatedAt: Value(m.updatedAt),
      );
}
