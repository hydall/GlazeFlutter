import '../../models/chat_message.dart';
import '../../models/studio_config.dart';
import '../prompt_builder.dart' show PromptPayload;
import '../studio_stage_brief.dart';
import '../../../features/chat/state/studio_cycle_state_provider.dart';
import '../memory_studio_service.dart' show StudioPipelineResult;
import '../../models/agent_operation_record.dart';

/// Pure static helpers for Studio stream interception.
///
/// Extracted from `StreamGenerationService` — all methods are pure
/// (no `Ref`, no side effects) and can be called from any context.
class StudioStreamInterceptor {
  StudioStreamInterceptor._();

  /// Compute the set of visible message IDs that form the Studio final
  /// generator's source window. Takes the last [finalContextSize] non-hidden
  /// messages from [history].
  static Set<String> computeStudioFinalVisibleMessageIds(
    List<ChatMessage> history,
    int finalContextSize,
  ) {
    if (finalContextSize <= 0) return const <String>{};
    final nonHidden = history.where((m) => !m.isHidden).toList();
    final start = nonHidden.length > finalContextSize
        ? nonHidden.length - finalContextSize
        : 0;
    return nonHidden.skip(start).map((m) => m.id).toSet();
  }

  /// Compute the max context size across all pre-generation trackers except
  /// the last one (the final generator). Falls back to 5 when there are
  /// fewer than 2 pre-gen agents.
  static int maxStudioTrackerContextSize(StudioConfig config) {
    final preGen =
        config.agents
            .where((a) => a.enabled && a.phase == 'pre_generation')
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (preGen.length <= 1) return 5;
    preGen.removeLast();
    if (preGen.isEmpty) return 5;
    return preGen
        .map((a) => a.contextSize)
        .fold<int>(1, (max, size) => size > max ? size : max);
  }

  /// Clone a [PromptPayload] with a different `sourceWindowVisibleMessageIds`.
  static PromptPayload payloadWithSourceWindow(
    PromptPayload payload,
    Set<String> sourceWindowVisibleMessageIds,
  ) {
    return PromptPayload(
      character: payload.character,
      persona: payload.persona,
      preset: payload.preset,
      history: payload.history,
      sessionId: payload.sessionId,
      apiConfig: payload.apiConfig,
      sessionVars: payload.sessionVars,
      globalVars: payload.globalVars,
      summaryContent: payload.summaryContent,
      summaryPrefix: payload.summaryPrefix,
      memoryContent: payload.memoryContent,
      memoryMacroContent: payload.memoryMacroContent,
      memoryInjectionTarget: payload.memoryInjectionTarget,
      guidanceText: payload.guidanceText,
      lorebooks: payload.lorebooks,
      lorebookSettings: payload.lorebookSettings,
      lorebookActivations: payload.lorebookActivations,
      vectorEntries: payload.vectorEntries,
      authorsNote: payload.authorsNote,
      characterDepthPrompt: payload.characterDepthPrompt,
      characterDepthPromptDepth: payload.characterDepthPromptDepth,
      characterDepthPromptRole: payload.characterDepthPromptRole,
      memoryCoverage: payload.memoryCoverage,
      globalRegexes: payload.globalRegexes,
      preScannedEntries: payload.preScannedEntries,
      triggeredMemories: payload.triggeredMemories,
      runtimePromptBlocks: payload.runtimePromptBlocks,
      memorySelection: payload.memorySelection,
      memoryExcerptingEnabled: payload.memoryExcerptingEnabled,
      memoryPackingMode: payload.memoryPackingMode,
      memoryExcerptTokensPerChunk: payload.memoryExcerptTokensPerChunk,
      memoryExcerptChunksPerEntry: payload.memoryExcerptChunksPerEntry,
      chunkFirstTopEntries: payload.chunkFirstTopEntries,
      chunkFirstTopChunks: payload.chunkFirstTopChunks,
      arcContent: payload.arcContent,
      entitiesContent: payload.entitiesContent,
      studioSessionStateContent: payload.studioSessionStateContent,
      recalledMessagesContent: payload.recalledMessagesContent,
      recalledMessageChunks: payload.recalledMessageChunks,
      disableSourceWindowExclusion: payload.disableSourceWindowExclusion,
      sourceWindowVisibleMessageIds: sourceWindowVisibleMessageIds,
      memoryInjectionFingerprint: payload.memoryInjectionFingerprint,
    );
  }

  /// Convert Studio stage briefs into the compact JSON format stored on
  /// `ChatMessage.studioOutputs` / `AgentSwipe.studioOutputs` and read by the
  /// UI (Agentic Ops panel). Format: `{'id','name','content'}` per brief.
  static List<Map<String, dynamic>> studioOutputsToJson(
    List<StudioStageBrief> briefs,
  ) {
    return briefs
        .map((b) => {'id': b.agentId, 'name': b.agentName, 'content': b.brief})
        .toList(growable: false);
  }

  /// Builds the terminal `StudioCycleState` from a `StudioPipelineResult`,
  /// aggregating the per-agent briefs into completed/failed counts.
  static StudioCycleState studioFinalState(
    String sessionId,
    StudioPipelineResult result,
    StudioCyclePhase phase,
  ) {
    final briefs = result.stageBriefs;
    final ok = briefs.where((b) => b.status == 'ok').length;
    final failed = briefs.length - ok;
    final failedNames = briefs
        .where((b) => b.status != 'ok')
        .map((b) => b.agentName)
        .toList(growable: false);
    switch (phase) {
      case StudioCyclePhase.done:
        return StudioCycleState.done(
          sessionId: sessionId,
          totalAgents: briefs.length,
          completedAgents: ok,
          failedAgents: failed,
          failedAgentNames: failedNames,
        );
      case StudioCyclePhase.agentErrors:
        return StudioCycleState.agentErrors(
          sessionId: sessionId,
          totalAgents: briefs.length,
          completedAgents: ok,
          failedAgents: failed,
          failedAgentNames: failedNames,
        );
      default:
        return const StudioCycleState.idle();
    }
  }

  /// Maps a Studio pipeline status string to an [AgentOperationStatus].
  static AgentOperationStatus studioStatusToOp(String status) {
    return switch (status) {
      'ok' => AgentOperationStatus.ok,
      'disabled' => AgentOperationStatus.disabled,
      'aborted' => AgentOperationStatus.aborted,
      'timeout' => AgentOperationStatus.timeout,
      'error' => AgentOperationStatus.error,
      'agent_errors' => AgentOperationStatus.error,
      _ => AgentOperationStatus.error,
    };
  }
}
