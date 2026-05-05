import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'app_db.g.dart';

@DriftDatabase(tables: [
  Characters,
  ChatSessions,
  Presets,
  ApiConfigs,
  Personas,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = _getAppDataDir();
    final dir = Directory(dbFolder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dbFolder, 'glaze.db'));
    return NativeDatabase.createInBackground(file);
  });
}

String _getAppDataDir() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA']!;
    return p.join(appData, 'Glaze');
  } else if (Platform.isLinux) {
    final xdg = Platform.environment['XDG_DATA_HOME'] ??
        p.join(Platform.environment['HOME']!, '.local', 'share');
    return p.join(xdg, 'Glaze');
  } else if (Platform.isMacOS) {
    return p.join(Platform.environment['HOME']!, 'Library', 'Application Support', 'Glaze');
  }
  throw UnsupportedError('Platform not supported yet');
}
