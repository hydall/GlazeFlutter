import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/character.dart';
import '../../models/gallery_entry.dart';
import '../../llm/character_tokens.dart';
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

  /// Representative-row predicate for the My Characters list: only the cover
  /// (variant_order 0), and — unless [includeHidden] — only non-hidden rows.
  Expression<bool> _listPredicate(bool includeHidden) {
    final repOnly = _db.characters.variantOrder.equals(0);
    return includeHidden
        ? repOnly
        : repOnly & _db.characters.hidden.equals(false);
  }

  Future<List<Character>> getPage({
    required int limit,
    required int offset,
    required CharacterSortField sort,
    required CharacterSortDir dir,
    bool includeHidden = false,
  }) async {
    if (sort == CharacterSortField.lastChat) {
      final rows = await (_db.select(_db.characters).join([
            leftOuterJoin(
              _db.chatSessions,
              _db.chatSessions.characterId.equalsExp(_db.characters.charId),
            ),
          ])
            ..where(_listPredicate(includeHidden))
            ..addColumns([_lastChatAtColumn()])
            ..groupBy([_db.characters.charId])
            ..orderBy(_lastChatOrderTerms(dir))
            ..limit(limit, offset: offset))
          .get();
      return rows.map((r) => _toModel(r.readTable(_db.characters))).toList();
    }
    final rows = await (_db.select(_db.characters)
          ..where((t) => _listPredicate(includeHidden))
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
    bool includeHidden = false,
  }) {
    if (sort == CharacterSortField.lastChat) {
      return (_db.select(_db.characters).join([
            leftOuterJoin(
              _db.chatSessions,
              _db.chatSessions.characterId.equalsExp(_db.characters.charId),
            ),
          ])
            ..where(_listPredicate(includeHidden))
            ..addColumns([_lastChatAtColumn()])
            ..groupBy([_db.characters.charId])
            ..orderBy(_lastChatOrderTerms(dir))
            ..limit(limit, offset: offset))
          .watch()
          .map((rows) =>
              rows.map((r) => _toModel(r.readTable(_db.characters))).toList());
    }
    return (_db.select(_db.characters)
          ..where((t) => _listPredicate(includeHidden))
          ..orderBy(_orderBy(sort, dir))
          ..limit(limit, offset: offset))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  Stream<int> watchTotalCount({bool includeHidden = false}) {
    final countExp = _db.characters.charId.count();
    final query = _db.selectOnly(_db.characters)
      ..addColumns([countExp])
      ..where(_listPredicate(includeHidden));
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
    // Cache the estimated token count on every write (import/save) so the UI
    // reads it instead of re-encoding during scroll/filter.
    final withTokens =
        character.copyWith(tokenCount: estimateCharacterTokens(character));
    await _db.into(_db.characters).insertOnConflictUpdate(_toCompanion(withTokens));
  }

  /// Computes and stores `tokenCount` for rows that still have the default 0
  /// (existing characters from before the column was added). Runs in one batch
  /// → a single reactive emission; safe to call unawaited at startup.
  Future<void> backfillMissingTokenCounts() async {
    final rows = await (_db.select(_db.characters)
          ..where((t) => t.tokenCount.equals(0)))
        .get();
    if (rows.isEmpty) return;

    final updates = <String, int>{};
    for (final row in rows) {
      final count = estimateCharacterTokens(_toModel(row));
      if (count > 0) updates[row.charId] = count;
      // Yield between encodes so a large library doesn't jank the UI thread.
      await Future<void>.delayed(Duration.zero);
    }
    if (updates.isEmpty) return;

    await _db.batch((b) {
      updates.forEach((id, count) {
        b.update(
          _db.characters,
          CharactersCompanion(tokenCount: Value(count)),
          where: ($CharactersTable t) => t.charId.equals(id),
        );
      });
    });
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
    // Capture the variation group/order before deletion so we can promote a
    // sibling to representative (variant_order 0) if needed — otherwise the
    // whole group would vanish from the My Characters list (which only shows
    // variant_order 0 rows).
    final deletedRow = await (_db.select(_db.characters)
          ..where((t) => t.charId.equals(id)))
        .getSingleOrNull();

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
    // Drop folder memberships for this character (local folders feature).
    await (_db.delete(_db.characterFolderMembers)
          ..where((t) => t.charId.equals(id)))
        .go();
    await (_db.delete(_db.characters)..where((t) => t.charId.equals(id))).go();

    if (deletedRow != null && deletedRow.variantOrder == 0) {
      final groupId = deletedRow.variantGroupId.isEmpty
          ? deletedRow.charId
          : deletedRow.variantGroupId;
      await _promoteRepresentative(groupId);
    }
  }

  /// Ensures the variation group has a representative (variant_order 0) by
  /// promoting its lowest-ordered remaining sibling. No-op when the group is
  /// empty or already has a representative.
  Future<void> _promoteRepresentative(String groupId) async {
    final siblings = await (_db.select(_db.characters)
          ..where((t) => t.variantGroupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm.asc(t.variantOrder)]))
        .get();
    if (siblings.isEmpty || siblings.any((s) => s.variantOrder == 0)) return;
    await (_db.update(_db.characters)
          ..where((t) => t.charId.equals(siblings.first.charId)))
        .write(const CharactersCompanion(variantOrder: Value(0)));
  }

  /// All variations in a group, ordered by variant_order (representative first).
  Future<List<Character>> getVariants(String groupId) async {
    final rows = await (_db.select(_db.characters)
          ..where((t) => t.variantGroupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm.asc(t.variantOrder)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Stream<List<Character>> watchVariants(String groupId) {
    return (_db.select(_db.characters)
          ..where((t) => t.variantGroupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm.asc(t.variantOrder)]))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Next free variant_order for a group (max + 1, or 0 for a fresh group).
  Future<int> nextVariantOrder(String groupId) async {
    final maxExpr = _db.characters.variantOrder.max();
    final query = _db.selectOnly(_db.characters)
      ..addColumns([maxExpr])
      ..where(_db.characters.variantGroupId.equals(groupId));
    final row = await query.getSingleOrNull();
    final current = row?.read(maxExpr);
    return current == null ? 0 : current + 1;
  }

  Future<void> renameVariant(String charId, String? name) async {
    final trimmed = name?.trim();
    await (_db.update(_db.characters)..where((t) => t.charId.equals(charId)))
        .write(CharactersCompanion(
      variantName: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
    ));
  }

  /// Hides or reveals an entire variation group. Applied group-wide so that
  /// promoting a sibling on delete never resurfaces a hidden character.
  Future<void> setHidden(String groupId, bool hidden) async {
    await (_db.update(_db.characters)
          ..where((t) => t.variantGroupId.equals(groupId)))
        .write(CharactersCompanion(hidden: Value(hidden)));
  }

  /// Reassigns variant_order so [orderedIds] becomes 0..n-1 (index 0 = cover).
  Future<void> reorderVariants(String groupId, List<String> orderedIds) async {
    await _db.batch((b) {
      for (var i = 0; i < orderedIds.length; i++) {
        b.update(
          _db.characters,
          CharactersCompanion(variantOrder: Value(i)),
          where: ($CharactersTable t) => t.charId.equals(orderedIds[i]),
        );
      }
    });
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
            tokenCount: Value(estimateCharacterTokensFromParts(
              name: name,
              description: description,
              personality: personality,
              scenario: scenario,
              firstMes: firstMes,
              mesExample: mesExample,
            )),
          ),
        );
  }

  Character _toModel(CharacterRow c) {
    final extensions = c.extensionsJson != null
        ? Map<String, dynamic>.from(jsonDecode(c.extensionsJson!) as Map)
        : <String, dynamic>{};
    final rawDisplayName = extensions.remove('displayName');

    return Character(
      id: c.charId,
      name: c.name,
      displayName: rawDisplayName is String ? rawDisplayName : null,
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
      extensions: extensions,
      characterVersion: c.characterVersion,
      macroName: c.macroName,
      picksHash: c.picksHash,
      tokenCount: c.tokenCount,
      variantGroupId: c.variantGroupId.isEmpty ? c.charId : c.variantGroupId,
      variantName: c.variantName,
      variantOrder: c.variantOrder,
      hidden: c.hidden,
    );
  }

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
        extensionsJson: Value(_encodeCharacterExtensions(m)),
        characterVersion: Value(m.characterVersion),
        macroName: Value(m.macroName),
        picksHash: Value(m.picksHash),
        tokenCount: Value(m.tokenCount),
        variantGroupId:
            Value(m.variantGroupId.isEmpty ? m.id : m.variantGroupId),
        variantName: Value(m.variantName),
        variantOrder: Value(m.variantOrder),
        hidden: Value(m.hidden),
      );

  String? _encodeCharacterExtensions(Character m) {
    final extensions = Map<String, dynamic>.from(m.extensions);
    final displayName = m.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      extensions['displayName'] = displayName;
    } else {
      extensions.remove('displayName');
    }
    return extensions.isNotEmpty ? jsonEncode(extensions) : null;
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
