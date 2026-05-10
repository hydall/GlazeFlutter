import 'dart:convert';

import 'package:drift/drift.dart';

import '../../db/app_db.dart';
import '../../utils/time_helpers.dart';
import '../image_storage_service.dart';
import 'backup_helpers.dart';

class JsChatImporter with BackupHelpers {
  @override
  final AppDatabase db;
  @override
  final ImageStorageService imageStorage;

  JsChatImporter(this.db, this.imageStorage);

  Future<void> importChats(Map<String, dynamic> kv) async {
    await importChatsFromMap(kv, 'gz_chat_');

    final topLevelChats = kv['chats'];
    if (topLevelChats is Map<String, dynamic>) {
      for (final entry in topLevelChats.entries) {
        final charId = entry.key;
        final chatData = entry.value as Map<String, dynamic>?;
        if (chatData == null) continue;
        await importChatData(charId, chatData);
      }
    }
  }

  Future<void> importChatsFromMap(
      Map<String, dynamic> kv, String prefix) async {
    final chatKeys = kv.keys.where((k) => k.startsWith(prefix));

    for (final key in chatKeys) {
      final charId = key.substring(prefix.length);
      final chatData = kv[key] as Map<String, dynamic>?;
      if (chatData == null) continue;
      await importChatData(charId, chatData);
    }
  }

  Future<void> importChatData(
      String charId, Map<String, dynamic> chatData) async {
    if (charId == 'undefined' || charId.isEmpty) return;
    final sessions = chatData['sessions'] as Map<String, dynamic>?;
    if (sessions == null) return;

    final authorsNotesRaw = chatData['authorsNotes'] is Map<String, dynamic>
        ? chatData['authorsNotes'] as Map<String, dynamic>
        : null;

    for (final sessionEntry in sessions.entries) {
      final sessionIdx = int.tryParse(sessionEntry.key) ?? 0;
      final rawMessages = sessionEntry.value as List<dynamic>;

      final messages = rawMessages.map((m) {
        final msg = m as Map<String, dynamic>;
        var role = msg['role'] as String? ?? 'user';
        if (role == 'char') role = 'assistant';

        final content =
            (msg['text'] is String ? msg['text'] as String : null) ??
                (msg['content'] is String
                    ? msg['content'] as String
                    : null) ??
                (msg['mes'] is String ? msg['mes'] as String : null) ??
                '';

        final swipes = <String>[];
        final rawSwipes = msg['swipes'];
        if (rawSwipes is List) {
          for (final s in rawSwipes) {
            swipes.add(s.toString());
          }
        }
        if (swipes.isEmpty && content.isNotEmpty) {
          swipes.add(content);
        }

        String? reasoning;
        final rawReasoning = msg['reasoning'];
        if (rawReasoning is String && rawReasoning.isNotEmpty) {
          reasoning = rawReasoning;
        }

        final persona = msg['persona'];
        String? personaId;
        String? personaName;
        if (persona is Map) {
          personaId = persona['id'] as String?;
          personaName = persona['name'] as String?;
        }

        return {
          'id': msg['id']?.toString() ??
              '${charId}_${sessionIdx}_${rawMessages.indexOf(m)}',
          'role': role,
          'content': content,
          'timestamp': msg['timestamp'],
          'personaId': msg['personaId'] ?? personaId,
          'personaName': msg['personaName'] ?? personaName,
          'swipes': swipes,
          'swipeId': toInt(msg['swipeId'] ?? msg['swipe_id']) ?? 0,
          'reasoning': reasoning,
          'isHidden': msg['isHidden'] ?? msg['is_hidden'] ?? false,
          'isError': msg['isError'] ?? false,
          'genTime': msg['genTime']?.toString(),
          'tokens': toInt(msg['tokens']),
          'greetingIndex':
              toInt(msg['greetingIndex'] ?? msg['greeting_index']),
          'contextRefs': msg['contextRefs'] is List
              ? List<String>.from(msg['contextRefs'].whereType<String>())
              : <String>[],
          'swipeDirection': msg['swipeDirection'] is String
              ? msg['swipeDirection']
              : (msg['swipe_direction'] is String
                  ? msg['swipe_direction'] as String
                  : 'none'),
          'isEditing':
              msg['isEditing'] == true || msg['is_editing'] == true,
          'isTyping':
              msg['isTyping'] == true || msg['is_typing'] == true,
          'guidanceText': msg['guidanceText'] is String
              ? msg['guidanceText'] as String
              : null,
          'guidanceType': msg['guidanceType'] is String
              ? msg['guidanceType'] as String
              : 'GENERATION',
          'triggeredLorebooks': msg['triggeredLorebooks'] is List
              ? List<String>.from(
                  msg['triggeredLorebooks'].whereType<String>())
              : <String>[],
          'triggeredMemories': msg['triggeredMemories'] is List
              ? List<String>.from(
                  msg['triggeredMemories'].whereType<String>())
              : <String>[],
          'swipesMeta': msg['swipesMeta'] is List
              ? (msg['swipesMeta'] as List)
                  .whereType<Map<String, dynamic>>()
                  .toList()
              : <Map<String, dynamic>>[],
          'memoryCoverage': msg['memoryCoverage'] is Map
              ? Map<String, dynamic>.from(msg['memoryCoverage'])
              : <String, dynamic>{},
          'time':
              msg['time'] is String ? msg['time'] as String : null,
        };
      }).toList();

      final sessionId = '${charId}_$sessionIdx';
      final chatUpdatedAt = toInt(chatData['updatedAt']);
      final anRaw = authorsNotesRaw?[sessionEntry.key];
      final authorsNoteJson = encodeAuthorsNote(anRaw);
      final draft =
          chatData['draft'] is String ? chatData['draft'] as String : null;
      final scrollAnchor = chatData['lastScrollAnchor'] is Map
          ? jsonEncode(chatData['lastScrollAnchor'])
          : null;
      await db.into(db.chatSessions).insertOnConflictUpdate(
            ChatSessionsCompanion.insert(
              sessionId: sessionId,
              characterId: charId,
              sessionIndex: sessionIdx,
              messagesJson: jsonEncode(messages),
              updatedAt:
                  Value(chatUpdatedAt ?? currentTimestampSeconds()),
              authorsNoteJson: Value(authorsNoteJson),
              draft: Value(draft),
              lastScrollAnchorJson: Value(scrollAnchor),
            ),
          );
    }

    final currentId = toInt(chatData['currentId']);
    if (currentId != null) {
      await (db.update(db.characters)
            ..where((t) => t.charId.equals(charId)))
          .write(CharactersCompanion(
        currentSessionIndex: Value(currentId),
      ));
    }

    final memoryBooksRaw = _decodeIfString(chatData['memoryBooks']);
    if (memoryBooksRaw is Map) {
      await _importMemoryBooksFromMap(charId, memoryBooksRaw);
    } else if (memoryBooksRaw is List) {
      final sessionId = '${charId}_0';
      await _importMemoryBookEntries(charId, sessionId, memoryBooksRaw, {}, null);
    }

    final pendingDraftsRaw = _decodeIfString(chatData['pendingDrafts']);
    if (pendingDraftsRaw is Map) {
      await _importMemoryDraftsFromMap(charId, pendingDraftsRaw);
    }
  }

