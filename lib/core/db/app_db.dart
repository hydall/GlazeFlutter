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
  ExtensionPresets,
  InfoBlocks,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 22;

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
            await m.addColumn(apiConfigs, apiConfigs.embeddingEnabled);
            await m.addColumn(apiConfigs, apiConfigs.embeddingMaxChunkTokens);
          }
          if (from < 12) {
            await m.addColumn(lorebooks, lorebooks.settingsJson);
          }
          if (from < 13) {
            await m.addColumn(chatSessions, chatSessions.authorsNoteJson);
            await m.addColumn(chatSessions, chatSessions.draft);
            await m.addColumn(characters, characters.currentSessionIndex);
            await m.addColumn(characters, characters.fav);
            await m.addColumn(characters, characters.extensionsJson);
          }
          if (from < 14) {
            await m.addColumn(chatSessions, chatSessions.lastScrollAnchorJson);
            await m.addColumn(characters, characters.characterVersion);
            await m.addColumn(lorebooks, lorebooks.description);
          }
          if (from < 15) {
            await m.addColumn(memoryBookRows, memoryBookRows.pendingDraftsJson);
          }
          if (from < 16) {
            await m.addColumn(characters, characters.macroName);
          }
          if (from < 17) {
            await customStatement(
              "DELETE FROM embeddings WHERE source_type = 'lorebook_entry'",
            );
          }
          if (from < 18) {
            await m.addColumn(characters, characters.picksHash);
          }
          if (from < 19) {
            await m.addColumn(characters, characters.createdAt);
            await customStatement(
              'UPDATE characters SET created_at = updated_at WHERE created_at = 0',
            );
          }
          if (from < 20) {
            await m.createTable(extensionPresets);
            await m.createTable(infoBlocks);
          }
          if (from < 21) {
            await m.addColumn(apiConfigs, apiConfigs.cacheControlTtl);
          }
          if (from < 22) {
            // Guard: only add columns if the table existed before v20.
            // If the table was created in the `from < 20` branch above,
            // Drift already applied the current schema (including order/status),
            // so adding them again would cause "duplicate column" errors.
            //
            // Additionally, if the table was created at v20 by a version of
            // the code that already had order/status in the Dart schema, the
            // same duplicate would occur — so we use a SQL-level existence
            // check that works on all SQLite versions supported by the app.
            if (from >= 20) {
              final cols = await customSelect(
                'PRAGMA table_info("info_blocks")',
              ).get();
              final colNames = cols.map((r) => r.read<String>('name')).toSet();
              if (!colNames.contains('order')) {
                await m.addColumn(infoBlocks, infoBlocks.order_);
              }
              if (!colNames.contains('status')) {
                await m.addColumn(infoBlocks, infoBlocks.status);
              }
            }
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
