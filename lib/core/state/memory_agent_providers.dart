import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat_history/chat_history_provider.dart';
import '../../features/settings/api_list_provider.dart';
import '../llm/aux_llm_client.dart';
import '../llm/memory_graph_builder.dart';
import '../llm/memory_provenance.dart';
import '../llm/memory_cadence_service.dart';
import '../llm/memory_post_turn_service.dart';
import '../llm/memory_agentic_service.dart';
import '../llm/memory_agentic_write_service.dart';
import '../llm/memory_dedup_service.dart';
import '../llm/memory_studio_service.dart';
import '../llm/post_cleaner_service.dart';
import '../llm/studio_ledger_service.dart';
import '../models/api_config.dart';
import 'db_provider.dart';

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
/// Currently a no-op (entity graph disabled) — only cadence counter runs.
final memoryPostTurnServiceProvider = Provider<MemoryPostTurnService>((ref) {
  return MemoryPostTurnService(ref.watch(memoryCadenceServiceProvider));
});

/// Agentic memory service (Phase 10). Read-only searchMemory tool.
final memoryAgenticServiceProvider = Provider<MemoryAgenticService>((ref) {
  return MemoryAgenticService(ref);
});

/// Agentic write-loop service (Stage 1). Trackers only.
final memoryAgenticWriteServiceProvider = Provider<MemoryAgenticWriteService>((
  ref,
) {
  return MemoryAgenticWriteService(
    llm: const AuxLlmClient(),
    trackerRepo: ref.read(trackerRepoProvider),
    snapshotRepo: ref.read(trackerSnapshotRepoProvider),
  );
});

/// Studio Mode pipeline service. Tracker-around-generator model.
final memoryStudioServiceProvider = Provider<MemoryStudioService>((ref) {
  return MemoryStudioService(ref);
});

/// POST-cleaner service (Stage 4). Rewrites the final assistant message
/// to remove clichés and repetition. Fire-and-forget after generation.
final postCleanerServiceProvider = Provider<PostCleanerService>((ref) {
  return PostCleanerService(
    llm: const AuxLlmClient(),
    chatRepo: ref.read(chatRepoProvider),
    snapshotRepo: ref.read(trackerSnapshotRepoProvider),
    invalidateChatHistory: () => ref.invalidate(chatHistoryProvider),
  );
});

/// Studio Ledger service (Stage 5). Runs after the POST-cleaner to extract
/// and persist continuity state (entity/relationship/arc/world/scene) and
/// durable MemoryBook facts from the final assistant response.
/// See docs/plans/STUDIO_LEDGER_MEMORY.md.
final studioLedgerServiceProvider = Provider<StudioLedgerService>((ref) {
  return StudioLedgerService(
    llm: const AuxLlmClient(),
    trackerRepo: ref.read(trackerRepoProvider),
    bookRepo: ref.read(memoryBookRepoProvider),
    snapshotRepo: ref.read(trackerSnapshotRepoProvider),
  );
});

/// Memory dedup service. Cosine pre-filter + batch LLM call to merge/drop/keep
/// near-duplicate memory entries. Runs on-demand (UI button) or automatically
/// after generation (delayed, fire-and-forget).
final memoryDedupServiceProvider = Provider<MemoryDedupService>((ref) {
  return MemoryDedupService(
    llm: const AuxLlmClient(),
    embeddingRepo: ref.read(embeddingRepoProvider),
    bookRepo: ref.read(memoryBookRepoProvider),
    loadApiConfigs: () async {
      await ref.read(apiListProvider.future);
      return ref.read(apiListProvider).value ?? const <ApiConfig>[];
    },
    activeApiConfig: () => ref.read(activeApiConfigProvider),
  );
});
