import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../llm/studio_api_config_resolver.dart';
import '../llm/studio_controller_ontology.dart';
import '../models/api_config.dart';
import '../models/studio_config.dart';
import '../utils/time_helpers.dart';
import 'db_provider.dart';
import 'preset_resolution.dart';
import '../../features/settings/api_list_provider.dart';

/// Outcome of a finished Studio build, surfaced to whichever dialog is open
/// (or the next one to open) so the user always sees the result toast.
class StudioBuildStatus {
  /// True while the build pipeline is in flight.
  final bool building;

  /// Toast text from the most recent finished build. Empty until a build
  /// completes. The UI shows it once, then calls [StudioBuildNotifier.consume]
  /// so it is not shown twice.
  final String resultMessage;

  const StudioBuildStatus({
    this.building = false,
    this.resultMessage = '',
  });

  StudioBuildStatus copyWith({bool? building, String? resultMessage}) =>
      StudioBuildStatus(
        building: building ?? this.building,
        resultMessage: resultMessage ?? this.resultMessage,
      );
}

/// Session-scoped Studio build state that lives at the provider (root) scope,
/// NOT inside the Studio dialog widget. This is what lets a build survive the
/// dialog being closed: the dialog only triggers [StudioBuildNotifier.build]
/// and watches the resulting status, while the actual build runs on the
/// provider's [Ref] and keeps going regardless of widget lifecycle.
final studioBuildProvider =
    NotifierProvider<StudioBuildNotifier, Map<String, StudioBuildStatus>>(
  StudioBuildNotifier.new,
);

class StudioBuildNotifier extends Notifier<Map<String, StudioBuildStatus>> {
  @override
  Map<String, StudioBuildStatus> build() => const {};

  /// Status for one session (defaults to idle/empty).
  StudioBuildStatus status(String sessionId) =>
      state[sessionId] ?? const StudioBuildStatus();

  bool isBuilding(String sessionId) => status(sessionId).building;

  /// Start a Studio build for [sessionId]. Returns immediately; the build runs
  /// in the background and updates [state] when it finishes. No-op (returns
  /// false) if a build is already running for this session.
  bool startBuild({required String sessionId, required String charId}) {
    if (isBuilding(sessionId)) return false;
    _set(sessionId, const StudioBuildStatus(building: true, resultMessage: ''));
    _runBuild(sessionId: sessionId, charId: charId);
    return true;
  }

  /// Read and clear the buffered result toast for [sessionId].
  String consume(String sessionId) {
    final current = status(sessionId);
    if (current.resultMessage.isEmpty) return '';
    _set(sessionId, current.copyWith(resultMessage: ''));
    return current.resultMessage;
  }

  void _set(String sessionId, StudioBuildStatus value) {
    state = {...state, sessionId: value};
  }

  Future<void> _runBuild({
    required String sessionId,
    required String charId,
  }) async {
    String message;
    try {
      message = await _buildAndPersist(sessionId: sessionId, charId: charId);
    } catch (e) {
      message = 'Build failed: $e';
    }
    _set(
      sessionId,
      StudioBuildStatus(building: false, resultMessage: message),
    );
  }

  /// Build Studio agents directly from the controller ontology (no LLM
  /// decomposition). The agent prompt shards come from the DB Studio preset
  /// (resolved at chat time via [StudioPromptResolver]). Studio is now
  /// unbound from user presets — the controller slots are fixed, and the
  /// user edits the preset blocks in the preset editor.
  Future<String> _buildAndPersist({
    required String sessionId,
    required String charId,
  }) async {
    final repo = ref.read(studioConfigRepoProvider);
    final existing = await repo.getBySessionId(sessionId);

    final apiConfig = _resolveBuildApiConfig(existing);
    if (apiConfig == null) {
      return 'No API configured. Set one up in API settings first.';
    }

    final now = currentTimestampSeconds();
    final agents = _buildAgentsFromOntology(sessionId: sessionId, now: now);

    final newConfig = (existing ?? StudioConfig(sessionId: sessionId)).copyWith(
      agents: agents,
      enabled: true,
      updatedAt: now,
      createdAt: existing?.createdAt ?? now,
    );

    await repo.upsert(newConfig);

    return 'Studio built: ${agents.length} agents';
  }

  /// Build the fixed set of Studio controller agents from
  /// [StudioControllerOntology.specs]. Each agent gets the spec's fallback
  /// prompt as its initial shard (the DB preset blocks are resolved at chat
  /// time, not stored on the agent).
  List<StudioAgent> _buildAgentsFromOntology({
    required String sessionId,
    required int now,
  }) {
    final agents = <StudioAgent>[];
    for (var i = 0; i < StudioControllerOntology.specs.length; i++) {
      final spec = StudioControllerOntology.specs[i];
      agents.add(
        StudioAgent(
          id: 'agent_${sessionId}_${spec.id}_$now',
          name: spec.name,
          role: 'system',
          promptShard: [PromptShardBlock(content: spec.fallbackPrompt)],
          order: i,
          enabled: spec.id != 'meta',
          temperature: spec.temperature,
          maxTokens: spec.maxTokens,
          timeoutMs: spec.timeoutMs,
          refreshPolicy: spec.refreshPolicy,
          invalidationSignals: spec.invalidationSignals,
          phase: spec.phase,
          contextSize: spec.contextSize > 0 ? spec.contextSize : 5,
        ),
      );
    }
    return agents;
  }

  ApiConfig? _resolveBuildApiConfig(StudioConfig? existing) {
    return StudioApiConfigResolver(
      apiConfigs: ref.read(apiListProvider).value ?? const <ApiConfig>[],
      activeConfig: ref.read(activeApiConfigProvider),
    ).resolveBuildConfig(
      existing?.buildApiConfigId ?? '',
      existing?.buildModelOverride ?? '',
    );
  }
}
