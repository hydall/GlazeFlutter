import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../llm/studio_controller_ontology.dart';
import '../models/studio_config.dart';
import '../utils/time_helpers.dart';
import 'db_provider.dart';

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

    final now = currentTimestampSeconds();
    final agents = StudioControllerOntology.buildDefaultAgents(
      sessionId: sessionId,
      now: now,
    );

    final newConfig = (existing ?? StudioConfig(sessionId: sessionId)).copyWith(
      agents: agents,
      enabled: true,
      updatedAt: now,
      createdAt: existing?.createdAt ?? now,
    );

    await repo.upsert(newConfig);

    return 'Studio built: ${agents.length} agents';
  }

}
