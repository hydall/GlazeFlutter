import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/chat_message.dart';
import '../../../features/cloud_sync/sync_repo_interfaces.dart';

class ChatRepo implements SyncChatStore {
  final AppDatabase _db;
  ChatRepo(this._db);

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

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

  @override
  Future<List<SessionMetadata>> getAllSessionMetadata() async {
    final rows = await (_db.select(
      _db.chatSessions,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();
    return rows.map(_toMetadata).toList();
  }

  Stream<List<SessionMetadata>> watchAllSessionMetadata() {
    var lastEmit = <SessionMetadata>[];
    return (_db.select(_db.chatSessions)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch()
        .asyncMap((rows) async {
          final meta = rows.map(_toMetadata).toList();
          if (_metadataEqual(lastEmit, meta)) return lastEmit;
          lastEmit = meta;
          return meta;
        });
  }

  static bool _metadataEqual(List<SessionMetadata> a, List<SessionMetadata> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].sessionId != b[i].sessionId ||
          a[i].updatedAt != b[i].updatedAt ||
          a[i].messageCount != b[i].messageCount ||
          a[i].sessionName != b[i].sessionName) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<ChatSession?> getById(String sessionId) async {
    final row = await (_db.select(
      _db.chatSessions,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  @override
  Future<void> put(ChatSession session) async {
    await _db
        .into(_db.chatSessions)
        .insertOnConflictUpdate(_toCompanion(session));
  }

  Future<Map<String, dynamic>> updateSessionVarsJson(
    String sessionId,
    Map<String, dynamic> Function(Map<String, dynamic> vars) update,
  ) async {
    return _db.transaction(() async {
      final row = await (_db.select(
        _db.chatSessions,
      )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
      if (row == null) {
        throw StateError('Chat session "$sessionId" was not found');
      }

      final current = _decodeJsonMap(row.sessionVarsJson);
      final updated = update(Map<String, dynamic>.from(current));
      await (_db.update(_db.chatSessions)
            ..where((t) => t.sessionId.equals(sessionId)))
          .write(
        ChatSessionsCompanion(
          sessionVarsJson: Value(updated.isNotEmpty ? jsonEncode(updated) : null),
        ),
      );
      return updated;
    });
  }

  @override
  Future<void> delete(String sessionId) async {
    await (_db.delete(
      _db.chatSessions,
    )..where((t) => t.sessionId.equals(sessionId))).go();
  }

  /// Deletes all sessions belonging to [characterId], along with all per-session
  /// dependent data (memory books, summaries). Returns the deleted session IDs
  /// for sync-deletion tracking.
  Future<List<String>> deleteByCharacterId(String characterId) async {
    final rows = await (_db.select(_db.chatSessions)
          ..where((t) => t.characterId.equals(characterId)))
        .get();
    final ids = rows.map((r) => r.sessionId).toList();

    if (ids.isNotEmpty) {
      await (_db.delete(_db.memoryBookRows)
            ..where((t) => t.sessionId.isIn(ids)))
          .go();
      await (_db.delete(_db.chatSummaries)
            ..where((t) => t.sessionId.isIn(ids)))
          .go();
      await (_db.delete(_db.chatSessions)
            ..where((t) => t.characterId.equals(characterId)))
          .go();
    }
    return ids;
  }

  SessionMetadata _toMetadata(ChatSessionRow c) {
    final json = c.messagesJson;

    // Lightweight scan: count top-level objects and find last object start
    // without deserializing the entire messages array.
    int messageCount = 0;
    String lastContent = '';
    int lastTimestamp = 0;

    if (json.length > 2) {
      final (count, startIdx) = _scanTopLevelObjects(json);
      messageCount = count;

      if (startIdx >= 0) {
        final lastBrace = json.lastIndexOf('}');
        if (lastBrace > startIdx) {
          try {
            final lastMsg =
                jsonDecode(json.substring(startIdx, lastBrace + 1))
                    as Map<String, dynamic>;
            lastContent = (lastMsg['content'] as String?) ?? '';
            if (lastContent.length > 250) {
              lastContent = lastContent.substring(0, 250);
            }
            lastTimestamp = (lastMsg['timestamp'] as int?) ?? 0;
          } catch (_) {}
        }
      }
    }

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
      messageCount: messageCount,
      lastMessageContent: lastContent,
      lastMessageTimestamp: lastTimestamp,
      sessionName: sessionName,
    );
  }

  /// Single-pass scan of a JSON array string.
  /// Returns (objectCount, lastObjectStartIndex) without full deserialization.
  static (int, int) _scanTopLevelObjects(String json) {
    int count = 0;
    int lastStart = -1;
    int depth = 0;
    bool inString = false;

    for (int i = 0; i < json.length; i++) {
      final ch = json.codeUnitAt(i);
      if (inString) {
        if (ch == 0x5C /* \ */) {
          i++; // skip escaped char
        } else if (ch == 0x22 /* " */) {
          inString = false;
        }
        continue;
      }
      switch (ch) {
        case 0x22: // "
          inString = true;
        case 0x5B: // [
          depth++;
        case 0x5D: // ]
          depth--;
        case 0x7B: // {
          depth++;
          if (depth == 2) {
            count++;
            lastStart = i;
          }
        case 0x7D: // }
          depth--;
      }
    }
    return (count, lastStart);
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

  Map<String, dynamic> _decodeJsonMap(String? text) {
    if (text == null || text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }
}
