import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db_provider.dart';
import '../llm/memory_graph_builder.dart';
import '../llm/memory_provenance.dart';
import '../llm/memory_cadence_service.dart';
import '../llm/memory_post_turn_service.dart';
import '../llm/memory_agentic_service.dart';
import '../llm/memory_agentic_write_service.dart';
import '../llm/memory_studio_service.dart';
import '../llm/post_cleaner_service.dart';
import '../llm/studio_ledger_service.dart';
import 'memory_settings_provider.dart';

/// Provider for the entity graph builder.
final memoryGraphBuilderProvider = Provider<MemoryGraphBuilder>((ref) {
  return MemoryGraphBuilder(
    ref.watch(memoryEntityRepoProvider),
    ref.watch(memorySalienceRepoProvider),
  );
});

/// Provenance index for derived state artifacts (tracker, proposed memory,
/// scene, and legacy catalog artifacts).
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
    () => ref.read(memoryGlobalSettingsProvider),
  );
});

/// Agentic memory service (Phase 10). Read-only searchMemory tool.
final memoryAgenticServiceProvider = Provider<MemoryAgenticService>((ref) {
  return MemoryAgenticService(ref);
});

/// Agentic write-loop service (Stage 1). Trackers + memory drafts.
final memoryAgenticWriteServiceProvider = Provider<MemoryAgenticWriteService>((
  ref,
) {
  return MemoryAgenticWriteService(ref);
});

/// Studio Mode pipeline service. Tracker-around-generator model.
final memoryStudioServiceProvider = Provider<MemoryStudioService>((ref) {
  return MemoryStudioService(ref);
});

/// POST-cleaner service (Stage 4). Rewrites the final assistant message
/// to remove clichés and repetition. Fire-and-forget after generation.
final postCleanerServiceProvider = Provider<PostCleanerService>((ref) {
  return PostCleanerService(ref);
});

/// Studio Ledger service (Stage 5). Runs after the POST-cleaner to extract
/// and persist continuity state (entity/relationship/arc/world/scene) and
/// durable MemoryBook facts from the final assistant response.
/// See docs/plans/PLAN_STUDIO_LEDGER_MEMORY.md.
final studioLedgerServiceProvider = Provider<StudioLedgerService>((ref) {
  return StudioLedgerService(ref);
});
