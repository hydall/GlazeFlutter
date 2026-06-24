import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db_provider.dart';
import '../db/repositories/memory_entity_repo.dart';
import '../db/repositories/memory_salience_repo.dart';
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
import '../llm/memory_studio_service.dart';
import 'memory_settings_provider.dart';

/// Provider for the memory needs classifier service.
/// Returns a no-op service when classifier is not configured.
final memoryClassifierServiceProvider =
    Provider<MemoryNeedsClassifierService>((ref) {
  return MemoryNeedsClassifierService(buildClassifierClient(ref));
});

/// Provider for the sidecar reranker service.
final memorySidecarRerankerServiceProvider =
    Provider<MemorySidecarRerankerService>((ref) {
  return MemorySidecarRerankerService(buildSidecarClient(ref));
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
    Provider<MemoryProvenanceIndex<MemoryDerivedArtifact>>((ref) {
  final index = MemoryProvenanceIndex<MemoryDerivedArtifact>();
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
    ref.watch(memoryConsolidationRepoProvider),
    ref.watch(memoryCadenceServiceProvider),
    ref.watch(memoryGraphBuilderProvider),
    () => ref.read(memoryGlobalSettingsProvider),
  );
});

/// Consolidation service (Phase G5). Opt-in LLM feature.
final memoryConsolidationServiceProvider =
    Provider<MemoryConsolidationService>((ref) {
  return MemoryConsolidationService(ref.watch(memoryConsolidationRepoProvider));
});

/// Agentic memory service (Phase 10). Read-only searchMemory tool.
final memoryAgenticServiceProvider = Provider<MemoryAgenticService>((ref) {
  return MemoryAgenticService(ref);
});

/// Studio Mode pipeline service (Phase 11). Multi-stage RP pipeline.
final memoryStudioServiceProvider = Provider<MemoryStudioService>((ref) {
  return MemoryStudioService(ref);
});