  dynamic _decodeIfString(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return jsonDecode(value);
      } catch (_) {}
    }
    return value;
  }

  Future<void> _importMemoryBooksFromMap(
      String charId, Map memoryBooksRaw) async {
    for (final mbEntry in memoryBooksRaw.entries) {
      final mbSessionIdx = mbEntry.key;
      final mbData = mbEntry.value;
      if (mbData is! Map) continue;

      final mbFullSessionId = '${charId}_$mbSessionIdx';
      final rawEntries = mbData['entries'];
      final rawSettings =
          mbData['settings'] is Map ? mbData['settings'] as Map : {};

      if (rawEntries is List) {
        await _importMemoryBookEntries(
            charId, mbFullSessionId, rawEntries, rawSettings, mbData);
      }

      final rawDrafts = mbData['pendingDrafts'];
      if (rawDrafts is List) {
        await _importMemoryDraftsForSession(
            mbFullSessionId, rawDrafts);
      }
    }
  }

  Future<void> _importMemoryBookEntries(
      String charId,
      String sessionId,
      List rawEntries,
      Map rawSettings,
      Map? mbData) async {
    final entries = <Map<String, dynamic>>[];
    for (final e in rawEntries) {
      if (e is! Map) continue;
      entries.add({
        'id': e['id']?.toString() ?? '',
        'title': e['title'] is String
            ? e['title'] as String
            : (e['name'] is String ? e['name'] as String : ''),
        'keys': e['keys'] is List
            ? List<String>.from(e['keys'].whereType<String>())
            : <String>[],
        'glazeKeys': e['glazeKeys'] is List
            ? List<String>.from(e['glazeKeys'].whereType<String>())
            : <String>[],
        'content':
            e['content'] is String ? e['content'] as String : '',
        'rawContent': e['rawContent'] is String
            ? e['rawContent'] as String
            : null,
        'status': e['status'] is String
            ? e['status'] as String
            : 'active',
        'vectorSearch': e['vectorSearch'] == true,
        'messageIds': e['messageIds'] is List
            ? List<String>.from(
                e['messageIds'].whereType<String>())
            : <String>[],
        'messageRange': e['messageRange'] is Map
            ? _convertMessageRange(e['messageRange'] as Map)
            : null,
        'source': e['source'] is String
            ? e['source'] as String
            : 'manual',
        'createdAt': toInt(e['createdAt']),
        'updatedAt': toInt(e['updatedAt']) ?? 0,
        'generatedAt': toInt(e['generatedAt']),
      });
    }

    final settings = _parseMemorySettings(rawSettings);

    await db.into(db.memoryBookRows).insertOnConflictUpdate(
          MemoryBookRowsCompanion.insert(
            sessionId: sessionId,
            entriesJson: Value(jsonEncode(entries)),
            settingsJson: Value(jsonEncode(settings)),
            lastProcessedMessageCount: Value(toInt(mbData?['automation']
                        is Map
                    ? (mbData!['automation'] as Map)[
                        'lastProcessedMessageCount']
                    : null) ??
                0),
            updatedAt: Value(toInt(mbData?['updatedAt']) ??
                currentTimestampSeconds()),
          ),
        );
  }

  Map<String, dynamic> _parseMemorySettings(Map rawSettings) {
    return <String, dynamic>{
      'enabled': rawSettings['enabled'] == true,
      'autoCreateEnabled': rawSettings['autoCreateEnabled'] == true,
      'autoGenerateEnabled':
          rawSettings['autoGenerateEnabled'] == true,
      'maxInjectedEntries':
          toInt(rawSettings['maxInjectedEntries']) ?? 7,
      'autoCreateInterval':
          toInt(rawSettings['autoCreateInterval']) ?? 15,
      'useDelayedAutomation':
          rawSettings['useDelayedAutomation'] == true,
      'injectionTarget': rawSettings['injectionTarget'] is String
          ? rawSettings['injectionTarget'] as String
          : 'summary_block',
      'batchSize': toInt(rawSettings['batchSize']) ?? 3,
      'vectorSearchEnabled':
          rawSettings['vectorSearchEnabled'] == true,
      'keyMatchMode': rawSettings['keyMatchMode'] is String
          ? rawSettings['keyMatchMode'] as String
          : 'glaze',
      'generationSource': rawSettings['generationSource'] is String
          ? rawSettings['generationSource'] as String
          : 'current',
      'generationModel': rawSettings['generationModel'] is String
          ? rawSettings['generationModel'] as String
          : '',
      'generationEndpoint':
          rawSettings['generationEndpoint'] is String
              ? rawSettings['generationEndpoint'] as String
              : '',
      'generationApiKey': rawSettings['generationApiKey'] is String
          ? rawSettings['generationApiKey'] as String
          : '',
    };
  }

  Future<void> _importMemoryDraftsFromMap(
      String charId, Map pendingDraftsRaw) async {
    for (final entry in pendingDraftsRaw.entries) {
      final sessionIdx = entry.key;
      final drafts = entry.value;
      if (drafts is! List) continue;
      final sessionId = '${charId}_$sessionIdx';
      await _importMemoryDraftsForSession(sessionId, drafts);
    }
  }

  Future<void> _importMemoryDraftsForSession(
      String sessionId, List rawDrafts) async {
    final drafts = <Map<String, dynamic>>[];
    for (final d in rawDrafts) {
      if (d is! Map) continue;
      drafts.add({
        'id': d['id']?.toString() ?? '',
        'title': d['title'] is String ? d['title'] as String : '',
        'content': d['content'] is String ? d['content'] as String : '',
        'keys': d['keys'] is List
            ? List<String>.from(d['keys'].whereType<String>())
            : <String>[],
        'glazeKeys': d['glazeKeys'] is List
            ? List<String>.from(d['glazeKeys'].whereType<String>())
            : <String>[],
        'vectorSearch': d['vectorSearch'] == true,
        'messageIds': d['messageIds'] is List
            ? List<String>.from(d['messageIds'].whereType<String>())
            : <String>[],
        'messageRange': d['messageRange'] is Map
            ? _convertMessageRange(d['messageRange'] as Map)
            : null,
        'status': d['status'] is String ? d['status'] as String : 'pending_generation',
        'source': d['source'] is String ? d['source'] as String : '',
        'createdAt': toInt(d['createdAt']) ?? 0,
        'updatedAt': toInt(d['updatedAt']) ?? 0,
        'generatedAt': toInt(d['generatedAt']),
        'error': d['error'] is String ? d['error'] as String : null,
      });
    }

    final existing = await (db.select(db.memoryBookRows)
          ..where((t) => t.sessionId.equals(sessionId)))
        .getSingleOrNull();
    if (existing != null) {
      await (db.update(db.memoryBookRows)
            ..where((t) => t.sessionId.equals(sessionId)))
          .write(MemoryBookRowsCompanion(
        pendingDraftsJson: Value(jsonEncode(drafts)),
      ));
    } else {
      await db.into(db.memoryBookRows).insertOnConflictUpdate(
            MemoryBookRowsCompanion.insert(
              sessionId: sessionId,
              pendingDraftsJson: Value(jsonEncode(drafts)),
            ),
          );
    }
  }

  Map<String, dynamic>? _convertMessageRange(Map raw) {
    if (raw.containsKey('start') && raw.containsKey('end')) {
      return {
        'start': toInt(raw['start']) ?? 0,
        'end': toInt(raw['end']) ?? 0,
      };
    }
    return null;
  }
}
