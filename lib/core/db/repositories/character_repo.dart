import 'dart:convert';
import 'package:isar/isar.dart';
import '../collections.dart';
import '../../models/character.dart';

class CharacterRepo {
  final Isar _db;
  CharacterRepo(this._db);

  Future<List<Character>> getAll() async {
    final items = await _db.characterCollections.where().findAll();
    return items.map(_toModel).toList();
  }

  Future<Character?> getById(String id) async {
    final c =
        await _db.characterCollections.where().charIdEqualTo(id).findFirst();
    return c != null ? _toModel(c) : null;
  }

  Future<void> put(Character character) async {
    await _db.writeTxn(() async {
      await _db.characterCollections.put(_toCollection(character));
    });
  }

  Future<void> delete(String id) async {
    await _db.writeTxn(() async {
      await _db.characterCollections.where().charIdEqualTo(id).deleteAll();
    });
  }

  Character _toModel(CharacterCollection c) => Character(
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
      );

  CharacterCollection _toCollection(Character m) => CharacterCollection()
    ..charId = m.id
    ..name = m.name
    ..avatarPath = m.avatarPath
    ..description = m.description
    ..personality = m.personality
    ..scenario = m.scenario
    ..firstMes = m.firstMes
    ..mesExample = m.mesExample
    ..systemPrompt = m.systemPrompt
    ..postHistoryInstructions = m.postHistoryInstructions
    ..creator = m.creator
    ..creatorNotes = m.creatorNotes
    ..color = m.color
    ..updatedAt = m.updatedAt
    ..tagsJson = jsonEncode(m.tags)
    ..alternateGreetingsJson = jsonEncode(m.alternateGreetings);
}
