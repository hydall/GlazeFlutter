import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/character.dart';
import '../../models/gallery_entry.dart';
import '../../utils/time_helpers.dart';
import '../../../features/cloud_sync/sync_repo_interfaces.dart';

enum CharacterSortField { name, date, lastChat }

enum CharacterSortDir { asc, desc }

class CharacterRepo implements SyncCharacterStore {
  final AppDatabase _db;
  CharacterRepo(this._db);

  List<OrderClauseGenerator<$CharactersTable>> _orderBy(
    CharacterSortField field,
    CharacterSortDir dir,
  ) {
    if (field == CharacterSortField.lastChat) {
      return _lastChatOrder(dir);
    }
    final mode = dir == CharacterSortDir.asc ? OrderingMode.asc : OrderingMode.desc;
    final primaryExpr = switch (field) {
      CharacterSortField.name => _db.characters.name,
      CharacterSortField.date => _db.characters.createdAt,
      CharacterSortField.lastChat => _db.characters.createdAt,
    };
    return [
      ($CharactersTable t) => OrderingTerm(expression: primaryExpr, mode: mode),
      ($CharactersTable t) =>
          OrderingTerm(expression: t.charId, mode: OrderingMode.asc),
    ];
  }

  Expression<int> _lastChatAtColumn() {
    return _db.chatSessions.updatedAt.max();
  }

  List<OrderClauseGenerator<$CharactersTable>> _lastChatOrder(
    CharacterSortDir dir,
  ) {
    final mode = dir == CharacterSortDir.asc ? OrderingMode.asc : OrderingMode.desc;
    final nullExpr = _lastChatAtColumn().isNull();
    final chatExpr = _lastChatAtColumn();
    return [
      ($CharactersTable t) => OrderingTerm(expression: nullExpr, mode: OrderingMode.asc),
      ($CharactersTable t) => OrderingTerm(expression: chatExpr, mode: mode),
      ($CharactersTable t) =>
          OrderingTerm(expression: t.charId, mode: OrderingMode.asc),
    ];
  }

  List<OrderingTerm> _lastChatOrderTerms(CharacterSortDir dir) {
    final mode = dir == CharacterSortDir.asc ? OrderingMode.asc : OrderingMode.desc;
    final nullExpr = _lastChatAtColumn().isNull();
    final chatExpr = _lastChatAtColumn();
    return [
      OrderingTerm(expression: nullExpr, mode: OrderingMode.asc),
      OrderingTerm(expression: chatExpr, mode: mode),
      OrderingTerm(expression: _db.characters.charId, mode: OrderingMode.asc),
    ];
  }

