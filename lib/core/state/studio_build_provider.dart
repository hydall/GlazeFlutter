import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../llm/studio_api_config_resolver.dart';
import '../llm/studio_cleaner_rules_extractor.dart';
import '../llm/studio_decomposition_service.dart';
import '../models/api_config.dart';
import '../models/preset.dart';
import '../models/studio_config.dart';
import '../utils/time_helpers.dart';
import 'db_provider.dart';
import 'memory_agent_providers.dart';
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
/// and watches the resulting status, while the actual LLM pipeline runs on the
/// provider's [Ref] and keeps going regardless of widget lifecycle.
///
/// Guarantees:
/// - **Survives close:** the build Future is owned by the notifier, not the
///   widget. Closing the dialog never cancels or abandons it; the result is
///   persisted to Drift and the toast is buffered in [StudioBuildStatus].
/// - **No duplicate builds:** [build] no-ops when a build is already in flight
///   for the same `sessionId`, so re-opening the dialog and pressing the button
///   again cannot launch a second concurrent decomposition.
/// - **UI re-attaches:** a re-opened dialog reads `status(sessionId).building`
///   and shows its "Building Studio…" overlay again; on completion it consumes
///   the buffered toast.
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
    // Fire-and-forget: deliberately NOT awaited. The Future is owned by the
    // notifier (provider scope), so it outlives the dialog that triggered it.
    // ignore: discarded_futures
    _runBuild(sessionId: sessionId, charId: charId);
    return true;
  }

  /// Read and clear the buffered result toast for [sessionId]. The dialog calls
  /// this after showing the toast so it is not shown again on the next open.
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
      message = await _decomposeAndPersist(
        sessionId: sessionId,
        charId: charId,
      );
    } catch (e) {
      message = 'Build failed: $e';
    }
    _set(
      sessionId,
      StudioBuildStatus(building: false, resultMessage: message),
    );
  }

  /// The build pipeline, ported verbatim from the old
  /// `StudioMenuController.buildStudio` but running on the provider [Ref] so it
  /// survives the dialog. Returns the toast message.
  Future<String> _decomposeAndPersist({
    required String sessionId,
    required String charId,
  }) async {
    final preset = ref.read(
      effectivePresetForChatProvider((charId: charId, sessionId: sessionId)),
    );
    if (preset == null) {
      return 'No preset available. Create or select a preset first.';
    }
    final repo = ref.read(studioConfigRepoProvider);
    final existing = await repo.getBySessionId(sessionId);

    final apiConfig = _resolveBuildApiConfig(existing);
    if (apiConfig == null) {
      return 'No API configured. Set one up in API settings first.';
    }

    final decompositionService = ref.read(studioDecompositionServiceProvider);
    final routingMode = (existing?.routingMode.isNotEmpty ?? false)
        ? existing!.routingMode
        : 'verbatim';
    final agents = await decompositionService.decompose(
      preset: preset,
      sessionId: sessionId,
      apiConfig: apiConfig,
      builderPromptTemplate: existing?.builderPromptTemplate ?? '',
      routingMode: routingMode,
    );
    if (agents.isEmpty) {
      throw Exception('Decomposition returned no agents');
    }

    final broadcastBlocks = decompositionService
        .collectBroadcastBlocks(preset)
        .map((b) {
          final name = b.name.isNotEmpty ? b.name : b.id;
          return '[Block: $name]\n${b.content.trim()}';
        })
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final now = currentTimestampSeconds();
    final newConfig = (existing ?? StudioConfig(sessionId: sessionId)).copyWith(
      agents: agents,
      enabled: true,
      sourcePresetId: preset.id,
      sourcePresetHash: StudioDecompositionService.computePresetHash(
        preset.blocks.where((b) => b.enabled).toList(),
      ),
      buildApiConfigId: apiConfig.id,
      broadcastBlocks: broadcastBlocks,
      updatedAt: now,
      createdAt: existing?.createdAt ?? now,
    );

    await repo.upsert(newConfig);

    final cleanerToast = await _extractCleanerRules(
      preset: preset,
      apiConfig: apiConfig,
    );

    return 'Studio built: ${agents.length} agents from "${preset.name}"$cleanerToast';
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

  Future<String> _extractCleanerRules({
    required Preset preset,
    required ApiConfig apiConfig,
  }) async {
    final extractor = ref.read(studioCleanerRulesExtractorProvider);
    try {
      final rules = await extractor.extract(
        preset: preset,
        apiConfig: apiConfig,
      );
      if (rules.isEmpty) {
        return '. No cleaner rules extracted.';
      }
      final pipeline = ref.read(pipelineSettingsProvider);
      final updated = pipeline.copyWith(
        postCleanerBannedWords: rules.bannedWords,
        postCleanerAvoidInstructions: rules.avoidInstructions,
        postCleanerStyleInstructions: rules.styleInstructions,
      );
      await ref.read(pipelineSettingsProvider.notifier).save(updated);
      return '. Cleaner rules extracted.';
    } on NoCleanerRulesFoundException {
      return '. No cleaner rules found in preset.';
    } catch (e) {
      return '. Cleaner rules extraction failed: $e';
    }
  }
}
