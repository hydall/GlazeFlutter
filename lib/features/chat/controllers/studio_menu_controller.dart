import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/studio_api_config_resolver.dart';
import '../../../core/llm/studio_cleaner_rules_extractor.dart';
import '../../../core/llm/studio_decomposition_service.dart';
import '../../../core/llm/transport/transport_factory.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/preset.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/models/tracker.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/memory_agent_providers.dart';
import '../../../core/state/preset_resolution.dart';
import '../../../core/utils/time_helpers.dart';
import '../../settings/api_list_provider.dart';

/// Controller for the Studio tracker dialog, separating business logic from
/// UI. The widget holds `build`, the private `_TrackerRow`/`_StatusChip`
/// widgets, and the bottom-sheet/dialog interactions (`_editAgentModel`,
/// `_editAgentShard`, `_openAdvanced`); this controller owns session config
/// state and the read-modify-write + LLM-build pipeline.
///
/// Mirrors the [MemoryBookController] pattern (`WidgetRef`-backed controller
/// constructed in `initState`).
class StudioMenuController {
  final WidgetRef _ref;
  final String _charId;
  final String _sessionId;

  StudioConfig? _config;
  List<Tracker> _trackers = const [];
  bool _loading = true;
  bool _loadingModels = false;
  bool _building = false;
  final Set<String> _regeneratingAgentIds = {};

  StudioMenuController(this._ref, this._sessionId, this._charId);

  StudioConfig? get config => _config;
  List<Tracker> get trackers => _trackers;
  bool get loading => _loading;
  bool get loadingModels => _loadingModels;
  bool get building => _building;
  Set<String> get regeneratingAgentIds => Set.unmodifiable(_regeneratingAgentIds);

  /// Effective routing mode, falling back to `verbatim` when unset.
  String get _effectiveRoutingMode =>
      (_config?.routingMode.isNotEmpty ?? false)
          ? _config!.routingMode
          : 'verbatim';

  Future<void> load() async {
    final repo = _ref.read(studioConfigRepoProvider);
    final snapshotRepo = _ref.read(trackerSnapshotRepoProvider);
    final trackerRepo = _ref.read(trackerRepoProvider);
    // Warm the API list so model suggestions are available when the user taps
    // a tracker's model chip.
    await _ref.read(apiListProvider.future);
    final config = await repo.getBySessionId(_sessionId);
    // Read tracker state from snapshots (preferred) with a tracker_rows
    // fallback for legacy sessions. Use getLatest (not just committed) so the
    // user sees the most recent state even if not yet committed.
    final snapshot = await snapshotRepo.getLatest(_sessionId);
    final trackers =
        snapshot?.trackers ?? await trackerRepo.getBySessionId(_sessionId);
    _config = config;
    _trackers = trackers;
    _loading = false;
  }

  /// Resolve the [ApiConfig] a tracker runs against, mirroring
  /// [AgentRunner]'s resolution: the Studio's `runApiConfigId` if set,
  /// otherwise the chat's active API config. Trackers reuse this config's
  /// provider/endpoint/key — only the model id is overridden per agent — so
  /// the model list must come from this exact provider.
  ApiConfig? resolveTrackerApiConfig() {
    return StudioApiConfigResolver(
      apiConfigs: _ref.read(apiListProvider).value ?? const <ApiConfig>[],
      activeConfig: _ref.read(activeApiConfigProvider),
    ).resolveRunConfig(_config?.runApiConfigId ?? '');
  }

  /// Resolve the [ApiConfig] used for the one-shot build-time decomposition
  /// LLM call. The Studio's `buildApiConfigId` if set, otherwise the chat's
  /// active API config. The Studio's `buildModelOverride` is applied on top
  /// when set so the user can run the builder on a different model than chat.
  ApiConfig? resolveBuildApiConfig() {
    return StudioApiConfigResolver(
      apiConfigs: _ref.read(apiListProvider).value ?? const <ApiConfig>[],
      activeConfig: _ref.read(activeApiConfigProvider),
    ).resolveBuildConfig(
      _config?.buildApiConfigId ?? '',
      _config?.buildModelOverride ?? '',
    );
  }

  /// The chat's effective preset, or `null` if none is selected.
  Preset? get effectivePreset => _ref.read(
    effectivePresetForChatProvider((charId: _charId, sessionId: _sessionId)),
  );

  Future<void> toggleEnabled(bool enabled) async {
    final repo = _ref.read(studioConfigRepoProvider);
    final current = _config;
    if (current == null) return;
    final updated = current.copyWith(enabled: enabled);
    await repo.upsert(updated);
    _config = updated;
  }

