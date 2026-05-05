import 'dart:convert';
import 'package:isar/isar.dart';
import '../collections.dart';
import '../../models/chat_message.dart';

class ChatRepo {
  final Isar _db;
  ChatRepo(this._db);

  Future<List<ChatSession>> getByCharacterId(String charId) async {
    final items = await _db.chatSessionCollections
        .where()
        .filter()
        .characterIdEqualTo(charId)
        .findAll();
    return items.map(_toModel).toList();
  }

  Future<ChatSession?> getById(String sessionId) async {
    final c = await _db.chatSessionCollections
        .where()
        .sessionIdEqualTo(sessionId)
        .findFirst();
    return c != null ? _toModel(c) : null;
  }

  Future<void> put(ChatSession session) async {
    await _db.writeTxn(() async {
      await _db.chatSessionCollections.put(_toCollection(session));
    });
  }

  Future<void> delete(String sessionId) async {
    await _db.writeTxn(() async {
      await _db.chatSessionCollections
          .where()
          .sessionIdEqualTo(sessionId)
          .deleteAll();
    });
  }

  ChatSession _toModel(ChatSessionCollection c) => ChatSession(
        id: c.sessionId,
        characterId: c.characterId,
        sessionIndex: c.sessionIndex,
        messages: (jsonDecode(c.messagesJson) as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: c.updatedAt,
      );

  ChatSessionCollection _toCollection(ChatSession m) => ChatSessionCollection()
    ..sessionId = m.id
    ..characterId = m.characterId
    ..sessionIndex = m.sessionIndex
    ..messagesJson =
        jsonEncode(m.messages.map((e) => e.toJson()).toList())
    ..updatedAt = m.updatedAt;
}
