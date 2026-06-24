import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/studio_config.dart';
import '../../utils/time_helpers.dart';
import '../app_db.dart';

class StudioConfigRepo {
  final AppDatabase db;

  const StudioConfigRepo(this.db);

  Future<StudioConfig?> getBySessionId(String sessionId) async {
    final row = await (db.select(
      db.studioConfigRows,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (row == null) return null;
    return _rowToModel(row);
  }

  Future<void> upsert(StudioConfig config) {
    return db
        .into(db.studioConfigRows)
        .insertOnConflictUpdate(
          StudioConfigRowsCompanion.insert(
            sessionId: config.sessionId,
            enabled: Value(config.enabled),
            agentsJson: Value(
              jsonEncode(config.agents.map((a) => a.toJson()).toList()),
            ),
            sourcePresetId: Value(config.sourcePresetId),
            finalPresetId: Value(config.finalPresetId),
            agentStudioPresetId: Value(config.agentStudioPresetId),
            finalStudioPresetId: Value(config.finalStudioPresetId),
            sourcePresetHash: Value(config.sourcePresetHash),
            buildApiConfigId: Value(config.buildApiConfigId),
            runApiConfigId: Value(config.runApiConfigId),
            selectedBlockIdsJson: Value(jsonEncode(config.selectedBlockIds)),
            selectedBlockIdsInitialized: Value(
              config.selectedBlockIdsInitialized,
            ),
            createdAt: Value(config.createdAt),
            updatedAt: Value(currentTimestampSeconds()),
          ),
        );
  }

  Future<void> deleteBySessionId(String sessionId) {
    return (db.delete(
      db.studioConfigRows,
    )..where((t) => t.sessionId.equals(sessionId))).go();
  }

  Future<void> copyForSessionBranch({
    required String fromSessionId,
    required String toSessionId,
  }) async {
    final source = await getBySessionId(fromSessionId);
    if (source == null) return;
    await upsert(
      source.copyWith(
        sessionId: toSessionId,
        createdAt: currentTimestampSeconds(),
        updatedAt: currentTimestampSeconds(),
      ),
    );
  }

  StudioConfig _rowToModel(StudioConfigRow row) {
    List<StudioAgent> agents;
    try {
      final list = jsonDecode(row.agentsJson) as List<dynamic>;
      agents = list
          .map((e) => StudioAgent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      agents = [];
    }
    List<String> selectedBlockIds;
    try {
      selectedBlockIds = (jsonDecode(row.selectedBlockIdsJson) as List<dynamic>)
          .whereType<String>()
          .toList(growable: false);
    } catch (_) {
      selectedBlockIds = const [];
    }

    return StudioConfig(
      sessionId: row.sessionId,
      enabled: row.enabled,
      agents: agents,
      sourcePresetId: row.sourcePresetId,
      finalPresetId: row.finalPresetId,
      agentStudioPresetId: row.agentStudioPresetId,
      finalStudioPresetId: row.finalStudioPresetId,
      sourcePresetHash: row.sourcePresetHash,
      buildApiConfigId: row.buildApiConfigId,
      runApiConfigId: row.runApiConfigId,
      selectedBlockIds: selectedBlockIds,
      selectedBlockIdsInitialized: row.selectedBlockIdsInitialized,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
