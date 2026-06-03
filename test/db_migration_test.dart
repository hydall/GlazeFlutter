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
  _TestImageStorage() : super(Directory.systemTemp.createTempSync('glaze_test_img_').path);

  @override
  Future<String> saveAvatar(String characterId, Uint8List imageBytes) async {
    return '/fake/avatars/$characterId.png';
  }

  @override
  Future<String?> saveThumbnail(String characterId, Uint8List imageBytes) async {
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

    test('21 after import', () async {
      final importer = JsBackupImporter(db, imageStorage);
      await importer.import(_minimalBackup(), onProgress: (_) {});

      final result = await db.customSelect('PRAGMA user_version').get();
      final version = result.first.read<int>('user_version');

      expect(version, 21);
    });
  });
}

Map<String, dynamic> _minimalBackup() => {
      'keyvalue': <String, dynamic>{},
      'localStorage': <String, dynamic>{},
      'characters': <dynamic>[],
      'personas': <dynamic>[],
    };
