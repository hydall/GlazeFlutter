import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_db.dart';
import '../../models/character.dart';
import '../../models/gallery_entry.dart';
import '../../utils/time_helpers.dart';

class CharacterRepo {
  final AppDatabase _db;
  CharacterRepo(this._db);

  Future<List<Character>> getAll() async {
    final rows = await (_db.select(_db.characters)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Stream<List<Character>> watchAll() {
    return (_db.select(_db.characters)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

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

  Future<void> put(Character character) async {
    await _db.into(_db.characters).insertOnConflictUpdate(_toCompanion(character));
  }

  Future<void> delete(String id) async {
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
        tags: c.tagsJson != null
            ? List<String>.from(jsonDecode(c.tagsJson!))
            : [],
        alternateGreetings: c.alternateGreetingsJson != null
            ? List<String>.from(jsonDecode(c.alternateGreetingsJson!))
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
        tagsJson: Value(jsonEncode(m.tags)),
        alternateGreetingsJson: Value(jsonEncode(m.alternateGreetings)),
        galleryJson: Value(jsonEncode(m.gallery.map((e) => e.toJson()).toList())),
        currentSessionIndex: Value(m.currentSessionIndex),
        fav: Value(m.fav),
        extensionsJson: Value(m.extensions.isNotEmpty ? jsonEncode(m.extensions) : null),
        characterVersion: Value(m.characterVersion),
        macroName: Value(m.macroName),
      );
}
