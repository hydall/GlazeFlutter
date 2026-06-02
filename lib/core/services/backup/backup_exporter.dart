import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../db/app_db.dart';
import '../file_export_service.dart';
import '../image_storage_service.dart';class BackupExporter {
  static const int _schemaVersion = 2;

  final AppDatabase _db;
  final ImageStorageService _imageStorage;

  BackupExporter(this._db, this._imageStorage);

  Future<String> export() async {
    final now = DateTime.now();
    final filename =
        'Glaze_backup_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.glz';

    final tempFile = File('${Directory.systemTemp.path}/$filename');
    final encoder = ZipFileEncoder();
    encoder.create(tempFile.path);

    try {
      await _writeZip(encoder);
      await encoder.close();
      final path = await FileExportService.exportFile(
        sourcePath: tempFile.path,
        filename: filename,
        subfolder: 'backup',
      );
      try {
        await tempFile.delete();
      } catch (_) {}
      return path;
    } catch (e) {
      try {
        await encoder.close();
      } catch (_) {}
      try {
        await tempFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _writeZip(ZipFileEncoder encoder) async {
    // 1. manifest.json
    final manifest = <String, dynamic>{
      '_isGlazeBackup': true,
      '_glazeVersion': _schemaVersion,
      '_source': 'flutter',
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    encoder.addArchiveFile(
      ArchiveFile.bytes('manifest.json', manifestBytes),
    );

    // 2. tables/<name>.jsonl — streamed per row.
    for (final tableName in _knownTableNames()) {
      final bytes = await _streamTableAsNdjson(tableName);
      if (bytes.isEmpty) continue;
      encoder.addArchiveFile(
        ArchiveFile.bytes('tables/$tableName.jsonl', bytes),
      );
    }

    // 3. preferences.json
    final prefs = await SharedPreferences.getInstance();
    final prefsMap = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) prefsMap[key] = value;
    }
    final prefsBytes = utf8.encode(jsonEncode(prefsMap));
    encoder.addArchiveFile(
      ArchiveFile.bytes('preferences.json', prefsBytes),
    );

    // 4. avatars/* — copy directly from disk into the zip via streams.
    final avatarsDir = Directory(p.join(_imageStorage.baseDir, 'avatars'));
    if (await avatarsDir.exists()) {
      await for (final entity in avatarsDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        // Heuristic: characters stored as <id>.png, personas as <id>.png.
        // We pack them all under avatars/flat; the importer already
        // matches the file to a character or persona by looking it up
        // via the characters / personas table.
        encoder.addFile(entity, 'avatars/$name');
      }
    }

    // 5. gallery/<charId>/<id>.<ext> — copy from disk as-is.
    final galleryDir = Directory(p.join(_imageStorage.baseDir, 'gallery'));
    if (await galleryDir.exists()) {
      await for (final charDir in galleryDir.list(followLinks: false)) {
        if (charDir is! Directory) continue;
        final charId = p.basename(charDir.path);
        await for (final f in charDir.list(followLinks: false)) {
          if (f is! File) continue;
          encoder.addFile(f, 'gallery/$charId/${p.basename(f.path)}');
        }
      }
    }
  }

  /// Serializes a table to NDJSON bytes. Loads the table fully into memory
  /// (Drift doesn't support true row-streaming), but does so one table at
  /// a time, so peak RAM is bounded by the largest single table instead of
  /// the whole database.
  Future<List<int>> _streamTableAsNdjson(String tableName) async {
    final builder = BytesBuilder(copy: false);
    List<QueryRow> rows;
    try {
      rows = await _db.customSelect('SELECT * FROM $tableName').get();
    } catch (_) {
      // table may not exist
      return builder.takeBytes();
    }
    for (final row in rows) {
      try {
        final data = row.data;
        builder.add(utf8.encode(jsonEncode(data)));
        builder.add([0x0A]); // '\n'
      } catch (_) {
        // skip unserializable rows
      }
    }
    rows = const [];
    return builder.takeBytes();
  }

  List<String> _knownTableNames() {
    return const [
      'characters',
      'chat_sessions',
      'presets',
      'api_configs',
      'personas',
      'lorebooks',
      'embeddings',
      'chat_summaries',
      'memory_book_rows',
      'extension_presets',
      'info_blocks',
    ];
  }
}
