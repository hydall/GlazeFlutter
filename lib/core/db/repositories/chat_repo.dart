import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/chat_message.dart';

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

class ChatRepo {
  final AppDatabase _db;
  ChatRepo(this._db);

  Future<List<ChatSession>> getByCharacterId(String charId) async {
    final rows = await (_db.select(
      _db.chatSessions,
    )..where((t) => t.characterId.equals(charId))).get();
    return rows.map(_toModel).toList();
  }

  Future<List<ChatSession>> getAllSessions() async {
    final rows = await (_db.select(
      _db.chatSessions,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();
    return rows.map(_toModel).toList();
  }

  Future<List<SessionMetadata>> getAllSessionMetadata() async {
    final rows = await (_db.select(
      _db.chatSessions,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();
    return rows.map(_toMetadata).toList();
  }

  Stream<List<SessionMetadata>> watchAllSessionMetadata() {
    return (_db.select(_db.chatSessions)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch()
        .map((rows) => rows.map(_toMetadata).toList());
  }

  Future<ChatSession?> getById(String sessionId) async {
    final row = await (_db.select(
      _db.chatSessions,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<void> put(ChatSession session) async {
    await _db
        .into(_db.chatSessions)
        .insertOnConflictUpdate(_toCompanion(session));
  }

  Future<void> delete(String sessionId) async {
    await (_db.delete(
      _db.chatSessions,
    )..where((t) => t.sessionId.equals(sessionId))).go();
  }

  SessionMetadata _toMetadata(ChatSessionRow c) {
    final msgs = jsonDecode(c.messagesJson) as List;
    final lastRaw = msgs.isNotEmpty ? msgs.last as Map<String, dynamic> : null;

    String? sessionName;
    if (c.sessionVarsJson != null && c.sessionVarsJson!.isNotEmpty) {
      try {
        final vars = jsonDecode(c.sessionVarsJson!) as Map;
        sessionName = vars['sessionName'] as String?;
      } catch (_) {}
    }

    return SessionMetadata(
      sessionId: c.sessionId,
      characterId: c.characterId,
      sessionIndex: c.sessionIndex,
      updatedAt: c.updatedAt,
      messageCount: msgs.length,
      lastMessageContent: (lastRaw?['content'] as String?) ?? '',
      lastMessageTimestamp: (lastRaw?['timestamp'] as int?) ?? 0,
      sessionName: sessionName,
    );
  }

  ChatSession _toModel(ChatSessionRow c) => ChatSession(
    id: c.sessionId,
    characterId: c.characterId,
    sessionIndex: c.sessionIndex,
    messages: (jsonDecode(c.messagesJson) as List)
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList(),
    updatedAt: c.updatedAt,
    sessionVars: c.sessionVarsJson != null
        ? Map<String, String>.from(jsonDecode(c.sessionVarsJson!) as Map)
        : {},
    authorsNote: _parseAuthorsNote(c.authorsNoteJson),
    draft: c.draft,
    lastScrollAnchor:
        c.lastScrollAnchorJson != null && c.lastScrollAnchorJson!.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(c.lastScrollAnchorJson!) as Map)
        : {},
  );

  ChatSessionsCompanion _toCompanion(ChatSession m) => ChatSessionsCompanion(
    sessionId: Value(m.id),
    characterId: Value(m.characterId),
    sessionIndex: Value(m.sessionIndex),
    messagesJson: Value(jsonEncode(m.messages.map((e) => e.toJson()).toList())),
    updatedAt: Value(m.updatedAt),
    sessionVarsJson: Value(
      m.sessionVars.isNotEmpty ? jsonEncode(m.sessionVars) : null,
    ),
    authorsNoteJson: Value(
      m.authorsNote != null ? jsonEncode(m.authorsNote!.toJson()) : null,
    ),
    draft: Value(m.draft),
    lastScrollAnchorJson: Value(
      m.lastScrollAnchor.isNotEmpty ? jsonEncode(m.lastScrollAnchor) : null,
    ),
  );

  AuthorsNote? _parseAuthorsNote(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is String) {
        return AuthorsNote(content: decoded);
      }
      if (decoded is Map<String, dynamic>) {
        return AuthorsNote.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }
}
