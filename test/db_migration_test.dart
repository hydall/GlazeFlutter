import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/services/backup/js_backup_importer.dart';
import 'package:glaze_flutter/core/services/image_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase _testDb() => AppDatabase.forTesting(NativeDatabase.memory());

class _TestImageStorage extends ImageStorageService {
  _TestImageStorage()
    : super(Directory.systemTemp.createTempSync('glaze_test_img_').path);

  @override
  Future<String> saveAvatar(String characterId, Uint8List imageBytes) async {
    return '/fake/avatars/$characterId.png';
  }

  @override
  Future<String?> saveThumbnail(
    String characterId,
    Uint8List imageBytes,
  ) async {
    return '/fake/thumbnails/$characterId.jpg';
  }
}

void main() {
  group('Backup importer schema safety', () {
    late AppDatabase db;
    late ImageStorageService imageStorage;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = _testDb();
      imageStorage = _TestImageStorage();
    });

    tearDown(() async {
      await db.close();
    });

    test('calling import() twice does not crash on duplicate column', () async {
      final importer = JsBackupImporter(db, imageStorage);
      final data = _minimalBackup();

      await importer.import(data, onProgress: (_) {});

      await importer.import(data, onProgress: (_) {});
    });

    test('created_at column exists after import', () async {
      final importer = JsBackupImporter(db, imageStorage);
      await importer.import(_minimalBackup(), onProgress: (_) {});

      final cols = await db
          .customSelect("PRAGMA table_info('characters')")
          .get();
      final names = cols.map((c) => c.read<String>('name')).toSet();

      expect(names, contains('created_at'));
      expect(names, contains('macro_name'));
      expect(names, contains('picks_hash'));
    });

    test('current schema version after import', () async {
      final importer = JsBackupImporter(db, imageStorage);
      await importer.import(_minimalBackup(), onProgress: (_) {});

      final result = await db.customSelect('PRAGMA user_version').get();
      final version = result.first.read<int>('user_version');

      // user_version matches the Drift schema version (app_db.dart schemaVersion).
      // Update this constant whenever a new migration step is added.
      expect(version, 50);
    });

    test(
      'upgrade from v15 with macro_name already present does not crash',
      () async {
        final file = File(
          '${Directory.systemTemp.path}/glaze_mig_test_${DateTime.now().microsecondsSinceEpoch}.db',
        );
        addTearDown(() async {
          if (file.existsSync()) await file.delete();
        });

        final seeded = AppDatabase.forTesting(
          NativeDatabase.createInBackground(file),
        );
        await seeded.customSelect('SELECT 1').get();
        await seeded.customStatement('PRAGMA user_version = 15');
        await seeded.close();

        final upgraded = AppDatabase.forTesting(
          NativeDatabase.createInBackground(file),
        );
        // Ensure the db handle is released even if an expectation below
        // fails — otherwise Windows cannot delete the temp file in tearDown.
        addTearDown(() async => upgraded.close());
        await upgraded.customSelect('SELECT 1').get();

        final cols = await upgraded
            .customSelect("PRAGMA table_info('characters')")
            .get();
        final names = cols.map((c) => c.read<String>('name')).toSet();
        expect(names, contains('macro_name'));

        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .get();
        expect(version.first.read<int>('user_version'), 50);
        expect(names, contains('variant_group_id'));
        expect(names, contains('hidden'));
      },
    );

    test('memory catalog table exists in current schema', () async {
      final rows = await db
          .customSelect("PRAGMA table_info('memory_catalog_rows')")
          .get();
      final names = rows.map((c) => c.read<String>('name')).toSet();

      expect(names, contains('chat_session_id'));
      expect(names, contains('memory_entry_id'));
      expect(names, contains('entry_revision'));
      expect(names, contains('source_hash'));
      expect(names, contains('entities_json'));
      expect(names, contains('locations_json'));
      expect(names, contains('topics_json'));
      expect(names, contains('message_range_start'));
      expect(names, contains('message_range_end'));
      expect(names, contains('token_count'));
      expect(names, contains('abstract_text'));
      expect(names, contains('stale'));
    });

    test('memory graph tables exist in current schema (v35)', () async {
      final entityCols = await db
          .customSelect("PRAGMA table_info('memory_entity_rows')")
          .get();
      final entityNames = entityCols.map((c) => c.read<String>('name')).toSet();
      expect(entityNames, contains('chat_session_id'));
      expect(entityNames, contains('memory_entry_id'));
      expect(entityNames, contains('name'));
      expect(entityNames, contains('entity_type'));
      expect(entityNames, contains('salience_avg'));
      expect(entityNames, contains('source_hash'));

      final salienceCols = await db
          .customSelect("PRAGMA table_info('memory_salience_rows')")
          .get();
      final salienceNames = salienceCols
          .map((c) => c.read<String>('name'))
          .toSet();
      expect(salienceNames, contains('chat_session_id'));
      expect(salienceNames, contains('memory_entry_id'));
      expect(salienceNames, contains('score'));
      expect(salienceNames, contains('emotional_tags_json'));
      expect(salienceNames, contains('narrative_flags_json'));

      final cadenceCols = await db
          .customSelect("PRAGMA table_info('memory_cadence_rows')")
          .get();
      final cadenceNames = cadenceCols
          .map((c) => c.read<String>('name'))
          .toSet();
      expect(cadenceNames, contains('chat_session_id'));
      expect(cadenceNames, contains('assistant_messages_since_last_run'));
      expect(cadenceNames, contains('last_run_kind'));

      final consolidationCols = await db
          .customSelect("PRAGMA table_info('memory_consolidation_rows')")
          .get();
      final consolidationNames = consolidationCols
          .map((c) => c.read<String>('name'))
          .toSet();
      expect(consolidationNames, contains('chat_session_id'));
      expect(consolidationNames, contains('tier'));
      expect(consolidationNames, contains('summary'));
      expect(consolidationNames, contains('status'));
      expect(consolidationNames, contains('error_message'));
    });
  });
}

Map<String, dynamic> _minimalBackup() => {
  'keyvalue': <String, dynamic>{},
  'localStorage': <String, dynamic>{},
  'characters': <dynamic>[],
  'personas': <dynamic>[],
};
