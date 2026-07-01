import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../utils/platform_paths.dart';
import '../utils/time_helpers.dart';
import 'tables.dart';

part 'app_db.g.dart';

@DriftDatabase(
  tables: [
    Characters,
    CharacterFolders,
    CharacterFolderMembers,
    ChatSessions,
    Presets,
    ApiConfigs,
    Personas,
    Lorebooks,
    Embeddings,
    ChatSummaries,
    MemoryBookRows,
    MemoryCatalogRows,
    MemoryEntityRows,
    MemorySalienceRows,
    MemoryCadenceRows,
    MemoryConsolidationRows,
    StudioConfigRows,
    StudioPresetRows,
    TrackerRows,
    TrackerSnapshots,
    ExtensionPresets,
    InfoBlocks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 55;

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
        // Guard: early builds may have already added macro_name under a
        // different schema version. Unguarded addColumn raises "duplicate
        // column name: macro_name" and aborts DB open (gray chats screen).
        final cols = await customSelect(
          'PRAGMA table_info("characters")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('macro_name')) {
          await m.addColumn(characters, characters.macroName);
        }
      }
      if (from < 17) {
        await customStatement(
          "DELETE FROM embeddings WHERE source_type = 'lorebook_entry'",
        );
      }
      if (from < 18) {
        final cols = await customSelect(
          'PRAGMA table_info("characters")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('picks_hash')) {
          await m.addColumn(characters, characters.picksHash);
        }
      }
      if (from < 19) {
        final cols = await customSelect(
          'PRAGMA table_info("characters")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('created_at')) {
          await m.addColumn(characters, characters.createdAt);
        }
        await customStatement(
          'UPDATE characters SET created_at = updated_at WHERE created_at = 0',
        );
      }
      if (from < 20) {
        // Guard: early builds may have already created these tables under a
        // different schema version. createTable without IF NOT EXISTS raises
        // "table ... already exists" and aborts the migration. Check the
        // sqlite_master catalog before creating.
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('extension_presets')) {
          await m.createTable(extensionPresets);
        }
        if (!tableNames.contains('info_blocks')) {
          await m.createTable(infoBlocks);
        }
      }
      if (from < 21) {
        // Guard: same root cause as the column guards below — early builds
        // may have already added cache_control_ttl under a different version.
        final cols = await customSelect(
          'PRAGMA table_info("api_configs")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('cache_control_ttl')) {
          await m.addColumn(apiConfigs, apiConfigs.cacheControlTtl);
        }
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
      if (from < 23) {
        // Guard: early `feat/freezed-3x-migration` builds may have already
        // added `protocol` under a different schema version. Without the
        // existence check Drift's `addColumn` raises "duplicate column name:
        // protocol" on upgrade, which aborts the whole migration and bricks
        // DB open (and everything downstream, including the chat WebView).
        final cols = await customSelect(
          'PRAGMA table_info("api_configs")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('protocol')) {
          await m.addColumn(apiConfigs, apiConfigs.protocol);
        }
      }
      if (from < 24) {
        // Guard each column: early builds may have added these under a
        // different schema version (same root cause as the protocol guard
        // above). The unguarded addColumn would raise "duplicate column name"
        // and abort the migration. The `from < 27` block below also guards
        // these, but that branch only runs when upgrading from < 27 — this
        // branch must be self-consistent on its own.
        final cols = await customSelect(
          'PRAGMA table_info("api_configs")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('top_k')) {
          await m.addColumn(apiConfigs, apiConfigs.topK);
        }
        if (!colNames.contains('frequency_penalty')) {
          await m.addColumn(apiConfigs, apiConfigs.frequencyPenalty);
        }
        if (!colNames.contains('presence_penalty')) {
          await m.addColumn(apiConfigs, apiConfigs.presencePenalty);
        }
        await customStatement(
          'UPDATE api_configs SET top_k = 0 WHERE top_k IS NULL',
        );
        await customStatement(
          'UPDATE api_configs SET frequency_penalty = 0.0 WHERE frequency_penalty IS NULL',
        );
        await customStatement(
          'UPDATE api_configs SET presence_penalty = 0.0 WHERE presence_penalty IS NULL',
        );
      }
      if (from < 25) {
        // Guard: previous versions of these migrations may have been partially
        // applied (e.g. an early `feat/freezed-3x-migration` build that landed
        // these columns under different schema versions). Without the guard
        // Drift's `addColumn` raises "duplicate column name" on upgrade.
        final cols = await customSelect(
          'PRAGMA table_info("api_configs")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('cache_breakpoint_mode')) {
          await m.addColumn(apiConfigs, apiConfigs.cacheBreakpointMode);
        }
        if (!colNames.contains('session_id_mode')) {
          await m.addColumn(apiConfigs, apiConfigs.sessionIdMode);
        }
      }
      if (from < 27) {
        // Schema may have been bumped past v24 without addColumn running (e.g.
        // early builds). Ensure columns exist before backfilling NULLs — Drift
        // map() uses ! on these fields.
        final cols = await customSelect(
          'PRAGMA table_info("api_configs")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('top_k')) {
          await m.addColumn(apiConfigs, apiConfigs.topK);
        }
        if (!colNames.contains('frequency_penalty')) {
          await m.addColumn(apiConfigs, apiConfigs.frequencyPenalty);
        }
        if (!colNames.contains('presence_penalty')) {
          await m.addColumn(apiConfigs, apiConfigs.presencePenalty);
        }
        if (!colNames.contains('cache_breakpoint_mode')) {
          await m.addColumn(apiConfigs, apiConfigs.cacheBreakpointMode);
        }
        if (!colNames.contains('session_id_mode')) {
          await m.addColumn(apiConfigs, apiConfigs.sessionIdMode);
        }
        await customStatement(
          'UPDATE api_configs SET top_k = 0 WHERE top_k IS NULL',
        );
        await customStatement(
          'UPDATE api_configs SET frequency_penalty = 0.0 WHERE frequency_penalty IS NULL',
        );
        await customStatement(
          'UPDATE api_configs SET presence_penalty = 0.0 WHERE presence_penalty IS NULL',
        );
        await customStatement(
          "UPDATE api_configs SET cache_breakpoint_mode = 'depth' WHERE cache_breakpoint_mode IS NULL",
        );
        await customStatement(
          "UPDATE api_configs SET session_id_mode = 'openrouter' WHERE session_id_mode IS NULL",
        );
      }
      if (from < 28) {
        // v28 adds swipe_id but existing rows can remain NULL (partial upgrade
        // or SQLite ADD COLUMN without a backfill). Drift reads swipe_id as
        // non-null, so NULL rows crash InfoBlocksRepository.getBySessionId.
        final cols = await customSelect(
          'PRAGMA table_info("info_blocks")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('swipe_id')) {
          await m.addColumn(infoBlocks, infoBlocks.swipeId);
        }
        await customStatement(
          'UPDATE info_blocks SET swipe_id = 0 WHERE swipe_id IS NULL',
        );
      }
      if (from < 29) {
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('memory_catalog_rows')) {
          await m.createTable(memoryCatalogRows);
        }
      }
      if (from < 30) {
        final cols = await customSelect(
          'PRAGMA table_info("chat_summaries")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('enabled')) {
          await m.addColumn(chatSummaries, chatSummaries.enabled);
        }
        await customStatement(
          'UPDATE chat_summaries SET enabled = 1 WHERE enabled IS NULL',
        );
      }
      if (from < 31) {
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('character_folders')) {
          await m.createTable(characterFolders);
        }
        if (!tableNames.contains('character_folder_members')) {
          await m.createTable(characterFolderMembers);
        }
      }
      if (from < 32) {
        final cols = await customSelect(
          'PRAGMA table_info("characters")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('token_count')) {
          await m.addColumn(characters, characters.tokenCount);
        }
      }
      if (from < 33) {
        // Character variations: rows sharing variant_group_id collapse to one
        // list card. Guarded like every prior column migration.
        final cols = await customSelect(
          'PRAGMA table_info("characters")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('variant_group_id')) {
          await m.addColumn(characters, characters.variantGroupId);
        }
        if (!colNames.contains('variant_name')) {
          await m.addColumn(characters, characters.variantName);
        }
        if (!colNames.contains('variant_order')) {
          await m.addColumn(characters, characters.variantOrder);
        }
        // Backfill: every existing character is its own standalone group.
        await customStatement(
          "UPDATE characters SET variant_group_id = char_id "
          "WHERE variant_group_id IS NULL OR variant_group_id = ''",
        );
      }
      if (from < 34) {
        // Hideable characters: the `hidden` flag excludes a character (group)
        // from the My Characters list. Guarded like every prior column.
        final cols = await customSelect(
          'PRAGMA table_info("characters")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('hidden')) {
          await m.addColumn(characters, characters.hidden);
        }
      }
      if (from < 35) {
        // Memory Graph foundation (Phase G0): entity graph, salience, cadence,
        // and consolidation tables. Guarded like every prior table migration
        // to survive partial upgrades from early feature builds.
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('memory_entity_rows')) {
          await m.createTable(memoryEntityRows);
        }
        if (!tableNames.contains('memory_salience_rows')) {
          await m.createTable(memorySalienceRows);
        }
        if (!tableNames.contains('memory_cadence_rows')) {
          await m.createTable(memoryCadenceRows);
        }
        if (!tableNames.contains('memory_consolidation_rows')) {
          await m.createTable(memoryConsolidationRows);
        }
      }
      if (from < 36) {
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('studio_config_rows')) {
          await m.createTable(studioConfigRows);
        }
      }
      if (from < 37) {
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('build_api_config_id')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN build_api_config_id TEXT NOT NULL DEFAULT ""',
          );
        }
        if (!colNames.contains('run_api_config_id')) {
          await m.addColumn(studioConfigRows, studioConfigRows.runApiConfigId);
        }
      }
      if (from < 38) {
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('selected_block_ids_json')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN selected_block_ids_json TEXT NOT NULL DEFAULT "[]"',
          );
        }
        if (!colNames.contains('selected_block_ids_initialized')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN selected_block_ids_initialized INTEGER NOT NULL DEFAULT 0',
          );
        }
      }
      if (from < 39) {
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('final_preset_id')) {
          await m.addColumn(studioConfigRows, studioConfigRows.finalPresetId);
        }
      }
      if (from < 40) {
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('agent_studio_preset_id')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN agent_studio_preset_id TEXT NOT NULL DEFAULT ""',
          );
        }
        if (!colNames.contains('final_studio_preset_id')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN final_studio_preset_id TEXT NOT NULL DEFAULT ""',
          );
        }
      }
      if (from < 41) {
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('studio_preset_overrides_json')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN studio_preset_overrides_json TEXT NOT NULL DEFAULT "[]"',
          );
        }
      }
      if (from < 42) {
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('profile_id')) {
          await m.addColumn(studioConfigRows, studioConfigRows.profileId);
        }
        if (!colNames.contains('profile_name')) {
          await m.addColumn(studioConfigRows, studioConfigRows.profileName);
        }
        await customStatement(
          "UPDATE studio_config_rows SET profile_id = session_id "
          "WHERE profile_id IS NULL OR profile_id = ''",
        );
        await customStatement(
          "UPDATE studio_config_rows SET profile_name = "
          "CASE WHEN profile_id IS NULL OR profile_id = '' "
          "THEN 'Studio Profile' ELSE 'Studio: ' || profile_id END "
          "WHERE profile_name IS NULL OR profile_name = ''",
        );
      }
      if (from < 43) {
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('builder_prompt_template')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN builder_prompt_template TEXT NOT NULL DEFAULT ""',
          );
        }
      }
      if (from < 44) {
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('max_final_history_messages')) {
          await m.addColumn(
            studioConfigRows,
            studioConfigRows.maxFinalHistoryMessages,
          );
        }
      }
      if (from < 45) {
        // Agentic memory trackers: lightweight key-value state written by the
        // memory agent (e.g. 'Lucy: chip in pocket', 'relationship: +1').
        // Guarded like every prior table migration to survive partial upgrades
        // from early feature builds.
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('tracker_rows')) {
          await m.createTable(trackerRows);
        }
      }
      if (from < 46) {
        // Stage 3: routing mode for preset orchestrator — 'verbatim' (default,
        // blocks go to agents дословно) vs 'compiled' (legacy LLM digest).
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('routing_mode')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN routing_mode TEXT NOT NULL DEFAULT "verbatim"',
          );
        }
      }
      if (from < 47) {
        // Broadcast blocks: verbatim content of cross-cutting rules (output
        // language + prose-quality guards) captured at Studio build time so the
        // POST-cleaner can apply the user's own rules instead of a hardcoded
        // English-only cliché list. Guarded to survive partial upgrades.
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('broadcast_blocks_json')) {
          await m.addColumn(
            studioConfigRows,
            studioConfigRows.broadcastBlocksJson,
          );
        }
      }
      if (from < 48) {
        // Pipeline settings separation: extract pipeline LLM fields from
        // memory_book_rows.settings_json into a new pipeline_settings_rows
        // table so generation-pipeline config is owned by the pipeline, not
        // the memory book. Additive only — old JSON keys are left in
        // memory_book_rows.settings_json and silently ignored by the updated
        // MemoryBookSettings.fromJson (unknown keys are dropped by freezed).
        //
        // NOTE: the pipeline_settings_rows table was dropped in schema v52
        // (pipeline settings are now a singleton global in SharedPreferences).
        // This v48 migration is retained so users upgrading from <48 → >=52
        // still create the table transiently before the v52 step drops it.
        // The CREATE TABLE uses raw SQL (not m.createTable) because the Drift
        // table definition was removed when the table was dropped.
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('pipeline_settings_rows')) {
          await customStatement(
            'CREATE TABLE IF NOT EXISTS pipeline_settings_rows ('
            'session_id TEXT NOT NULL PRIMARY KEY, '
            "settings_json TEXT NOT NULL DEFAULT '{}', "
            'updated_at INTEGER NOT NULL DEFAULT 0)',
          );
        }
        // Migrate existing per-session pipeline settings out of memory books.
        // Done in Dart (not SQL) because the field set is large and typed.
        final rows = await customSelect(
          'SELECT session_id, settings_json FROM memory_book_rows',
        ).get();
        const pipelineKeys = <String>{
          'generationSource',
          'generationModel',
          'generationEndpoint',
          'generationApiKey',
          'generationTemperature',
          'generationMaxTokens',
          'auxSource',
          'auxModel',
          'auxEndpoint',
          'auxApiKey',
          'auxTimeoutMs',
          'agenticWriteEnabled',
          'postCleanerEnabled',
          'postCleanerTemperature',
          'postCleanerMaxTokens',
          'postCleanerSource',
          'postCleanerModel',
          'postCleanerEndpoint',
          'postCleanerApiKey',
          'postCleanerTimeoutMs',
          'postCleanerContinuityEnabled',
          'postCleanerCharacterCheckEnabled',
          'postCleanerHistoryMessages',
          'postCleanerMaxCharsPerMessage',
          'consolidationEnabled',
          'consolidationThreshold',
          'consolidationSource',
          'consolidationModel',
          'consolidationEndpoint',
          'consolidationApiKey',
          'consolidationTimeoutMs',
        };
        for (final row in rows) {
          final sessionId = row.read<String>('session_id');
          final raw = row.read<String>('settings_json');
          Map<String, dynamic>? bookJson;
          try {
            bookJson = jsonDecode(raw) as Map<String, dynamic>;
          } catch (_) {
            bookJson = null;
          }
          if (bookJson == null) continue;
          final pipelineJson = <String, dynamic>{};
          for (final key in pipelineKeys) {
            if (bookJson.containsKey(key)) {
              pipelineJson[key] = bookJson[key];
            }
          }
          // Historical builds stored the shared helper LLM config as
          // `sidecar*`. Preserve that config under the neutral `aux*` names.
          if (!pipelineJson.containsKey('auxSource') &&
              bookJson.containsKey('sidecarSource')) {
            pipelineJson['auxSource'] = bookJson['sidecarSource'];
          }
          if (!pipelineJson.containsKey('auxModel') &&
              bookJson.containsKey('sidecarModel')) {
            pipelineJson['auxModel'] = bookJson['sidecarModel'];
          }
          if (!pipelineJson.containsKey('auxEndpoint') &&
              bookJson.containsKey('sidecarEndpoint')) {
            pipelineJson['auxEndpoint'] = bookJson['sidecarEndpoint'];
          }
          if (!pipelineJson.containsKey('auxApiKey') &&
              bookJson.containsKey('sidecarApiKey')) {
            pipelineJson['auxApiKey'] = bookJson['sidecarApiKey'];
          }
          if (!pipelineJson.containsKey('auxTimeoutMs') &&
              bookJson.containsKey('sidecarTimeoutMs')) {
            pipelineJson['auxTimeoutMs'] = bookJson['sidecarTimeoutMs'];
          }
          if (pipelineJson.isEmpty) continue;
          await customStatement(
            'INSERT OR REPLACE INTO pipeline_settings_rows '
            '(session_id, settings_json, updated_at) '
            "VALUES (?, ?, CAST(strftime('%s','now') AS INTEGER))",
            [sessionId, jsonEncode(pipelineJson)],
          );
        }
      }
      if (from < 49) {
        // Studio Build/Run model overrides: allow the user to pick a specific
        // model from the API config's fetched model list, independent of the
        // config's default `model` field. Additive — defaults to '' (use
        // config.model).
        final cols = await customSelect(
          'PRAGMA table_info("studio_config_rows")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('build_model_override')) {
          await customStatement(
            'ALTER TABLE studio_config_rows ADD COLUMN build_model_override TEXT NOT NULL DEFAULT ""',
          );
        }
        if (!colNames.contains('run_model_override')) {
          await m.addColumn(
            studioConfigRows,
            studioConfigRows.runModelOverride,
          );
        }
      }
      if (from < 50) {
        // Per-(message, swipe, agent-swipe) tracker state snapshots. Mirrors
        // Marinara-Engine's game_state_snapshots: each swipe of each message
        // owns an immutable tracker-state row so delete/swipe/regen rollback
        // is emergent (drop the rows; the previous committed snapshot becomes
        // "latest"). Guarded like every prior table migration to survive
        // partial upgrades.
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('tracker_snapshots')) {
          await m.createTable(trackerSnapshots);
        }
      }
      if (from < 51) {
        // Migrate existing tracker_rows into baseline tracker_snapshots so
        // legacy sessions get a committed snapshot the read path can find.
        // For each session with trackers, insert one snapshot at the sentinel
        // anchor (messageId='', swipeId=0, agentSwipeId=0, committed=1). This
        // snapshot is never dropped by deleteForMessage (no real message has
        // id='') and is naturally superseded when a new turn writes a real
        // snapshot with a higher createdAt.
        final snapTables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final snapNames = snapTables.map((r) => r.read<String>('name')).toSet();
        if (snapNames.contains('tracker_snapshots') &&
            snapNames.contains('tracker_rows')) {
          // Aggregate each session's trackers into a JSON array and insert
          // as a single baseline snapshot.
          final sessions = await customSelect(
            'SELECT DISTINCT session_id FROM tracker_rows',
          ).get();
          final now = currentTimestampSeconds();
          for (final s in sessions) {
            final sessionId = s.read<String>('session_id');
            final rows = await customSelect(
              'SELECT name, value, scope, provenance, updated_at '
              'FROM tracker_rows WHERE session_id = ? '
              'ORDER BY name',
              variables: [Variable.withString(sessionId)],
            ).get();
            if (rows.isEmpty) continue;
            final trackersJson = rows
                .map((r) {
                  return jsonEncode({
                    'sessionId': sessionId,
                    'name': r.read<String>('name'),
                    'value': r.read<String>('value'),
                    'scope': r.read<String>('scope'),
                    'provenance': r.read<String>('provenance'),
                    'updatedAt': r.read<int>('updated_at'),
                  });
                })
                .join(',');
            await customStatement(
              'INSERT OR REPLACE INTO tracker_snapshots '
              '(session_id, message_id, swipe_id, agent_swipe_id, '
              'trackers_json, committed, created_at) VALUES '
              "(?, '', 0, 0, ?, 1, ?)",
              [sessionId, '[$trackersJson]', now],
            );
          }
        }
      }
      if (from < 52) {
        // Pipeline settings are now a singleton global stored in
        // SharedPreferences (key 'pipelineSettings'), not per-session Drift
        // rows. Drop the table — per-session overrides are abandoned by
        // explicit user choice (pipeline config is set once via Build Studio
        // and applied uniformly across all chats). The SharedPreferences
        // payload is unaffected; PipelineSettings.fromJson reads the same
        // fields, with new cleaner fields defaulting to their @Default values.
        await m.deleteTable('pipeline_settings_rows');
      }
      if (from < 53) {
        // InfoBlock.agentSwipeId: bind ext blocks to the blue cleaned
        // sub-swipe so blocks launched after the POST-cleaner target the
        // cleaned text, not the raw streamed final. Default -1 = "no agent
        // swipe" (legacy blocks written before the cleaner existed or when
        // the cleaner is disabled — these match by (messageId, swipeId)
        // only, preserving prior behavior).
        final cols = await customSelect(
          'PRAGMA table_info("info_blocks")',
        ).get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        if (!colNames.contains('agent_swipe_id')) {
          await m.addColumn(infoBlocks, infoBlocks.agentSwipeId);
        }
      }
      if (from < 54) {
        // Studio preset DB: all hardcoded Studio prompts (request preset
        // layout blocks, controller ontology fallback prompts, runtime
        // envelope, final brief usage note, hard style contract, cleaner
        // system/audit prompts, ledger prompt, agentic write-loop prompt,
        // beauty shard instructions, cleaner rules extractor prompt, beauty
        // extractor prompt, block router prompt, brief parser fallback,
        // shard synthesizer prompts) migrate to a Drift table so the user can
        // edit them without code changes. Seeded with the current hardcoded
        // values via a single INSERT. See docs/PLAN_STUDIO_PRESET_DB.md.
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        if (!tableNames.contains('studio_preset_rows')) {
          await m.createTable(studioPresetRows);
        }
        // Seed the default preset if no row exists yet.
        final existing = await customSelect(
          'SELECT COUNT(*) AS cnt FROM studio_preset_rows',
        ).getSingle();
        if (existing.read<int>('cnt') == 0) {
          final seedBlocks = studioPresetSeedBlocks();
          await customStatement(
            'INSERT INTO studio_preset_rows '
            '(preset_id, name, blocks_json, updated_at) VALUES '
            "(?, ?, ?, CAST(strftime('%s','now') AS INTEGER))",
            ['default', 'Default Studio Preset', jsonEncode(seedBlocks)],
          );
        }
      }
      if (from < 55) {
        // Studio config overhaul: unbind from user presets, switch to 3 API
        // Config slots (expensive/cheap/cleaner) + studioPresetId.
        // ADD: studio_preset_id, expensive_api_config_id, cheap_api_config_id,
        //      cleaner_api_config_id
        // DROP: source_preset_id, source_preset_hash, routing_mode,
        //       agent_studio_preset_id, final_studio_preset_id,
        //       studio_preset_overrides_json, builder_prompt_template,
        //       selected_block_ids_json, selected_block_ids_initialized,
        //       build_api_config_id, build_model_override
        final cols = await customSelect(
          "PRAGMA table_info('studio_config_rows')",
        ).get();
        final colNames =
            cols.map((r) => r.read<String>('name')).toSet();

        if (!colNames.contains('studio_preset_id')) {
          await m.addColumn(
            studioConfigRows,
            studioConfigRows.studioPresetId,
          );
        }
        if (!colNames.contains('expensive_api_config_id')) {
          await m.addColumn(
            studioConfigRows,
            studioConfigRows.expensiveApiConfigId,
          );
        }
        if (!colNames.contains('cheap_api_config_id')) {
          await m.addColumn(
            studioConfigRows,
            studioConfigRows.cheapApiConfigId,
          );
        }
        if (!colNames.contains('cleaner_api_config_id')) {
          await m.addColumn(
            studioConfigRows,
            studioConfigRows.cleanerApiConfigId,
          );
        }

        // Drop old columns (SQLite 3.35+ supports ALTER TABLE DROP COLUMN).
        final toDrop = [
          'source_preset_id',
          'source_preset_hash',
          'routing_mode',
          'agent_studio_preset_id',
          'final_studio_preset_id',
          'studio_preset_overrides_json',
          'builder_prompt_template',
          'selected_block_ids_json',
          'selected_block_ids_initialized',
          'build_api_config_id',
          'build_model_override',
        ];
        for (final col in toDrop) {
          if (colNames.contains(col)) {
            await customStatement(
              'ALTER TABLE studio_config_rows DROP COLUMN $col',
            );
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

/// Seed blocks for the default Studio preset, migrated from the hardcoded
/// constants in `studio_request_preset.dart`, `studio_controller_ontology.dart`,
/// `studio_prompt_text.dart`, `studio_ledger_prompt.dart`,
/// `agentic_write_request_parser.dart`, `post_cleaner_service.dart`,
/// `studio_beauty_extractor.dart`, `studio_block_router.dart`,
/// `studio_cleaner_rules_extractor.dart`, `studio_shard_synthesizer.dart`,
/// `beauty_shard_instruction.dart`.
///
/// Each block: `{id, name, kind, role, content, enabled, order, section}`.
/// The `section` field groups blocks by pipeline stage:
/// `pregen`, `final`, `cleaner`, `ledger`, `writeloop`, `build`, `brief_parser`.
///
/// IMPORTANT: keep these in sync with the Dart fallback constants until the
/// fallbacks are removed in the cleanup PR. The resolver tries DB first, then
/// falls back to the constant.
List<Map<String, dynamic>> studioPresetSeedBlocks() {
  return <Map<String, dynamic>>[
    // ─── pregen section (agent layout + tracker instructions + slots) ───
    {
      'id': 'pregen_agent_instruction',
      'name': 'Agent instruction (pregen)',
      'kind': 'agent_instruction',
      'role': 'system',
      'content':
          'You are an intermediate Studio agent. Analyze the current roleplay context and produce only a compact operational brief for later agents. Focus on continuity, character truth, scene pressure, and risks. Do not write narrative prose, dialogue, or the final RP response.',
      'enabled': true,
      'order': 0,
      'section': 'pregen',
    },
    {
      'id': 'continuity_task',
      'name': 'Continuity Controller task',
      'kind': 'tracker_instruction',
      'role': 'system',
      'content':
          'Review character, persona, scenario, memory, summary, lore, and recent chat. Produce a compact continuity brief with established facts, who knows what, active constraints, unresolved threads, and contradictions to avoid. Do not write scene prose or dialogue.',
      'enabled': true,
      'order': 1,
      'section': 'pregen',
    },
    {
      'id': 'agency_task',
      'name': 'Agency & Character Controller task',
      'kind': 'tracker_instruction',
      'role': 'system',
      'content':
          "Enforce user autonomy and character authenticity. Never write the user's dialogue, actions, thoughts, feelings, intentions, or decisions. Characters act only from established knowledge, psychology, history, physical limits, and current pressure. Produce constraints only, not prose.",
      'enabled': true,
      'order': 2,
      'section': 'pregen',
    },
    {
      'id': 'narrative_task',
      'name': 'Narrative / Pacing / Style Controller task',
      'kind': 'tracker_instruction',
      'role': 'system',
      'content':
          "Extract narrative mode, pacing, style, POV, tone, genre, and sensory budget into a concise response contract. Classify the user's last turn as ACTION (physical movement, travel, object handling, executed decision — even when dialogue is present), CONVERSATIONAL (mostly speech, no physical progression), ATMOSPHERIC (slow/reflective), or DYNAMIC/MIXED (action + dialogue comparable). Set a qualitative tempo: short, medium, or long. Do NOT invent paragraph counts — the user's preset owns the numbers. When in doubt between action and conversational, prefer action. Include dialogue/action balance and where the response should stop. Do not draft the reply.",
      'enabled': true,
      'order': 3,
      'section': 'pregen',
    },
    {
      'id': 'dialogue_task',
      'name': 'Dialogue Controller task',
      'kind': 'tracker_instruction',
      'role': 'system',
      'content':
          "Guide dialogue cadence and interaction. Prefer purposeful speech when characters can plausibly speak; segment monologues naturally; preserve character voice and subtext. Set a dialogue ratio compatible with the current beat (action beats can be dialogue-heavy; a high ratio does not make an action beat 'conversational'). Do not draft dialogue.",
      'enabled': true,
      'order': 4,
      'section': 'pregen',
    },
    {
      'id': 'guard_task',
      'name': 'Anti-Loop & Prose Guard task',
      'kind': 'tracker_instruction',
      'role': 'system',
      'content':
          'Check the last user message and recent assistant replies for repetition risks. Enforce anti-echo, anti-loop, banlists, forbidden cliches, and prose quality constraints. Produce a guard brief only.',
      'enabled': true,
      'order': 5,
      'section': 'pregen',
    },
    {
      'id': 'world_task',
      'name': 'World / NPC Controller task',
      'kind': 'tracker_instruction',
      'role': 'system',
      'content':
          'Guide living-world and NPC activity. NPCs should act only when the scene supports it and should affect the scene without stealing focus. Produce practical world-state guidance only.',
      'enabled': true,
      'order': 6,
      'section': 'pregen',
    },
    {
      'id': 'meta_task',
      'name': 'Meta-Weaver / OOC Policy task',
      'kind': 'tracker_instruction',
      "role": 'system',
      'content':
          "You are the meta-weaver / OOC interface. Count the assistant messages in the history you see. Read the period rule, persona name, voice, length, format, and wrapper from your assigned meta block (e.g. period 'Every 4 assistant responses', voice 'warm, maternal', wrapper '<lumiaooc>...</lumiaooc>', length '1-3 sentences'). The persona name and voice come entirely from the block — do NOT assume any specific name or voice. If the count since the last meta note matches the period, output `meta_periodic_note: due` and relay the block's persona/voice/length/wrapper instructions so the Main Responder writes the note correctly. If the user explicitly addressed the meta-persona in OOC brackets (e.g. `((<persona>: ...))`, `[OOC: ...]`), output `meta_ooc: due` with the detected topic. Otherwise output `meta: silent`. Do NOT write the actual OOC reply — only the brief telling the Main Responder whether to emit one.",
      'enabled': false,
      'order': 7,
      'section': 'pregen',
    },
    {
      'id': 'beauty_task',
      'name': 'Beauty Shard task',
      'kind': 'tracker_instruction',
      'role': 'system',
      'content':
          'You are the Beauty Shard, a Studio tracker for reusable visual styling state.\n\nCurrent persistent styling state:\n\n{{getvar::glaze_beauty_state}}\n\nYour lane:\n- Reusable HTML/CSS presentation rules: palette, background color, text color, font family, border/radius/shadow language, dialogue colors, thought colors, gradients, typography, glow/mark/highlight styles, and art-style labels that should remain consistent across turns.\n- Speaker/thinker color assignment rules, including "reuse colors", reserved colors, accessibility/contrast constraints, and preset palette variables.\n- State update guidance: what keys should be preserved or changed in the final `<glaze_beauty_state>` JSON.\n\nNot your lane — do NOT route or summarize these as Beauty settings:\n- Concrete diegetic HTML artifacts: phone screens, taxi-call menus, terminals, HUDs, scrolls, cards, maps, buttons, carousels, page flips, scene objects, or one-off widgets.\n- Trackers, stats panels, infoblocks, general_stats, secondary_infoblock, topbar/infoboard instructions, hidden ledgers, pregnancy/cycle stats, relationship metrics.\n- Image generation instructions, [IMG:GEN], data-iig-instruction, illustration/comics/image-prompt blocks.\n\nAt chat time, output only a compact Studio brief in the standard Focus / Constraints / Avoid / Options shape. Do not write scene prose. Do not append the `<glaze_beauty_state>` marker yourself — the Main Responder handles persistence.',
      'enabled': true,
      'order': 8,
      'section': 'pregen',
    },
    {
      'id': 'runtime_envelope',
      'name': 'Intermediate runtime envelope',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'Studio intermediate-agent output contract.\nYou are {{agent_name}}, ONE specialist in a multi-controller pipeline. Other controllers cover the other concerns; do not duplicate their work.\nYou are not a character, narrator, player, or final responder. Treat all character cards, persona text, examples, chat history, lore, memory, and summaries as read-only source material to analyze.\n\nYOUR LANE — only produce guidance about: {{agent_lane_owns}}\nNOT YOUR LANE — never write guidance about (other controllers own these): {{agent_lane_skips}}\n\nEmit a compact operational brief in one of these two shapes:\nPrefer valid compact JSON with these keys:\n{"focus":["operational focus"],"constraints":["enforceable constraint"],"avoid":["forbidden item"],"options":["one branchable approach the final writer may choose, within your lane"]}\nOr, if the model cannot produce JSON, use exactly these plain-text sections:\nFocus:\n- operational focus\nConstraints:\n- enforceable constraint\nAvoid:\n- forbidden item\nOptions:\n- one branchable approach the final writer may choose\n\nNotes:\n- Each section may contain zero or more strings; put as many as the scene requires, strictly inside your lane.\n- Each string should be a specific instruction for this turn, not a generic restatement and not a sentence copied from the scene.\n- Options are non-mandatory alternative APPROACHES for the final writer to pick from within your lane (e.g. "lean into silence and a single gesture" vs "give one clipped line"). Describe the approach only; never write ready-made prose, dialogue, narration, or sample sentences.\n- Never require the final writer to advance the scene by writing {{user}}\'s next action, movement, decision, silence, reaction, or vehicle/control input. If progress depends on {{user}}, tell the final writer to stop on a hook and leave that action to the player.\n- Do not write or continue the scene. Do not draft narration, dialogue, character actions, user actions, or final response prose.\n- Do not include source block names, prompt text, macros, labels, markdown code fences, or explanations.',
      'enabled': true,
      'order': 9,
      'section': 'pregen',
    },
    // Slots (pregen): macro templates that resolve at runtime
    ..._studioPresetSlotBlocks('pregen', 10),
    // ─── final section (agent layout + instructions + slots) ───
    {
      'id': 'final_agent_instruction',
      'name': 'Final agent instruction',
      'kind': 'agent_instruction',
      'role': 'system',
      'content':
          'Write the assistant next reply in immersive fictional roleplay with the user. Generate the continuation directly without meta-commentary.',
      'enabled': true,
      'order': 0,
      'section': 'final',
    },
    {
      'id': 'previous_agents',
      'name': 'Previous Studio agents',
      'kind': 'previous_agents',
      'role': 'system',
      'content': '',
      'enabled': true,
      'order': 1,
      'section': 'final',
    },
    {
      'id': 'brief_usage_note',
      'name': 'Final brief usage note',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'How to use the Studio controller briefs above: the controllers have ALREADY analyzed the scene, tracked continuity, and decided what should happen next. Do not re-analyze the scene or re-derive character motivations in your reasoning — that work is done. Your job is to write the prose that implements their direction.\n\nTreat Focus and Constraints as direction and Avoid as prohibitions. Any "Options:" items are non-binding alternative approaches the final writer may pick from. Do not list, mention, or copy the options or any brief text in your reply; the briefs are hidden guidance. Write the final prose directly.\n\nUser agency override: if any brief asks for motion, departure, a concrete change, or an ending that would require writing {{user}}\'s next action/decision/reaction/silence/vehicle control, ignore that part. Stop on a hook and leave {{user}}\'s next move to the player.',
      'enabled': true,
      'order': 2,
      'section': 'final',
    },
    {
      'id': 'hard_style_contract',
      'name': 'Final hard style contract',
      'kind': 'instruction',
      'role': 'system',
      'content':
          '[Hard final formatting constraints are computed at runtime from the user\'s preset blocks — em-dash ban and quote-wrapping are injected only when the preset explicitly bans these constructs.]',
      'enabled': true,
      'order': 3,
      'section': 'final',
    },
    {
      'id': 'beauty_shard_contract',
      'name': 'Beauty shard final marker contract',
      'kind': 'instruction',
      'role': 'system',
      'content':
          '## Persistent Styling State\n\nYou maintain a styling state across turns so colors, fonts, and visual choices stay consistent. The current state is:\n\n{{getvar::glaze_beauty_state}}\n\nRules:\n- Reuse the colors already assigned to each speaker in "speakers". Do not invent new ones for existing characters.\n- When a new speaker appears, assign them a color that contrasts with the "palette" theme and does not collide with existing speaker colors or any color in "reserved".\n- Update the state when your styling decisions change (new speaker, palette switch, new art style, etc.). If nothing changed, re-emit the same state.\n- At the very END of your response, after all narrative and HTML artifacts, emit exactly one marker with the updated state:\n\n<glaze_beauty_state>\n{"speakers":{"Name":"#hex"},"thoughts":{"Name":"#hex"},"palette":"dark|light","font":"sans-serif","bg":"#hex","art_style":"...","reserved":{"lumia_ooc":"#9370DB"}}\n</glaze_beauty_state>\n\nThe marker is parsed and stripped automatically — the user never sees it in the chat bubble. Do not put the marker inside an HTML artifact or a code block. Do not use apostrophes inside JSON values; use angle quotes or rephrase if needed.',
      'enabled': true,
      'order': 4,
      'section': 'final',
    },
    ..._studioPresetSlotBlocks('final', 5),
    // ─── cleaner section (4 blocks) ───
    {
      'id': 'cleaner_system',
      'name': 'Cleaner system prompt',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'You are a faithful prose editor for a roleplay story. Your job is to clean up the following assistant response: remove clichés and common AI-isms, smooth repetitive phrasings, and fix local continuity errors — while PRESERVING the original voice, energy, imagery, and emotional texture. The text you receive was written with intent; your edits should refine it, not flatten it. Keep what is vivid, specific, and alive; only strip what is generic, overused, or contradictory.',
      'enabled': true,
      'order': 0,
      'section': 'cleaner',
    },
    {
      'id': 'cleaner_aiism',
      'name': 'Cleaner AI-ism cliché list',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'Rules:\n- Keep the same meaning, events, and character voices.\n- PRESERVE vivid, original imagery and figurative language. Metaphors, sensory details, and specific textures are NOT filler — keep them.\n- Remove or rephrase ONLY overused AI-isms and clichés (e.g. "a shiver ran down", "a dance of", "symphony of", "tapestry of", "couldn\'t help but", "a mix of", "sent shivers", "palpable tension"). Do NOT remove original metaphors or unique phrasings just because they are figurative.\n- Remove redundant repetition of the SAME idea within a few sentences — but do not compress distinct beats into one.\n- Do NOT add new content, events, or dialogue.\n- Do NOT change the POV, tense, or the output language. Preserve the language and formatting required by the authoritative rules above.\n- Keep the same approximate length. Do not shorten the text by removing imagery or descriptive passages — only by removing genuine filler.\n- PRESERVE all inline HTML / formatting markup VERBATIM. This includes <font color="...">, <i>, <b>, <em>, <strong>, <mark>, <sub>, <sup>, and any other inline tags. These tags carry the user\'s styling (colored thoughts, colored speech, emphasis) and are NOT markdown to be stripped. Rewrite the prose INSIDE the tags if needed, but never remove, move, or alter the tags themselves, and never collapse <font><i>...</i></font> into plain text. If a sentence with colored markup is rephrased, keep the tags around the rephrased text in the same nesting order.\n- PRESERVE OOC (out-of-character) blocks VERBATIM. OOC blocks are meta-commentary addressed to the user outside the roleplay — they are NOT prose to be cleaned. They may be wrapped in `((...))`, `[OOC: ...]`, `(OOC: ...)`, `((OOC: ...))`, or appear as clearly meta lines (e.g. "((Ghost in the machine: ...))", narrator notes to the user, system-style asides). Do not remove, rephrase, translate, reformat, or alter OOC blocks in any way. Clean only the in-roleplay prose around them. If the entire response is an OOC block, return it unchanged.\n- PRESERVE meta-OOC blocks VERBATIM. A meta-OOC block is any tag whose name contains "ooc" (e.g. `<lumiaooc>`, `<oocnote>`, `<metaooc>`, `<sisterooc>`). It is meta-commentary from the meta-persona to the user outside the roleplay — NOT narrative prose. Do not rewrite, move, rephrase, translate, reformat, or delete it. Clean only the in-roleplay prose around it. If the response contains a meta-OOC block, keep it exactly as-is in the same position.\n- Return ONLY the cleaned text, no explanation. Inline HTML tags described above are part of the content, not markdown fences — keep them. OOC blocks are also part of the content — keep them verbatim. Do not wrap the output in ``` fences.',
      'enabled': true,
      'order': 1,
      'section': 'cleaner',
    },
    {
      'id': 'cleaner_audit',
      'name': 'Cleaner audit prompt',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'You are a continuity auditor for a roleplay story. Your job is to find contradictions between the assistant response and the provided context.\n\nInstructions:\n- Check the response against ALL provided context.\n- Report ONLY direct contradictions: wrong names, wrong relationships, wrong locations, personality conflicts, world-fact errors, persona identity errors.\n- Do NOT report style issues, cliches, or prose quality.\n- Do NOT suggest fixes or rewrites. Only describe the contradiction.\n- If no contradictions found, return: {"ok": true}\n- If contradictions found, return: {"ok": false, "issues": ["...", "..."]}\n\nReturn ONLY the JSON, no other text.',
      'enabled': true,
      'order': 2,
      'section': 'cleaner',
    },
    {
      'id': 'cleaner_rules',
      'name': 'Cleaner rules (user-defined)',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'BANNED WORDS (never use these, even if the original has them):\n{{bannedWords}}\n\nAVOID (specific patterns to steer away from):\n{{avoidInstructions}}\n\nPREFER (style direction to lean into):\n{{styleInstructions}}',
      'enabled': true,
      'order': 3,
      'section': 'cleaner',
    },
    // ─── ledger section (1 block) ───
    {
      'id': 'ledger_system',
      'name': 'Ledger system prompt',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'You are Studio Ledger, an internal continuity and state extractor.\nYou do not write story prose.\nYou maintain session-canon facts for future generations.\n\nUse the final assistant response, latest user message, previous ledger, recent chat, current state, and existing memory.\n\nRules:\n- Preserve prior state unless contradicted by the final response.\n- Promote only durable, future-relevant facts into durableFacts.\n- Temporary posture/outfit/props stay in the visible ledger unless they became important.\n- Do not create quests unless an explicit task/goal exists.\n- Do not create persona stats unless already tracked.\n- Do not infer romance/trust jumps without evidence in the final response.\n- Session state overrides character-card baseline.\n- If an arc from the card is resolved in session canon, mark it completed with do_not_reopen=true.\n- Never write future events as facts.\n- Pending user choices are hooks, not completed events.\n- Do not convert threats, plans, questions, offers, or pending choices into completed facts.\n- Distinguish planned, suggested, threatened, attempted, completed, failed, cancelled, and unknown event states.\n- Do not mark an entity present only because it is mentioned.\n- Do not mark an entity absent unless it explicitly leaves, dies, is left behind, or the scene changes.\n- Return <studio_ledger> plus <glaze_memory_export> JSON.\n- Prefer patch ops in the ops list for persistence. Do not rewrite the whole world state.\n- Keep entity/relationship/arc/world state compact. Update current truth; do not create a history log.\n- Never output ledger text as story prose or a chat message.\n- Entity state keys: npc:Name.relationship_to_user, npc:Name.attitude_to_user, npc:Name.knowledge, npc:Name.boundaries, npc:Name.card_overrides\n- Relationship keys: relationship:A:B.relationship, relationship:A:B.attitude, relationship:A:B.knowledge\n- Arc keys: arc:id.status, arc:id.summary, arc:id.do_not_reopen, arc:id.card_override\n- World/scene keys: world:location, world:time, world:date, world:active_threats, scene.present_entities, scene.absent_backstory_entities',
      'enabled': true,
      'order': 0,
      'section': 'ledger',
    },
    // ─── writeloop section (1 block) ───
    {
      'id': 'writeloop_system',
      'name': 'Agentic write-loop prompt',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'You are a memory agent for a roleplay conversation. After each turn, you decide what facts to persist so they survive context truncation.\n\nRecent conversation:\n{{recentHistoryText}}\n\nCurrent trackers:\n{{trackersBlock}}\n\nExisting memory entries already in the MemoryBook:\n{{existingBlock}}\n\nDecide what to write. You have two tools:\n\n1. updateTracker — lightweight key-value state that persists across turns (mood, location, relationship status, inventory, ongoing promises).\n2. writeMemory — a pending memory draft for significant events, revelations, promises. These require user approval before becoming active.\n\nRespond with ONLY a JSON object (no markdown, no explanation):\n{\n  "trackers": [\n    {"name": "mood", "value": "happy", "scope": "chat"},\n    {"name": "location", "value": "tavern"}\n  ],\n  "memories": [\n    {"title": "Lucy reveals the chip", "content": "...", "keys": ["Lucy", "chip"]},\n    {"existingEntryId": "mem_abc123", "title": "Lucy\'s plan", "content": "new fact only", "keys": ["Lucy"]}\n  ]\n}\n\nRules:\n- Only write trackers that CHANGED or are NEW. Don\'t repeat unchanged trackers.\n- Only create memory drafts for SIGNIFICANT events (not every turn).\n- If an event merely ADDS detail to an existing memory entry, write a memory request whose `existingEntryId` is the id of the existing entry and whose `content` contains only the NEW facts — do not restate or rewrite the existing entry. The pipeline will append your newFacts to the existing entry verbatim.\n- Do NOT create a new memory entry (no existingEntryId) that duplicates an existing entry\'s title/keys. Instead, write an append-only update with existingEntryId set.\n- If nothing is worth persisting, return: {"trackers": [], "memories": []}\n- Keep tracker values short (1-5 words).\n- Memory content should be 1-3 sentences describing what happened and why it matters.',
      'enabled': true,
      'order': 0,
      'section': 'writeloop',
    },
    // ─── build section (build-time prompts) ───
    {
      'id': 'build_router',
      'name': 'Build-time block router prompt',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'You are a build-time Studio router. You are NOT roleplaying and you are NOT writing any reply. Your only job is to assign each roleplay preset block to the single most appropriate agent bucket.\n\nAvailable agent buckets:\n{{agentBuckets}}\n\nThere is also ONE special bucket:\n- drop: DROP. Use ONLY for a block that is itself a chain-of-thought / reasoning / thinking TEMPLATE — i.e. the block\'s primary purpose is to make the model produce hidden step-by-step reasoning (e.g. a "CoT" block whose body is mostly a "ILDAR...ILDAE" scaffold of internal planning steps). This multi-agent pipeline already does the reasoning, so such a block is redundant and must be dropped.\n\nRouting rules:\n- Assign every block to exactly ONE bucket id (one of the agent buckets above, or "drop").\n- Choose the bucket whose purpose best matches what the block actually does, judging by its name AND content (not just keywords).\n- Use "drop" ONLY for genuine reasoning/CoT templates as defined above. A block that merely MENTIONS reasoning or a ilda tag is NOT a reasoning template:\n  * A language/format block (e.g. "everything after ILDAE must be written in Russian") is about output language — route it to the final responder bucket, do NOT drop it.\n  * A meta/persona/lore block that references a ilda block while describing OOC behavior is NOT a reasoning template — route it to the matching agent bucket, do NOT drop it.\n- A block that defines the final output format, language, or the visible reply itself belongs to the final responder bucket.\n- If genuinely unsure, pick the final responder bucket. NEVER drop a block when unsure. Never invent a bucket.\n\nOutput STRICT JSON only, no markdown fences, no prose, in this exact shape:\n{"assignments": [{"block": "<block id>", "bucket": "<bucket id>"}, ...]}\n\nPreset blocks to route:\n{{blockLines}}',
      'enabled': true,
      'order': 0,
      'section': 'build',
    },
    {
      'id': 'build_synthesizer',
      'name': 'Build-time shard synthesizer prompt',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'You are a build-time Studio compiler. You are not roleplaying and you are not writing the next chat reply.\n\nBuild a reusable instruction prompt for one later Studio agent from the assigned roleplay preset blocks.\n\nCreate the build-time promptShard for ONE visible Studio agent/controller.\nController: {{controllerName}}\nPurpose: {{controllerPurpose}}\n\nRules:\n- Output only the final instruction text for this controller, no JSON and no markdown wrapper.\n- This promptShard will be saved in the database and reused later; write stable operating instructions, not current-scene content.\n- The later agent will prepare guidance for the roleplay game. It must not act as a character, narrator, player, or final responder unless this is the Main Responder controller.\n- Preserve enforceable rules from assigned blocks, but compress duplicates.\n- Do not include hidden chain-of-thought directives, ilda tags, or instructions to reveal reasoning.\n- If assigned blocks contain meta-weaver/OOC behavior, convert it to silent final-model policy or OOC interface rules; do not make this controller write meta-persona scene prose.\n- Intermediate controllers must produce operational briefs only, never in-scene prose or dialogue.\n- {{controllerOutputContract}}\n\nAssigned preset blocks:\n{{blocksSummary}}',
      'enabled': true,
      'order': 1,
      'section': 'build',
    },
    {
      'id': 'beauty_extractor',
      'name': 'Beauty extractor prompt',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'You are a build-time Beauty Extractor for a Studio multi-agent roleplay pipeline. You are NOT roleplaying and you are NOT routing every block. Your only job is to identify reusable visual styling settings that should be owned by the Beauty Shard tracker.\n\nSELECT a block as beauty ONLY when its primary purpose is reusable presentation state, such as:\n- global HTML/CSS style defaults\n- palette / color scheme\n- background color, main text color, font family\n- per-speaker dialogue colors or thought colors\n- gradients, text shadows, glow/highlight/mark styles, typography defaults\n- rules like "reuse colors for the same speaker" or "keep the same font/style"\n\nDO NOT SELECT blocks whose primary purpose is semantic behavior or a concrete artifact, even if they contain colors:\n- Lumia/OOC/meta-persona behavior, periodic OOC rules, wrappers like <lumiaooc>\n- trackers, stats panels, relationship metrics, cycle/pregnancy, hidden ledgers\n- infoblocks/general_stats/secondary_infoblock/topbar/infoboard\n- image generation, [IMG:GEN], data-iig-instruction, comics/illustration/image prompts\n- concrete HTML widgets/windows: phone screens, taxi-call menus, terminals, HUDs, scrolls, cards, maps, buttons, carousels, page flips, scene objects\n\nReserved-color rule:\n- If a semantic block (for example Lumia/OOC) contains a reserved color, DO NOT select that block as beauty.\n- Instead, copy only the reserved color into reserved_style_notes / normalized_style_contract.reserved so Beauty Shard knows not to reuse it for speakers.\n- If unsure whether a color is global style or semantic widget/persona color, leave the block unselected and optionally add a conservative reserved note.\n\nOutput STRICT JSON only, no markdown fences, no prose, in this exact shape:\n{\n  "beauty_block_ids": ["<block id whose primary purpose is reusable style>"],\n  "reserved_style_notes": [\n    {"source_block_id":"<id>","key":"lumia_ooc","value":"#9370DB","note":"reserved for Lumia/OOC; do not assign to speakers"}\n  ],\n  "normalized_style_contract": {\n    "palette":"dark|light|unknown",\n    "background":"#hex or empty",\n    "text":"#hex or empty",\n    "font":"font-family or empty",\n    "speaker_colors":"rule summary",\n    "reserved":{"key":"value"}\n  }\n}\n\nPreset blocks:\n{{blockLines}}',
      'enabled': true,
      'order': 2,
      'section': 'build',
    },
    {
      'id': 'cleaner_rules_extractor',
      'name': 'Cleaner rules extractor prompt',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'You are a build-time Studio compiler. You are not roleplaying and you are not writing the next chat reply.\n\nRead the roleplay preset blocks below and extract prose-guardian rules that a POST-generation cleaner LLM should enforce. Output ONLY a JSON object with three string fields and nothing else:\n\n{\n  "bannedWords": "comma-separated list of words/phrases the cleaner must remove or never emit; empty string if none",\n  "avoidInstructions": "imperative instructions for what the cleaner should avoid or minimize (e.g. cliches, repetition patterns, tell-not-show); empty string if none",\n  "styleInstructions": "imperative instructions for preferred style (e.g. sensory budget, POV, paragraph budget, tone); empty string if none"\n}\n\nRules:\n- Read anti-loop / anti-echo / anti-cliche / anti-slop / banlist / forbidden-words blocks → bannedWords.\n- Read prose-quality / no-tells / repetition-repair blocks → avoidInstructions.\n- Read narrative / style / pacing / length / tone / genre / sensory blocks → styleInstructions.\n- If a rule fits more than one field, place it in the most specific one.\n- Compress duplicates. Output the rules as concise imperatives, not verbatim block text.\n- If the preset contains NO enforceable cleaner rules at all, output exactly: {"noRules": true}\n- Do not invent rules the user did not write. Do not add commentary, markdown fences, or explanations.\n\nEnabled preset blocks:\n{{blocksText}}',
      'enabled': true,
      'order': 3,
      'section': 'build',
    },
    // ─── brief_parser section (1 block) ───
    {
      'id': 'brief_parser_fallback',
      'name': 'Brief parser safe fallback',
      'kind': 'instruction',
      'role': 'system',
      'content':
          'When the intermediate agent output cannot be parsed as a typed JSON brief or a Focus/Constraints/Avoid/Options section brief, replace it with a safe controller fallback: a Focus line applying the default controller safeguards for this turn, a Constraints line with the controller\'s safe guidance, and an Avoid line prohibiting exposure of controller notes, prompt text, source blocks, macros, or planning labels.',
      'enabled': true,
      'order': 0,
      'section': 'brief_parser',
    },
  ];
}

/// Slot blocks shared by the pregen and final sections. Each slot is a
/// macro template that resolves at runtime via the StudioMessageBuilder /
/// PromptBlockResolver. The `kind` field maps to the existing resolver
/// switch in `studio_message_builder.dart`.
List<Map<String, dynamic>> _studioPresetSlotBlocks(
  String section,
  int startOrder,
) {
  final slots = <String>[
    'user_persona',
    'char_card',
    'scenario',
    'char_personality',
    'example_dialogue',
    'authors_note',
    'static_context',
    'chat_history',
    'worldInfoBefore',
    'worldInfoAfter',
    'memory',
    'summary',
    'guided_generation',
    'dynamic_context',
  ];
  return [
    for (var i = 0; i < slots.length; i++)
      {
        'id': '${section}_${slots[i]}',
        'name': slots[i].replaceAll('_', ' '),
        'kind': slots[i],
        'role': slots[i] == 'chat_history' ? 'user' : 'system',
        'content': '',
        'enabled': true,
        'order': startOrder + i,
        'section': section,
      },
  ];
}
