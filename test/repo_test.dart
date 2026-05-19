import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/character_repo.dart';
import 'package:glaze_flutter/core/db/repositories/lorebook_repo.dart';
import 'package:glaze_flutter/core/models/character.dart';
import 'package:glaze_flutter/core/models/lorebook.dart';

AppDatabase _testDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() {
    db = _testDb();
  });

  tearDown(() async {
    await db.close();
  });

  group('LorebookRepo', () {
    late LorebookRepo repo;

    setUp(() {
      repo = LorebookRepo(db);
    });

    test('put and getAll round-trip', () async {
      final lb = Lorebook(
        id: 'lb1',
        name: 'World Lore',
        enabled: true,
        activationScope: 'global',
        entries: [
          LorebookEntry(
            id: '0',
            keys: ['castle'],
            content: 'The castle stands tall.',
          ),
        ],
      );

      await repo.put(lb);
      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.first.id, equals('lb1'));
      expect(all.first.name, equals('World Lore'));
      expect(all.first.entries.length, 1);
      expect(all.first.entries.first.keys, equals(['castle']));
    });

    test('getById returns lorebook or null', () async {
      expect(await repo.getById('missing'), isNull);

      await repo.put(Lorebook(id: 'lb1', name: 'Test'));
      final result = await repo.getById('lb1');
      expect(result, isNotNull);
      expect(result!.name, equals('Test'));
    });

    test('getByScopeAndTarget filters correctly', () async {
      await repo.put(Lorebook(
        id: 'global1',
        name: 'Global LB',
        activationScope: 'global',
      ));
      await repo.put(Lorebook(
        id: 'char_lb',
        name: 'Char LB',
        activationScope: 'character',
        activationTargetId: 'char1',
      ));
      await repo.put(Lorebook(
        id: 'char_lb2',
        name: 'Char LB 2',
        activationScope: 'character',
        activationTargetId: 'char2',
      ));

      final forChar1 = await repo.getByScopeAndTarget('character', 'char1');
      expect(forChar1.length, 1);
      expect(forChar1.first.id, equals('char_lb'));

      final globals = await repo.getByScopeAndTarget('global', '');
      expect(globals.length, 0,
          reason: 'Global lorebooks have null targetId, not empty string');

      final globalsDirect = (await repo.getAll())
          .where((lb) => lb.activationScope == 'global')
          .toList();
      expect(globalsDirect.length, 1);
      expect(globalsDirect.first.id, equals('global1'));

      final empty = await repo.getByScopeAndTarget('character', 'nonexistent');
      expect(empty, isEmpty);
    });

    test('delete removes lorebook', () async {
      await repo.put(Lorebook(id: 'lb1', name: 'Delete Me'));
      expect((await repo.getAll()).length, 1);

      await repo.delete('lb1');
      expect((await repo.getAll()).length, 0);
    });

    test('put updates existing lorebook', () async {
      await repo.put(Lorebook(id: 'lb1', name: 'V1'));
      await repo.put(Lorebook(id: 'lb1', name: 'V2'));

      final result = await repo.getById('lb1');
      expect(result!.name, equals('V2'));
    });

    test('createEntryFromCatalog adds entry to existing lorebook', () async {
      await repo.createEntryFromCatalog(
        characterId: 'char1',
        keys: ['magic'],
        content: 'Magic exists.',
      );

      var lb = await repo.getById('char1');
      expect(lb, isNotNull);
      expect(lb!.entries.length, 1);
      expect(lb.entries.first.content, equals('Magic exists.'));
      expect(lb.activationScope, equals('character'));
      expect(lb.activationTargetId, equals('char1'));

      await repo.createEntryFromCatalog(
        characterId: 'char1',
        keys: ['sword'],
        content: 'A sharp blade.',
      );

      lb = await repo.getById('char1');
      expect(lb!.entries.length, 2);
    });

    test('settings round-trip through put/getAll', () async {
      final lb = Lorebook(
        id: 'lb_settings',
        name: 'With Settings',
        settings: LorebookSettings(
          scanDepth: 10,
          vectorThreshold: 0.55,
          vectorTopK: 20,
        ),
      );

      await repo.put(lb);
      final result = await repo.getById('lb_settings');
      expect(result, isNotNull);
      expect(result!.settings, isNotNull);
      expect(result.settings!.scanDepth, equals(10));
      expect(result.settings!.vectorThreshold, equals(0.55));
      expect(result.settings!.vectorTopK, equals(20));
    });
  });

  group('CharacterRepo', () {
    late CharacterRepo repo;

    setUp(() {
      repo = CharacterRepo(db);
    });

    test('put and getAll round-trip', () async {
      final char = Character(id: 'c1', name: 'Alice', tags: ['fantasy', 'mage']);
      await repo.put(char);

      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.first.id, equals('c1'));
      expect(all.first.name, equals('Alice'));
      expect(all.first.tags, equals(['fantasy', 'mage']));
    });

    test('getById returns character or null', () async {
      expect(await repo.getById('missing'), isNull);

      await repo.put(Character(id: 'c1', name: 'Test'));
      final result = await repo.getById('c1');
      expect(result!.name, equals('Test'));
    });

    test('getByIds returns map of found characters', () async {
      await repo.put(Character(id: 'c1', name: 'Alice'));
      await repo.put(Character(id: 'c2', name: 'Bob'));
      await repo.put(Character(id: 'c3', name: 'Carol'));

      final result = await repo.getByIds({'c1', 'c3'});
      expect(result.length, 2);
      expect(result['c1']!.name, equals('Alice'));
      expect(result['c3']!.name, equals('Carol'));
      expect(result.containsKey('c2'), isFalse);
    });

    test('getByIds with empty set returns empty map', () async {
      final result = await repo.getByIds({});
      expect(result, isEmpty);
    });

    test('delete cascades to chat sessions, summaries, and memory book rows', () async {
      await repo.put(Character(id: 'c1', name: 'To Delete'));

      await db.into(db.chatSessions).insertOnConflictUpdate(
            ChatSessionsCompanion.insert(
              sessionId: 's1',
              characterId: 'c1',
              sessionIndex: 0,
              messagesJson: '[]',
            ),
          );

      await db.into(db.memoryBookRows).insertOnConflictUpdate(
            MemoryBookRowsCompanion.insert(
              sessionId: 's1',
              entriesJson: const Value('[]'),
            ),
          );

      await db.into(db.chatSummaries).insertOnConflictUpdate(
            ChatSummariesCompanion.insert(
              sessionId: 's1',
              content: 'summary text',
            ),
          );

      expect((await db.select(db.chatSessions).get()).length, 1);
      expect((await db.select(db.memoryBookRows).get()).length, 1);
      expect((await db.select(db.chatSummaries).get()).length, 1);

      await repo.delete('c1');

      expect((await db.select(db.characters).get()).length, 0);
      expect((await db.select(db.chatSessions).get()).length, 0,
          reason: 'Chat sessions should be cascade-deleted');
      expect((await db.select(db.memoryBookRows).get()).length, 0,
          reason: 'Memory book rows should be cascade-deleted');
      expect((await db.select(db.chatSummaries).get()).length, 0,
          reason: 'Chat summaries should be cascade-deleted');
    });

    test('delete with multiple sessions batches correctly', () async {
      await repo.put(Character(id: 'c1', name: 'Multi Session'));

      for (var i = 0; i < 5; i++) {
        await db.into(db.chatSessions).insertOnConflictUpdate(
              ChatSessionsCompanion.insert(
                sessionId: 's$i',
                characterId: 'c1',
                sessionIndex: i,
                messagesJson: '[]',
              ),
            );
        await db.into(db.memoryBookRows).insertOnConflictUpdate(
              MemoryBookRowsCompanion.insert(
                sessionId: 's$i',
                entriesJson: const Value('[]'),
              ),
            );
        await db.into(db.chatSummaries).insertOnConflictUpdate(
              ChatSummariesCompanion.insert(
                sessionId: 's$i',
                content: 'summary $i',
              ),
            );
      }

      await repo.delete('c1');

      expect((await db.select(db.chatSessions).get()).length, 0);
      expect((await db.select(db.memoryBookRows).get()).length, 0);
      expect((await db.select(db.chatSummaries).get()).length, 0);
    });

    test('delete does not affect other characters sessions', () async {
      await repo.put(Character(id: 'c1', name: 'Delete Me'));
      await repo.put(Character(id: 'c2', name: 'Keep Me'));

      await db.into(db.chatSessions).insertOnConflictUpdate(
            ChatSessionsCompanion.insert(
              sessionId: 's1',
              characterId: 'c1',
              sessionIndex: 0,
              messagesJson: '[]',
            ),
          );
      await db.into(db.chatSessions).insertOnConflictUpdate(
            ChatSessionsCompanion.insert(
              sessionId: 's2',
              characterId: 'c2',
              sessionIndex: 0,
              messagesJson: '[]',
            ),
          );

      await repo.delete('c1');

      final remaining = await db.select(db.chatSessions).get();
      expect(remaining.length, 1);
      expect(remaining.first.sessionId, equals('s2'));
    });

    test('createCharacterFromCatalog inserts character', () async {
      await repo.createCharacterFromCatalog(
        id: 'cat1',
        name: 'From Catalog',
        description: 'A catalog character',
        tags: ['tag1', 'tag2'],
        alternateGreetings: ['Hello!', 'Hi there!'],
      );

      final result = await repo.getById('cat1');
      expect(result, isNotNull);
      expect(result!.name, equals('From Catalog'));
      expect(result.description, equals('A catalog character'));
      expect(result.tags, equals(['tag1', 'tag2']));
      expect(result.alternateGreetings, equals(['Hello!', 'Hi there!']));
    });

    test('alternateGreetings and tags round-trip through put/getAll', () async {
      final char = Character(
        id: 'c1',
        name: 'Tags Test',
        tags: ['anime', 'fantasy'],
        alternateGreetings: ['Greeting 1', 'Greeting 2'],
      );

      await repo.put(char);
      final result = await repo.getById('c1');
      expect(result!.tags, equals(['anime', 'fantasy']));
      expect(result.alternateGreetings, equals(['Greeting 1', 'Greeting 2']));
    });

    test('extensions round-trip through put/getAll', () async {
      final char = Character(
        id: 'c1',
        name: 'Extensions Test',
        extensions: {'depth_prompt': {'prompt': 'test', 'depth': 4}},
      );

      await repo.put(char);
      final result = await repo.getById('c1');
      expect(result!.extensions.containsKey('depth_prompt'), isTrue);
    });

    test('watchAll emits updates', () async {
      final stream = repo.watchAll();

      final firstEmit = await stream.first;
      expect(firstEmit, isEmpty);

      await repo.put(Character(id: 'c1', name: 'Alice'));

      final secondEmit = await stream.first;
      expect(secondEmit.length, 1);
      expect(secondEmit.first.name, equals('Alice'));
    });
  });
}
