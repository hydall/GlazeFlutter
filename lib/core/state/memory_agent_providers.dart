import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db_provider.dart';
import '../llm/memory_classifier_http_client.dart';
import '../llm/memory_needs_classifier_service.dart';
import '../llm/memory_sidecar_http_client.dart';
import '../llm/memory_sidecar_prewarm_cache.dart';
import '../llm/memory_sidecar_reranker_service.dart';
import '../llm/memory_graph_builder.dart';
import '../llm/memory_provenance.dart';
import '../llm/memory_cadence_service.dart';
import '../llm/memory_post_turn_service.dart';
import '../llm/memory_consolidation_service.dart';
import '../llm/memory_agentic_service.dart';
import '../llm/memory_agentic_write_service.dart';
import '../llm/memory_studio_service.dart';
import '../llm/studio_decomposition_service.dart';
import '../llm/studio_cleaner_rules_extractor.dart';
import '../llm/studio_build_llm_client.dart';
import '../llm/post_cleaner_service.dart';
import 'memory_settings_provider.dart';
import '../llm/sidecar_llm_client.dart';

/// Provider for the memory needs classifier service.
/// Returns a no-op service when classifier is not configured.
final memoryClassifierServiceProvider =
    Provider<MemoryNeedsClassifierService>((ref) {
  return MemoryNeedsClassifierService(buildClassifierClient(ref));
});

/// Provider for the sidecar reranker service.
final memorySidecarRerankerServiceProvider =
    Provider<MemorySidecarRerankerService>((ref) {
  return MemorySidecarRerankerService(
    buildSidecarClient(ref),
    callWithLog: (request, cancelToken) =>
        callSidecarWithLog(ref: ref, request: request, cancelToken: cancelToken),
  );
});

/// Singleton in-memory prewarm cache for sidecar results.
/// Keyed per-session with full provenance key matching.
final memorySidecarPrewarmCacheProvider =
    Provider<MemorySidecarPrewarmCache>((ref) {
  final cache = MemorySidecarPrewarmCache();
  ref.onDispose(cache.clear);
  return cache;
});

/// Provider for the entity graph builder.
final memoryGraphBuilderProvider = Provider<MemoryGraphBuilder>((ref) {
  return MemoryGraphBuilder(
    ref.watch(memoryEntityRepoProvider),
    ref.watch(memorySalienceRepoProvider),
  );
});

/// Provenance index for derived state artifacts (catalog, sidecar, tracker).
final memoryProvenanceIndexProvider =
    Provider<MemoryProvenanceIndex<MemoryDerivedArtifact<dynamic>>>((ref) {
  final index = MemoryProvenanceIndex<MemoryDerivedArtifact<dynamic>>();
  ref.onDispose(index.clear);
  return index;
});

/// Cadence service for gating post-turn work.
final memoryCadenceServiceProvider = Provider<MemoryCadenceService>((ref) {
  return MemoryCadenceService(ref.watch(memoryCadenceRepoProvider));
});

/// Post-turn pipeline service. Fire-and-forget after assistant response.
final memoryPostTurnServiceProvider = Provider<MemoryPostTurnService>((ref) {
  return MemoryPostTurnService(
    ref.watch(memoryBookRepoProvider),
    ref.watch(memorySalienceRepoProvider),
    ref.watch(memoryCadenceServiceProvider),
    ref.watch(memoryGraphBuilderProvider),
    ref.watch(memoryConsolidationServiceProvider),
    () => ref.read(memoryGlobalSettingsProvider),
    () => ref.read(pipelineSettingsProvider),
  );
});

/// Consolidation service (Phase G5). Opt-in LLM feature.
final memoryConsolidationServiceProvider =
    Provider<MemoryConsolidationService>((ref) {
  return MemoryConsolidationService(
    ref.watch(memoryConsolidationRepoProvider),
    SidecarLlmClient(ref),
  );
});

/// Agentic memory service (Phase 10). Read-only searchMemory tool.
final memoryAgenticServiceProvider = Provider<MemoryAgenticService>((ref) {
  return MemoryAgenticService(ref);
});

/// Agentic write-loop service (Stage 1). Trackers + memory drafts.
final memoryAgenticWriteServiceProvider =
    Provider<MemoryAgenticWriteService>((ref) {
  return MemoryAgenticWriteService(ref);
});

/// Studio Mode pipeline service. Tracker-around-generator model.
final memoryStudioServiceProvider = Provider<MemoryStudioService>((ref) {
  return MemoryStudioService(ref);
});

/// Build-time preset decomposition service. Turns a user preset into a list of
/// [StudioAgent]s (trackers + one final generator) that slot into
/// [MemoryStudioService.runTrackerCycle]. Last enabled agent (highest order) is
/// the generator; all earlier agents are pre-generation trackers.
final studioDecompositionServiceProvider =
    Provider<StudioDecompositionService>((ref) {
  return StudioDecompositionService(ref);
});

/// Build-time extractor for POST-cleaner style rules. Second LLM call in
/// `StudioMenuController.buildStudio`: reads the preset and fills the three
/// `postCleaner*` string fields of `PipelineSettings`.
final studioCleanerRulesExtractorProvider =
    Provider<StudioCleanerRulesExtractor>((ref) {
  return StudioCleanerRulesExtractor(StudioBuildLlmClient(ref));
});

/// POST-cleaner service (Stage 4). Rewrites the final assistant message
/// to remove clichés and repetition. Fire-and-forget after generation.
final postCleanerServiceProvider = Provider<PostCleanerService>((ref) {
  return PostCleanerService(ref);
});
