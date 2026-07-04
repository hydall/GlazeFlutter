import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/settings/api_list_provider.dart';
import '../../models/api_config.dart';
import '../../models/studio_config.dart';
import '../../state/db_provider.dart';
import '../agent_runner.dart' show ResolvedAgentConfig;
import '../studio_api_config_resolver.dart';

/// Resolves which API config an agent uses.
///
/// With the 3-slot model (v55):
/// - [apiConfigId] — if non-empty, overrides `runApiConfigId` from the
///   StudioConfig. Callers pass `cheapApiConfigId` for trackers,
///   `expensiveApiConfigId` for the final generator, `cleanerApiConfigId`
///   for post-processing agents. When empty, falls back to `runApiConfigId`
///   then to the active chat config.
/// - Model overrides are global PipelineSettings values configured from the
///   Studio menu: studioFinalModelOverride for the final generator,
///   postCleanerModel for post-processing trackers, studioTrackerModelOverride
///   for pre-gen trackers. The final generator intentionally does not read
///   PipelineSettings.memoryBookApi.generationModel because that field belongs
///   to MemoryBook generation / agentic write-loop routing.
class AgentConfigResolver {
  final Ref _ref;

  AgentConfigResolver(this._ref);

  Future<ResolvedAgentConfig> resolveAgentConfig(
    StudioAgent agent,
    ApiConfig current,
    String sessionId, {
    bool isFinalResponse = false,
    String? apiConfigId,
  }) async {
    await _ref.read(apiListProvider.future);
    final apiConfigs = _ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final runApiConfigId = (apiConfigId != null && apiConfigId.isNotEmpty)
        ? apiConfigId
        : await _readRunApiConfigId(sessionId);
    final resolver = StudioApiConfigResolver(
      apiConfigs: apiConfigs,
      activeConfig: _ref.read(activeApiConfigProvider),
    );
    final pipeline = _ref.read(pipelineSettingsProvider);
    if (isFinalResponse) {
      return resolver
          .resolveAgentConfig(
            current,
            runApiConfigId,
            pipeline.studioAgent.studioFinalModelOverride,
          )
          .copyWithSampling(
            topP: pipeline.studioAgent.studioFinalTopP,
            topK: pipeline.studioAgent.studioFinalTopK,
            frequencyPenalty: pipeline.studioAgent.studioFinalFrequencyPenalty,
            presencePenalty: pipeline.studioAgent.studioFinalPresencePenalty,
            omitTemperature: pipeline.studioAgent.studioFinalOmitTemperature,
            omitTopP: pipeline.studioAgent.studioFinalOmitTopP,
          );
    } else if (agent.phase == 'post_processing') {
      if (pipeline.cleaner.postCleanerModel.isNotEmpty) {
        return resolver
            .resolveAgentConfig(
              current,
              runApiConfigId,
              pipeline.cleaner.postCleanerModel,
            )
            .copyWithSampling(
              topP: pipeline.cleaner.postCleanerTopP,
              topK: pipeline.cleaner.postCleanerTopK,
              frequencyPenalty: pipeline.cleaner.postCleanerFrequencyPenalty,
              presencePenalty: pipeline.cleaner.postCleanerPresencePenalty,
              omitTemperature: pipeline.cleaner.postCleanerOmitTemperature,
              omitTopP: pipeline.cleaner.postCleanerOmitTopP,
            );
      }
      return resolver
          .resolveAgentConfig(current, runApiConfigId, '')
          .copyWithSampling(
            topP: pipeline.cleaner.postCleanerTopP,
            topK: pipeline.cleaner.postCleanerTopK,
            frequencyPenalty: pipeline.cleaner.postCleanerFrequencyPenalty,
            presencePenalty: pipeline.cleaner.postCleanerPresencePenalty,
            omitTemperature: pipeline.cleaner.postCleanerOmitTemperature,
            omitTopP: pipeline.cleaner.postCleanerOmitTopP,
          );
    } else if (pipeline.studioAgent.studioTrackerModelOverride.isNotEmpty) {
      return resolver
          .resolveAgentConfig(
            current,
            runApiConfigId,
            pipeline.studioAgent.studioTrackerModelOverride,
          )
          .copyWithSampling(
            topP: pipeline.studioAgent.studioTrackerTopP,
            topK: pipeline.studioAgent.studioTrackerTopK,
            frequencyPenalty: pipeline.studioAgent.studioTrackerFrequencyPenalty,
            presencePenalty: pipeline.studioAgent.studioTrackerPresencePenalty,
            omitTemperature: pipeline.studioAgent.studioTrackerOmitTemperature,
            omitTopP: pipeline.studioAgent.studioTrackerOmitTopP,
          );
    }
    return resolver
        .resolveAgentConfig(current, runApiConfigId, '')
        .copyWithSampling(
          topP: pipeline.studioAgent.studioTrackerTopP,
          topK: pipeline.studioAgent.studioTrackerTopK,
          frequencyPenalty: pipeline.studioAgent.studioTrackerFrequencyPenalty,
          presencePenalty: pipeline.studioAgent.studioTrackerPresencePenalty,
          omitTemperature: pipeline.studioAgent.studioTrackerOmitTemperature,
          omitTopP: pipeline.studioAgent.studioTrackerOmitTopP,
        );
  }

  Future<String> _readRunApiConfigId(String sessionId) async {
    final config = await _ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    return config?.runApiConfigId ?? '';
  }
}
