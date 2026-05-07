import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../utils/platform_paths.dart';
import 'tables.dart';

part 'app_db.g.dart';

@DriftDatabase(tables: [
  Characters,
  ChatSessions,
  Presets,
  ApiConfigs,
  Personas,
  Lorebooks,
  Embeddings,
  ChatSummaries,
  MemoryBookRows,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(apiConfigs, apiConfigs.mode);
          }
          if (from < 3) {
            await m.addColumn(chatSessions, chatSessions.sessionVarsJson);
          }
          if (from < 4) {
            await m.createTable(lorebooks);
          }
          if (from < 5) {
            await m.createTable(embeddings);
          }
          if (from < 6) {
            await m.createTable(chatSummaries);
          }
          if (from < 7) {
            await m.createTable(memoryBookRows);
          }
          if (from < 8) {
            await m.addColumn(characters, characters.galleryJson);
          }
          if (from < 9) {
            await m.addColumn(personas, personas.createdAt);
          }
          if (from < 10) {
            await m.addColumn(apiConfigs, apiConfigs.omitTemperature);
            await m.addColumn(apiConfigs, apiConfigs.omitTopP);
            await m.addColumn(apiConfigs, apiConfigs.omitReasoning);
            await m.addColumn(apiConfigs, apiConfigs.omitReasoningEffort);
          }
          if (from < 11) {
            await m.addColumn(apiConfigs, apiConfigs.embeddingUseSame);
            await m.addColumn(apiConfigs, apiConfigs.embeddingEndpoint);
            await m.addColumn(apiConfigs, apiConfigs.embeddingApiKey);
            await m.addColumn(apiConfigs, apiConfigs.embeddingModel);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getAppDataDir();
    final dir = Directory(dbFolder);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dbFolder, 'glaze.db'));
    return NativeDatabase.createInBackground(file);
  });
}