  Future<void> toggleAgent(StudioAgent agent, bool enabled) async {
    final repo = _ref.read(studioConfigRepoProvider);
    final current = _config;
    if (current == null) return;
    final agents = current.agents.map((a) {
      if (a.id == agent.id) return a.copyWith(enabled: enabled);
      return a;
    }).toList();
    final updated = current.copyWith(agents: agents);
    await repo.upsert(updated);
    _config = updated;
  }

  Future<void> setAgentModelOverride(
    StudioAgent agent,
    String modelOverride,
  ) async {
    final repo = _ref.read(studioConfigRepoProvider);
    final current = _config;
    if (current == null) return;
    final agents = current.agents.map((a) {
      if (a.id == agent.id) return a.copyWith(modelOverride: modelOverride);
      return a;
    }).toList();
    final updated = current.copyWith(agents: agents);
    await repo.upsert(updated);
    _config = updated;
  }

  Future<void> setAgentPromptShard(StudioAgent agent, String shard) async {
    final repo = _ref.read(studioConfigRepoProvider);
    final current = _config;
    if (current == null) return;
    final agents = current.agents.map((a) {
      if (a.id == agent.id) return a.copyWith(promptShard: shard);
      return a;
    }).toList();
    final updated = current.copyWith(
      agents: agents,
      updatedAt: currentTimestampSeconds(),
    );
    await repo.upsert(updated);
    _config = updated;
  }