  @override
  Future<List<Character>> getAll() async {
    final rows = await (_db.select(_db.characters)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Stream<List<Character>> watchAll() {
    return (_db.select(_db.characters)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  Future<List<Character>> getPage({
    required int limit,
    required int offset,
    required CharacterSortField sort,
    required CharacterSortDir dir,
  }) async {
    if (sort == CharacterSortField.lastChat) {
      final rows = await (_db.select(_db.characters).join([
            leftOuterJoin(
              _db.chatSessions,
              _db.chatSessions.characterId.equalsExp(_db.characters.charId),
            ),
          ])
            ..addColumns([_lastChatAtColumn()])
            ..groupBy([_db.characters.charId])
            ..orderBy(_lastChatOrderTerms(dir))
            ..limit(limit, offset: offset))
          .get();
      return rows.map((r) => _toModel(r.readTable(_db.characters))).toList();
    }
    final rows = await (_db.select(_db.characters)
          ..orderBy(_orderBy(sort, dir))
          ..limit(limit, offset: offset))
        .get();
    return rows.map(_toModel).toList();
  }

  Stream<List<Character>> watchPage({
    required int limit,
    required int offset,
    required CharacterSortField sort,
    required CharacterSortDir dir,
  }) {
    if (sort == CharacterSortField.lastChat) {
      return (_db.select(_db.characters).join([
            leftOuterJoin(
              _db.chatSessions,
              _db.chatSessions.characterId.equalsExp(_db.characters.charId),
            ),
          ])
            ..addColumns([_lastChatAtColumn()])
            ..groupBy([_db.characters.charId])
            ..orderBy(_lastChatOrderTerms(dir))
            ..limit(limit, offset: offset))
          .watch()
          .map((rows) =>
              rows.map((r) => _toModel(r.readTable(_db.characters))).toList());
    }
    return (_db.select(_db.characters)
          ..orderBy(_orderBy(sort, dir))
          ..limit(limit, offset: offset))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  Stream<int> watchTotalCount() {
    final countExp = _db.characters.charId.count();
    final query = _db.selectOnly(_db.characters)..addColumns([countExp]);
    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  @override
  Future<Character?> getById(String id) async {
    final row = await (_db.select(_db.characters)
          ..where((t) => t.charId.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<Map<String, Character>> getByIds(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (_db.select(_db.characters)
          ..where((t) => t.charId.isIn(ids.toList())))
        .get();
    return {for (final r in rows) r.charId: _toModel(r)};
  }

  @override
  Future<void> put(Character character) async {
    await _db.into(_db.characters).insertOnConflictUpdate(_toCompanion(character));
  }

  Future<Map<String, dynamic>> updateExtensionsJson(
    String charId,
    Map<String, dynamic> Function(Map<String, dynamic> extensions) update,
  ) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.characters)
            ..where((t) => t.charId.equals(charId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Character "$charId" was not found');
      }

      final current = _decodeJsonMap(row.extensionsJson);
      final updated = update(Map<String, dynamic>.from(current));
      await (_db.update(_db.characters)..where((t) => t.charId.equals(charId)))
          .write(
        CharactersCompanion(
          extensionsJson: Value(updated.isNotEmpty ? jsonEncode(updated) : null),
        ),
      );
      return updated;
    });
  }

  @override
  Future<void> delete(String id) async {
    final sessionIds = (await (_db.select(_db.chatSessions)
              ..where((t) => t.characterId.equals(id)))
            .get())
        .map((r) => r.sessionId)
        .toList();
    if (sessionIds.isNotEmpty) {
      await (_db.delete(_db.memoryBookRows)
            ..where((t) => t.sessionId.isIn(sessionIds)))
          .go();
      await (_db.delete(_db.chatSummaries)
            ..where((t) => t.sessionId.isIn(sessionIds)))
          .go();
    }
    await (_db.delete(_db.chatSessions)..where((t) => t.characterId.equals(id))).go();
    await (_db.delete(_db.characters)..where((t) => t.charId.equals(id))).go();
  }

  Future<void> createCharacterFromCatalog({
    required String id,
    required String name,
    String description = '',
    String personality = '',
    String scenario = '',
    String firstMes = '',
    String mesExample = '',
    String creatorNotes = '',
    String systemPrompt = '',
    String postHistoryInstructions = '',
    List<String> alternateGreetings = const [],
    List<String> tags = const [],
    String creator = '',
    String creatorId = '',
    String? avatarPath,
  }) async {
    await _db.into(_db.characters).insertOnConflictUpdate(
          CharactersCompanion(
            charId: Value(id),
            name: Value(name),
            avatarPath: Value(avatarPath),
            description: Value(description),
            personality: Value(personality),
            scenario: Value(scenario),
            firstMes: Value(firstMes),
            mesExample: Value(mesExample),
            systemPrompt: Value(systemPrompt),
            postHistoryInstructions: Value(postHistoryInstructions),
            creator: Value(creator),
            creatorNotes: Value(creatorNotes),
            updatedAt: Value(currentTimestampSeconds()),
            createdAt: Value(currentTimestampSeconds()),
            tagsJson: Value(jsonEncode(tags)),
            alternateGreetingsJson: Value(jsonEncode(alternateGreetings)),
          ),
        );
  }

  Character _toModel(CharacterRow c) => Character(
        id: c.charId,
        name: c.name,
        avatarPath: c.avatarPath,
        description: c.description,
        personality: c.personality,
        scenario: c.scenario,
        firstMes: c.firstMes,
        mesExample: c.mesExample,
        systemPrompt: c.systemPrompt,
        postHistoryInstructions: c.postHistoryInstructions,
        creator: c.creator,
        creatorNotes: c.creatorNotes,
        color: c.color,
        updatedAt: c.updatedAt,
        createdAt: c.createdAt,
        tags: c.tagsJson != null
            ? List<String>.from(jsonDecode(c.tagsJson!) as List<dynamic>)
            : [],
        alternateGreetings: c.alternateGreetingsJson != null
            ? List<String>.from(jsonDecode(c.alternateGreetingsJson!) as List<dynamic>)
            : [],
        gallery: c.galleryJson != null
            ? (jsonDecode(c.galleryJson!) as List)
                .map((e) => GalleryEntry.fromJson(e as Map<String, dynamic>))
                .toList()
            : [],
        currentSessionIndex: c.currentSessionIndex,
        fav: c.fav,
        extensions: c.extensionsJson != null
            ? Map<String, dynamic>.from(jsonDecode(c.extensionsJson!) as Map)
            : {},
        characterVersion: c.characterVersion,
        macroName: c.macroName,
        picksHash: c.picksHash,
      );

  CharactersCompanion _toCompanion(Character m) => CharactersCompanion(
        charId: Value(m.id),
        name: Value(m.name),
        avatarPath: Value(m.avatarPath),
        description: Value(m.description),
        personality: Value(m.personality),
        scenario: Value(m.scenario),
        firstMes: Value(m.firstMes),
        mesExample: Value(m.mesExample),
        systemPrompt: Value(m.systemPrompt),
        postHistoryInstructions: Value(m.postHistoryInstructions),
        creator: Value(m.creator),
        creatorNotes: Value(m.creatorNotes),
        color: Value(m.color),
        updatedAt: Value(m.updatedAt),
        createdAt: Value(m.createdAt),
        tagsJson: Value(jsonEncode(m.tags)),
        alternateGreetingsJson: Value(jsonEncode(m.alternateGreetings)),
        galleryJson: Value(jsonEncode(m.gallery.map((e) => e.toJson()).toList())),
        currentSessionIndex: Value(m.currentSessionIndex),
        fav: Value(m.fav),
        extensionsJson: Value(m.extensions.isNotEmpty ? jsonEncode(m.extensions) : null),
        characterVersion: Value(m.characterVersion),
        macroName: Value(m.macroName),
        picksHash: Value(m.picksHash),
      );

  Map<String, dynamic> _decodeJsonMap(String? text) {
    if (text == null || text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }
}
