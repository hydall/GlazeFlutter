import '../models/api_config.dart';
import '../models/studio_config.dart';
import 'agent_runner.dart' show ResolvedAgentConfig;
import 'transport/llm_protocol.dart';

/// Single home for the studio/agent API-config resolution policies that were
/// previously copied across `AgentRunner.resolveAgentConfig`,
/// `StudioMenuDialog._resolveTrackerApiConfig` / `_resolveBuildApiConfig`
/// (plan §1.1).
///
/// This is a **pure** specialist: it operates on an already-fetched
/// [apiConfigs] list plus the [activeConfig], so it has no `Ref` dependency and
/// no async I/O. Call sites fetch those inputs (each differs — `AgentRunner`
/// awaits `apiListProvider.future`, the dialog reads synchronously) and then
/// delegate the policy here. Behavior is preserved verbatim from the originals.
class StudioApiConfigResolver {
  final List<ApiConfig> apiConfigs;
  final ApiConfig? activeConfig;

  const StudioApiConfigResolver({
    required this.apiConfigs,
    this.activeConfig,
  });

  /// Resolve the [ApiConfig] used to RUN trackers / agents: the studio's
  /// `runApiConfigId` if it resolves to a saved config, otherwise the active
  /// chat config. Returns `null` when neither is available.
  ///
  /// Mirrors `StudioMenuDialog._resolveTrackerApiConfig` and the non-custom
  /// branch of `AgentRunner.resolveAgentConfig`.
  ApiConfig? resolveRunConfig(String runApiConfigId) {
    if (runApiConfigId.isNotEmpty) {
      final byRunId =
          apiConfigs.where((c) => c.id == runApiConfigId).firstOrNull;
      if (byRunId != null) return byRunId;
    }
    return activeConfig;
  }

  /// Resolve the [ApiConfig] used for the one-shot build-time decomposition
  /// call: the studio's `buildApiConfigId` if set, otherwise the active chat
  /// config, with [modelOverride] applied on top when non-empty. Returns
  /// `null` when no config is available.
  ///
  /// Mirrors `StudioMenuDialog._resolveBuildApiConfig`.
  ApiConfig? resolveBuildConfig(String buildApiConfigId, String modelOverride) {
    if (buildApiConfigId.isNotEmpty) {
      final byBuildId =
          apiConfigs.where((c) => c.id == buildApiConfigId).firstOrNull;
      if (byBuildId != null) {
        return modelOverride.isNotEmpty
            ? byBuildId.copyWith(model: modelOverride)
            : byBuildId;
      }
    }
    final active = activeConfig;
    if (active == null) return null;
    return modelOverride.isNotEmpty
        ? active.copyWith(model: modelOverride)
        : active;
  }

  /// Resolve a single agent's full [ResolvedAgentConfig].
  ///
  /// - `modelSource == 'custom'` → use the agent's [StudioAgent.model] id to
  ///   pick a saved config and apply [StudioAgent.modelOverride]; if the id is
  ///   unknown, fall back to the agent's own endpoint/model with [current]'s
  ///   key and stream flag.
  /// - otherwise → resolve via [resolveRunConfig] (`runApiConfigId` or active,
  ///   falling back to [current]) and apply [StudioAgent.modelOverride].
  ///
  /// Mirrors `AgentRunner.resolveAgentConfig` verbatim. [current] is the chat's
  /// active API config used as the final fallback.
  ResolvedAgentConfig resolveAgentConfig(
    StudioAgent agent,
    ApiConfig current,
    String runApiConfigId,
  ) {
    if (agent.modelSource == 'custom') {
      final selected =
          apiConfigs.where((c) => c.id == agent.model).firstOrNull;
      if (selected != null) {
        return ResolvedAgentConfig.fromApiConfig(
          selected,
          modelOverride: agent.modelOverride,
        );
      }
      return ResolvedAgentConfig(
        endpoint: agent.endpoint,
        apiKey: current.apiKey,
        model: agent.modelOverride.isNotEmpty
            ? agent.modelOverride
            : agent.model,
        protocol: LlmProtocol.openai,
        stream: current.stream,
      );
    }

    final active = resolveRunConfig(runApiConfigId) ?? current;
    return ResolvedAgentConfig.fromApiConfig(
      active,
      modelOverride: agent.modelOverride,
    );
  }
}
