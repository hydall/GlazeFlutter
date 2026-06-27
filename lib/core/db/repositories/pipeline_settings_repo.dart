import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_db.dart';
import '../tables.dart';
import '../../models/pipeline_settings.dart';
import '../../state/pipeline_settings_provider.dart';
import '../../utils/time_helpers.dart';

part 'pipeline_settings_repo.g.dart';

@DriftAccessor(tables: [PipelineSettingsRows])
class PipelineSettingsRepo extends DatabaseAccessor<AppDatabase>
    with _$PipelineSettingsRepoMixin {
  PipelineSettingsRepo(super.db, this._ref);

  final Ref _ref;

  /// Returns the per-session [PipelineSettings], creating a row seeded from
  /// [PipelineGlobalSettings] defaults if none exists yet. Mirrors the
  /// `MemoryBookRepo.ensureForSession` pattern: global defaults are folded into
  /// the new per-session row at creation time, so subsequent reads are pure
  /// per-session overrides.
  Future<PipelineSettings> ensureForSession(String sessionId) async {
    final existing = await getBySessionId(sessionId);
    if (existing != null) return existing;
    final global = _ref.read(pipelineGlobalSettingsProvider);
    final settings = PipelineSettings(
      generationSource: global.generationSource,
      generationModel: global.generationModel,
      generationEndpoint: global.generationEndpoint,
      generationApiKey: global.generationApiKey,
      generationTemperature: global.generationTemperature,
      generationMaxTokens: global.generationMaxTokens,
      classifierEnabled: global.classifierEnabled,
      classifierSource: global.classifierSource,
      classifierModel: global.classifierModel,
      classifierEndpoint: global.classifierEndpoint,
      classifierApiKey: global.classifierApiKey,
      classifierTimeoutMs: global.classifierTimeoutMs,
      sidecarEnabled: global.sidecarEnabled,
      sidecarSource: global.sidecarSource,
      sidecarModel: global.sidecarModel,
      sidecarEndpoint: global.sidecarEndpoint,
      sidecarApiKey: global.sidecarApiKey,
      sidecarTimeoutMs: global.sidecarTimeoutMs,
      agenticWriteEnabled: global.agenticWriteEnabled,
      postCleanerEnabled: global.postCleanerEnabled,
      postCleanerTemperature: global.postCleanerTemperature,
      postCleanerMaxTokens: global.postCleanerMaxTokens,
      consolidationEnabled: global.consolidationEnabled,
      consolidationThreshold: global.consolidationThreshold,
      consolidationSource: global.consolidationSource,
      consolidationModel: global.consolidationModel,
      consolidationEndpoint: global.consolidationEndpoint,
      consolidationApiKey: global.consolidationApiKey,
      consolidationTimeoutMs: global.consolidationTimeoutMs,
    );
    await updateSettings(sessionId, settings);
    return settings;
  }

  Future<PipelineSettings?> getBySessionId(String sessionId) async {
    final row = await (select(
      pipelineSettingsRows,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (row == null) return null;
    return _rowToModel(row);
  }

  Future<void> updateSettings(String sessionId, PipelineSettings settings) {
    return into(pipelineSettingsRows).insertOnConflictUpdate(
      PipelineSettingsRowsCompanion.insert(
        sessionId: sessionId,
        settingsJson: Value(jsonEncode(settings.toJson())),
        updatedAt: Value(currentTimestampSeconds()),
      ),
    );
  }

  /// Copies pipeline settings from [fromSessionId] to [toSessionId] when
  /// branching a chat session. Mirrors `MemoryBookRepo.copyForSessionBranch`.
  Future<void> copyToSession({
    required String fromSessionId,
    required String toSessionId,
  }) async {
    final source = await getBySessionId(fromSessionId);
    if (source == null) return;
    await updateSettings(toSessionId, source);
  }

  Future<void> deleteBySession(String sessionId) {
    return (delete(
      pipelineSettingsRows,
    )..where((t) => t.sessionId.equals(sessionId))).go();
  }

  // ── Cloud-sync raw-map API ───────────────────────────────────────────────
  //
  // Cloud sync exchanges raw JSON maps (not typed models) to avoid coupling
  // the wire format to the freezed shape. Each entry is
  // `{sessionId, settings: <PipelineSettings.toJson>, updatedAt}`.

  /// All rows for cloud-sync manifest building. Returns raw maps so the
  /// adapter layer does not depend on the freezed model.
  Future<List<Map<String, dynamic>>> getAllRaw() async {
    final rows = await select(pipelineSettingsRows).get();
    return rows.map(_rowToRawMap).toList();
  }

  /// One row as a raw map, or `null` if missing.
  Future<Map<String, dynamic>?> getRawBySessionId(String sessionId) async {
    final row = await (select(
      pipelineSettingsRows,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    return row == null ? null : _rowToRawMap(row);
  }

  /// Upserts a raw `{sessionId, settings, updatedAt}` map from cloud.
  Future<void> putRaw(Map<String, dynamic> entry) async {
    final sessionId = entry['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) return;
    final settingsJson = entry['settings'] is Map
        ? jsonEncode(entry['settings'])
        : (entry['settings'] as String? ?? '{}');
    final updatedAt = entry['updatedAt'] as int?;
    await into(pipelineSettingsRows).insertOnConflictUpdate(
      PipelineSettingsRowsCompanion.insert(
        sessionId: sessionId,
        settingsJson: Value(settingsJson),
        updatedAt: Value(updatedAt ?? currentTimestampSeconds()),
      ),
    );
  }

  Map<String, dynamic> _rowToRawMap(PipelineSettingsRow row) {
    dynamic settings;
    try {
      settings = jsonDecode(row.settingsJson);
    } catch (_) {
      settings = <String, dynamic>{};
    }
    return {
      'sessionId': row.sessionId,
      'settings': settings,
      'updatedAt': row.updatedAt,
    };
  }

  PipelineSettings _rowToModel(PipelineSettingsRow row) {
    try {
      return PipelineSettings.fromJson(
        jsonDecode(row.settingsJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return const PipelineSettings();
    }
  }
}
