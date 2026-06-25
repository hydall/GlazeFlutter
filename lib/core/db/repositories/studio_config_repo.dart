import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/studio_config.dart';
import '../../utils/time_helpers.dart';
import '../app_db.dart';
import '../../../features/cloud_sync/sync_repo_interfaces.dart';

class StudioConfigRepo implements SyncStudioConfigStore {
  final AppDatabase db;

  const StudioConfigRepo(this.db);

  Future<StudioConfig?> getBySessionId(String sessionId) async {
    final row = await (db.select(
      db.studioConfigRows,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (row == null) return null;
    final binding = _rowToModel(row);
    final profileId = binding.profileId;
    if (profileId.isEmpty || profileId == binding.sessionId) {
      return binding;
    }
    final profile = await getByProfileId(profileId);
    return profile?.copyWith(
          sessionId: binding.sessionId,
          enabled: binding.enabled,
          profileId: profile.profileId.isNotEmpty
              ? profile.profileId
              : profileId,
        ) ??
        binding;
  }

  Future<StudioConfig?> getByProfileId(String profileId) async {
    final row =
        await (db.select(db.studioConfigRows)..where(
              (t) =>
                  t.profileId.equals(profileId) & t.sessionId.equals(profileId),
            ))
            .getSingleOrNull();
    if (row != null) return _rowToModel(row);
    final fallback = await (db.select(
      db.studioConfigRows,
    )..where((t) => t.profileId.equals(profileId))).getSingleOrNull();
    return fallback == null ? null : _rowToModel(fallback);
  }

  Future<List<StudioConfig>> getProfiles() async {
    final rows = await db.select(db.studioConfigRows).get();
    final byProfile = <String, StudioConfig>{};
    for (final row in rows) {
      final config = _rowToModel(row);
      final id = config.profileId.isNotEmpty
          ? config.profileId
          : config.sessionId;
      final existing = byProfile[id];
      if (existing == null || config.sessionId == id) {
        byProfile[id] = config.copyWith(profileId: id);
      }
    }
    final profiles = byProfile.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return profiles;
  }

  @override
  Future<List<StudioConfig>> getAll() => getProfiles();

  @override
  Future<StudioConfig?> getById(String id) => getByProfileId(id);

  @override
  Future<void> put(StudioConfig config) => upsert(config);

  @override
  Future<void> delete(String id) async {
    await (db.delete(
      db.studioConfigRows,
    )..where((t) => t.profileId.equals(id))).go();
  }

  Future<void> bindSessionToProfile({
    required String sessionId,
    required String profileId,
    bool enabled = true,
  }) async {
    final profile = await getByProfileId(profileId);
    if (profile == null) return;
    await upsert(
      profile.copyWith(
        sessionId: sessionId,
        profileId: profileId,
        enabled: enabled,
        createdAt: currentTimestampSeconds(),
        updatedAt: currentTimestampSeconds(),
      ),
    );
  }

  Future<void> upsert(StudioConfig config) async {
    await _upsertRow(config);
    final profileId = config.profileId.isNotEmpty
        ? config.profileId
        : config.sessionId;
    if (profileId != config.sessionId) {
      await _upsertRow(
        config.copyWith(sessionId: profileId, profileId: profileId),
      );
    }
  }

  Future<void> _upsertRow(StudioConfig config) {
    return db
        .into(db.studioConfigRows)
        .insertOnConflictUpdate(
          StudioConfigRowsCompanion.insert(
            sessionId: config.sessionId,
            profileId: Value(
              config.profileId.isNotEmpty ? config.profileId : config.sessionId,
            ),
            profileName: Value(config.profileName),
            enabled: Value(config.enabled),
            agentsJson: Value(
              jsonEncode(config.agents.map((a) => a.toJson()).toList()),
            ),
            sourcePresetId: Value(config.sourcePresetId),
            finalPresetId: Value(config.finalPresetId),
            agentStudioPresetId: Value(config.agentStudioPresetId),
            finalStudioPresetId: Value(config.finalStudioPresetId),
            studioPresetOverridesJson: Value(
              jsonEncode(
                config.studioPresetOverrides.map((p) => p.toJson()).toList(),
              ),
            ),
            sourcePresetHash: Value(config.sourcePresetHash),
            buildApiConfigId: Value(config.buildApiConfigId),
            runApiConfigId: Value(config.runApiConfigId),
            builderPromptTemplate: Value(config.builderPromptTemplate),
            maxFinalHistoryMessages: Value(config.maxFinalHistoryMessages),
            routingMode: Value(config.routingMode),
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
        profileId: source.profileId.isNotEmpty
            ? source.profileId
            : source.sessionId,
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
    List<StudioPresetOverride> studioPresetOverrides;
    try {
      final list = jsonDecode(row.studioPresetOverridesJson) as List<dynamic>;
      studioPresetOverrides = list
          .map((e) => StudioPresetOverride.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      studioPresetOverrides = const [];
    }

    return StudioConfig(
      sessionId: row.sessionId,
      profileId: row.profileId.isNotEmpty ? row.profileId : row.sessionId,
      profileName: row.profileName,
      enabled: row.enabled,
      agents: agents,
      sourcePresetId: row.sourcePresetId,
      finalPresetId: row.finalPresetId,
      agentStudioPresetId: row.agentStudioPresetId,
      finalStudioPresetId: row.finalStudioPresetId,
      studioPresetOverrides: studioPresetOverrides,
      sourcePresetHash: row.sourcePresetHash,
      buildApiConfigId: row.buildApiConfigId,
      runApiConfigId: row.runApiConfigId,
      builderPromptTemplate: row.builderPromptTemplate,
      maxFinalHistoryMessages: row.maxFinalHistoryMessages,
      routingMode: row.routingMode,
      selectedBlockIds: selectedBlockIds,
      selectedBlockIdsInitialized: row.selectedBlockIdsInitialized,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