  /// Fetch the live model list for the resolved tracker API config's
  /// provider. Returns an empty list on fetch failure (the widget surfaces a
  /// toast in that case). Sets [loadingModels] while in flight so the widget
  /// can show a blocking overlay.
  Future<List<String>> fetchModelsForTrackerConfig() async {
    final apiConfig = resolveTrackerApiConfig();
    if (apiConfig == null) return const [];
    final endpoint = apiConfig.endpoint.trim();
    final apiKey = apiConfig.apiKey.trim();
    _loadingModels = true;
    try {
      final fetched = await pickChatTransport(
        apiConfig.protocol,
      ).fetchModels(endpoint: endpoint, apiKey: apiKey);
      final models =
          fetched
              .map((m) => (m['id'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort();
      return models;
    } catch (_) {
      return const [];
    } finally {
      _loadingModels = false;
    }
  }

  /// Build Studio trackers from the chat's effective preset (auto
  /// decomposition). Runs the [StudioDecompositionService] against the
  /// resolved build API, then persists the resulting agents + broadcast
  /// blocks + preset hash. The last agent (highest order) is the generator;
  /// all earlier agents are pre-generation trackers — the exact shape
  /// [MemoryStudioService.runTrackerCycle] consumes.
  ///
  /// Returns the toast message to surface on success/failure. The widget owns
  /// the actual `GlazeToast.show` call (UI concern).
  Future<String> buildStudio() async {
    _building = true;
    try {
      final preset = effectivePreset;
      if (preset == null) {
        return 'No preset available. Create or select a preset first.';
      }
      final apiConfig = resolveBuildApiConfig();
      if (apiConfig == null) {
        return 'No API configured. Set one up in API settings first.';
      }

      final decompositionService = _ref.read(studioDecompositionServiceProvider);
      final agents = await decompositionService.decompose(
        preset: preset,
        sessionId: _sessionId,
        apiConfig: apiConfig,
        builderPromptTemplate: _config?.builderPromptTemplate ?? '',
        routingMode: _effectiveRoutingMode,
      );
      if (agents.isEmpty) {
        throw Exception('Decomposition returned no agents');
      }

      // Capture cross-cutting "broadcast" blocks (output language + prose
      // guards) verbatim so the POST-cleaner can apply the user's own rules.
      final broadcastBlocks = decompositionService
          .collectBroadcastBlocks(preset)
          .map((b) {
            final name = b.name.isNotEmpty ? b.name : b.id;
            return '[Block: $name]\n${b.content.trim()}';
          })
          .where((s) => s.trim().isNotEmpty)
          .toList();

      final now = currentTimestampSeconds();
      final existing = _config;
      final newConfig = (existing ?? StudioConfig(sessionId: _sessionId))
          .copyWith(
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

      await _ref.read(studioConfigRepoProvider).upsert(newConfig);
      _config = newConfig;

      // Second LLM call: extract POST-cleaner style rules from the preset and
      // write them into PipelineSettings. Non-fatal: tracker build already
      // succeeded; a failure here surfaces a toast but does not roll back.
      final cleanerToast = await _extractCleanerRules(
        preset: preset,
        apiConfig: apiConfig,
      );

      return 'Studio built: ${agents.length} agents from "${preset.name}"$cleanerToast';
    } catch (e) {
      return 'Build failed: $e';
    } finally {
      _building = false;
    }
  }

  /// Second LLM call in [buildStudio]: extracts banned/avoid/style rules from
  /// [preset] via [StudioCleanerRulesExtractor] and writes them into the three
  /// `postCleaner*` string fields of `PipelineSettings`. Returns a toast
  /// fragment describing the outcome (always non-empty, prefixed with a space
  /// and a separator so it can be appended to the main build toast).
  Future<String> _extractCleanerRules({
    required Preset preset,
    required ApiConfig apiConfig,
  }) async {
    final extractor = _ref.read(studioCleanerRulesExtractorProvider);
    try {
      final rules = await extractor.extract(
        preset: preset,
        apiConfig: apiConfig,
      );
      if (rules.isEmpty) {
        // Should not happen — the extractor throws [NoCleanerRulesFoundException]
        // for the empty case. Treat as a defensive no-op.
        return '. No cleaner rules extracted.';
      }
      final pipeline = _ref.read(pipelineSettingsProvider);
      final updated = pipeline.copyWith(
        postCleanerBannedWords: rules.bannedWords,
        postCleanerAvoidInstructions: rules.avoidInstructions,
        postCleanerStyleInstructions: rules.styleInstructions,
      );
      await _ref.read(pipelineSettingsProvider.notifier).save(updated);
      return '. Cleaner rules extracted.';
    } on NoCleanerRulesFoundException {
      return '. No cleaner rules found in preset.';
    } catch (e) {
      return '. Cleaner rules extraction failed: $e';
    }
  }

  /// Regenerate one tracker's `promptShard` from its source preset blocks via
  /// [StudioDecompositionService.regenerateAgentInstruction]. Uses the same
  /// build API config as [buildStudio]. Single-agent regen reuses the
  /// deterministic keyword bucketing (no LLM router call); the build-time LLM
  /// map only matters for a full decompose.
  ///
  /// Returns the toast message to surface. No-ops if the agent is already
  /// regenerating or the config is missing.
  Future<String> regenerateAgentInstruction(StudioAgent agent) async {
    final current = _config;
    if (current == null || _regeneratingAgentIds.contains(agent.id)) {
      return '';
    }
    _regeneratingAgentIds.add(agent.id);
    try {
      final preset = effectivePreset;
      if (preset == null) {
        return 'No preset available. Cannot regenerate instruction.';
      }
      final apiConfig = resolveBuildApiConfig();
      if (apiConfig == null) {
        return 'No API configured. Set one up in API settings first.';
      }

      final decompositionService = _ref.read(studioDecompositionServiceProvider);
      final updatedAgent = await decompositionService.regenerateAgentInstruction(
        preset: preset,
        agent: agent,
        apiConfig: apiConfig,
        builderPromptTemplate: current.builderPromptTemplate,
        routingMode: current.routingMode.isNotEmpty
            ? current.routingMode
            : 'verbatim',
      );
      if (_config == null) return '';
      final agents = current.agents.map((a) {
        return a.id == agent.id ? updatedAgent.copyWith(order: a.order) : a;
      }).toList();
      final updatedConfig = current.copyWith(
        agents: agents,
        sourcePresetHash: StudioDecompositionService.computePresetHash(
          preset.blocks.where((b) => b.enabled).toList(),
        ),
        buildApiConfigId: apiConfig.id,
        updatedAt: currentTimestampSeconds(),
      );
      await _ref.read(studioConfigRepoProvider).upsert(updatedConfig);
      _config = updatedConfig;
      return 'Instruction regenerated for "${agent.name.isEmpty ? agent.id : agent.name}".';
    } catch (e) {
      return 'Regenerate failed: $e';
    } finally {
      _regeneratingAgentIds.remove(agent.id);
    }
  }

  /// Find the current [Tracker.value] for [name], truncated for display.
  /// Returns `null` if no tracker with this name exists for the session —
  /// the agent may be configured but not yet have run.
  String? trackerValueFor(String name) {
    final match = _trackers.where((t) => t.name == name).toList();
    if (match.isEmpty) return null;
    final value = match.first.value.trim();
    if (value.isEmpty) return null;
    if (value.length <= 80) return value;
    return '${value.substring(0, 77)}...';
  }
}
