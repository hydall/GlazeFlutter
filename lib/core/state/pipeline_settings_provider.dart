import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/pipeline_settings.dart';
import 'shared_prefs_provider.dart';

/// Global pipeline LLM settings, persisted in SharedPreferences under the
/// 'pipelineSettings' key. Loaded once at startup. This is a singleton global —
/// the same [PipelineSettings] instance applies to every chat session.
///
/// Previously a per-session Drift row (`pipeline_settings_rows`) merged with a
/// [PipelineGlobalSettings] subset; that table was dropped in schema v52 and
/// the two freezed classes were merged into this single [PipelineSettings]
/// shape.
final pipelineSettingsProvider =
    StateNotifierProvider<PipelineSettingsNotifier, PipelineSettings>(
      (ref) => PipelineSettingsNotifier(ref),
    );

class PipelineSettingsNotifier extends StateNotifier<PipelineSettings> {
  final Ref _ref;
  PipelineSettingsNotifier(this._ref) : super(const PipelineSettings());

  /// Current schema version for pipeline settings migration. Bump when
  /// adding a new migration step in [_applyMigrations].
  static const int kCurrentSchemaVersion = 1;

  /// SharedPreferences key storing the schema version integer.
  static const String _kVersionKey = 'pipelineSettingsSchemaVersion';

  Future<void> load() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    final raw = prefs.getString('pipelineSettings');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final migrated = _migrateLegacySidecarJson(json);
        final version = prefs.getInt(_kVersionKey) ?? 0;
        if (version < kCurrentSchemaVersion) {
          _applyMigrations(migrated, fromVersion: version);
          await prefs.setInt(_kVersionKey, kCurrentSchemaVersion);
          state = PipelineSettings.fromJson(migrated);
          await prefs.setString('pipelineSettings', jsonEncode(state.toJson()));
        } else {
          state = PipelineSettings.fromJson(migrated);
        }
      } catch (_) {}
    } else {
      await prefs.setInt(_kVersionKey, kCurrentSchemaVersion);
    }
  }

  Future<void> save(PipelineSettings settings) async {
    state = settings;
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    await prefs.setString('pipelineSettings', jsonEncode(settings.toJson()));
  }

  Map<String, dynamic> _migrateLegacySidecarJson(Map<String, dynamic> json) {
    final migrated = Map<String, dynamic>.from(json);
    migrated.putIfAbsent('auxSource', () => migrated['sidecarSource']);
    migrated.putIfAbsent('auxModel', () => migrated['sidecarModel']);
    migrated.putIfAbsent('auxEndpoint', () => migrated['sidecarEndpoint']);
    migrated.putIfAbsent('auxApiKey', () => migrated['sidecarApiKey']);
    migrated.putIfAbsent('auxTimeoutMs', () => migrated['sidecarTimeoutMs']);
    return migrated;
  }

  /// Applies migrations from [fromVersion] up to [kCurrentSchemaVersion].
  /// Each migration step mutates [json] in place.
  void _applyMigrations(Map<String, dynamic> json, {required int fromVersion}) {
    if (fromVersion < 1) {
      _migrateV1(json);
    }
  }

  /// Migration v0 → v1: several PipelineSettings bool fields changed their
  /// @Default from false to true because the Post Building Menu (the only UI
  /// that exposed their toggles) was removed. Existing installs that still
  /// have the old `false` value persisted in SharedPreferences are upgraded
  /// to `true` so the pipeline runs with the new intended defaults.
  ///
  /// Only upgrades fields that are explicitly `false` in the JSON — if the
  /// user had set them to `true`, they stay `true`. Fields absent from the
  /// JSON are not touched here; `fromJson` will use the new `@Default(true)`.
  ///
  /// Not upgraded (kept at user's choice / old default):
  /// - agentWriteApprovalRequired (stays false)
  /// - memoryDedupAutoEnabled (stays false, manual Dedup only)
  /// - postCleanerDisableReasoning (disable flag, stays false)
  void _migrateV1(Map<String, dynamic> json) {
    const fieldsToUpgrade = <String>[
      'postCleanerEnabled',
      'postCleanerCharacterCheckEnabled',
      'studioLedgerEnabled',
      'agenticWriteEnabled',
      'agenticWriteBlockNextGen',
    ];
    for (final field in fieldsToUpgrade) {
      if (json[field] == false) {
        json[field] = true;
      }
    }
  }
}
