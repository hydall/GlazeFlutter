import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/studio_config.dart';
import '../../llm/studio_controller_ontology.dart';
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
            buildModelOverride: Value(config.buildModelOverride),
            runModelOverride: Value(config.runModelOverride),
            builderPromptTemplate: Value(config.builderPromptTemplate),
            maxFinalHistoryMessages: Value(config.maxFinalHistoryMessages),
            routingMode: Value(config.routingMode),
            broadcastBlocksJson: Value(jsonEncode(config.broadcastBlocks)),
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
    List<String> broadcastBlocks;
    try {
      broadcastBlocks = (jsonDecode(row.broadcastBlocksJson) as List<dynamic>)
          .whereType<String>()
          .toList(growable: false);
    } catch (_) {
      broadcastBlocks = const [];
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

    return _normalizeLoadedConfig(
      StudioConfig(
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
        buildModelOverride: row.buildModelOverride,
        runModelOverride: row.runModelOverride,
        builderPromptTemplate: row.builderPromptTemplate,
        maxFinalHistoryMessages: row.maxFinalHistoryMessages,
        routingMode: row.routingMode,
        broadcastBlocks: broadcastBlocks,
        selectedBlockIds: selectedBlockIds,
        selectedBlockIdsInitialized: row.selectedBlockIdsInitialized,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      ),
    );
  }

  /// Silent migration of loaded Studio configs:
  ///
  /// 1. Meta-Weaver (plan §Part 6): upgrade from the old `'static'` refresh
  ///    policy + default `contextSize` to the meta-weaver architecture —
  ///    `refreshPolicy: 'turn'` (runs every turn so it can count assistant
  ///    messages and apply the period rule) and `contextSize: 15` (enough
  ///    history to count periods up to ~10).
  ///
  /// 2. All trackers run every turn (Marinara parity, see
  ///    `studio_controller_ontology.dart`): any agent still carrying
  ///    `refreshPolicy: 'scene'` or `'static'` from a pre-parity build is
  ///    migrated to `'turn'`. The `'scene'` policy's gate was a regex over
  ///    the last user message only — it missed real scene changes that
  ///    weren't phrased with time-skip words, and stale scene-cached briefs
  ///    degraded the final response. Running every turn is cheaper to reason
  ///    about and matches upstream Marinara-Engine's `runInterval: 1`
  ///    default for all tracker agents.
  ///
  /// Returns [config] unchanged when no agent needs migration. This is a
  /// normalization in memory, so existing configs benefit immediately without
  /// a rebuild.
  StudioConfig _normalizeLoadedConfig(StudioConfig config) {
    if (config.agents.isEmpty) return config;
    final migrated = <StudioAgent>[];
    var changed = false;
    for (final agent in config.agents) {
      var current = agent;
      if (_isMetaWeaver(current) &&
          (current.refreshPolicy != 'turn' || current.contextSize < 15)) {
        current = current.copyWith(
          refreshPolicy: 'turn',
          contextSize: current.contextSize < 15 ? 15 : current.contextSize,
        );
        changed = true;
      }
      if (current.refreshPolicy != 'turn') {
        current = current.copyWith(refreshPolicy: 'turn');
        changed = true;
      }
      migrated.add(current);
    }
    final withBeauty = _ensureBeautyShardAgent(config, migrated);
    if (!identical(withBeauty, migrated)) changed = true;
    return changed ? config.copyWith(agents: withBeauty) : config;
  }

  List<StudioAgent> _ensureBeautyShardAgent(
    StudioConfig config,
    List<StudioAgent> agents,
  ) {
    if (agents.any(_isBeautyShard)) return agents;
    final spec = StudioControllerOntology.specs.firstWhere(
      (s) => s.id == 'beauty',
      orElse: () => throw StateError('Beauty Shard spec missing'),
    );
    final finalIdx = agents.indexWhere(_isFinalResponder);
    final insertAt = finalIdx >= 0 ? finalIdx : agents.length;
    final beauty = StudioAgent(
      id: 'agent_${config.sessionId}_beauty_migrated',
      name: spec.name,
      role: 'system',
      promptShard: [PromptShardBlock(content: spec.fallbackPrompt)],
      order: insertAt,
      enabled: true,
      modelSource: 'current',
      temperature: spec.temperature,
      maxTokens: spec.maxTokens,
      timeoutMs: spec.timeoutMs,
      sourceBlockNames:
          'Beauty Shard fallback (rebuild Studio to route preset style blocks)',
      refreshPolicy: spec.refreshPolicy,
      invalidationSignals: spec.invalidationSignals,
      phase: spec.phase,
      contextSize: spec.contextSize > 0 ? spec.contextSize : 5,
    );
    final updated = <StudioAgent>[
      ...agents.take(insertAt),
      beauty,
      ...agents.skip(insertAt),
    ];
    return [
      for (var i = 0; i < updated.length; i++) updated[i].copyWith(order: i),
    ];
  }

  bool _isBeautyShard(StudioAgent agent) {
    final id = agent.id.toLowerCase();
    final name = agent.name.toLowerCase();
    final text = '$id\n$name';
    return id == 'beauty' ||
        text.contains('_beauty_') ||
        text.contains('beauty shard') ||
        name == 'beauty';
  }

  bool _isFinalResponder(StudioAgent agent) {
    final id = agent.id.toLowerCase();
    final name = agent.name.toLowerCase();
    final text = '$id\n$name';
    return id == 'final' ||
        text.contains('_final_') ||
        text.contains('main responder') ||
        name == 'final';
  }

  /// True if [agent] is the Meta-Weaver / OOC Policy controller. Matches by
  /// id/name (the controller spec id is `meta`, name is
  /// `Meta-Weaver / OOC Policy`). Falls back to substring contains so older
  /// configs with slightly different names still migrate.
  bool _isMetaWeaver(StudioAgent agent) {
    final id = agent.id.toLowerCase();
    final name = agent.name.toLowerCase();
    return id.contains('_meta_') ||
        id == 'meta' ||
        name.contains('meta-weaver') ||
        name.contains('meta weaver') ||
        name.contains('ooc policy') ||
        name.contains('lumia policy');
  }
}
