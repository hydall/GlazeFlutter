import 'dart:async';

import '../db/repositories/memory_book_repo.dart';
import '../db/repositories/memory_salience_repo.dart';
import '../models/pipeline_settings.dart';
import '../state/memory_settings_provider.dart';
import 'memory_cadence_service.dart';
import 'memory_consolidation_service.dart';
import 'memory_graph_builder.dart';
import 'memory_salience_scorer.dart';

/// Post-turn memory pipeline (Phase G4).
///
/// Runs after the assistant response is saved. Fire-and-forget — does NOT
/// block generation. Performs:
/// 1. Increment assistant message counter.
/// 2. If cadence allows: rebuild entity graph for new/changed entries.
/// 3. Rescore salience for entries without salience.
/// 4. If consolidation is enabled and threshold met: trigger consolidation.
/// 5. Mark cadence run.
///
/// Errors are logged, not shown to user (except consolidation — decision G).
class MemoryPostTurnService {
  final MemoryBookRepo _bookRepo;
  final MemorySalienceRepo _salienceRepo;
  final MemoryCadenceService _cadenceService;
  final MemoryGraphBuilder _graphBuilder;
  final MemoryConsolidationService _consolidationService;
  final MemoryGlobalSettings Function() _readGlobalSettings;
  final PipelineSettings Function() _readPipelineSettings;

  MemoryPostTurnService(
    this._bookRepo,
    this._salienceRepo,
    this._cadenceService,
    this._graphBuilder,
    this._consolidationService,
    this._readGlobalSettings,
    this._readPipelineSettings,
  );

  /// Run post-turn memory work. Fire-and-forget; caller should not await.
  Future<void> runPostTurn(String sessionId) async {
    try {
      await _cadenceService.incrementAssistant(sessionId);

      final gs = _readGlobalSettings();
      if (gs.memoryMode == 'fast') return;

      final book = await _bookRepo.getBySessionId(sessionId);
      if (book == null || !book.settings.enabled) return;

      final shouldRunGraph = await _cadenceService.shouldRun(
        sessionId,
        'graph',
        memoryMode: book.settings.memoryMode,
        cadenceInterval: book.settings.cadenceInterval,
      );
      if (!shouldRunGraph) return;

      // Update entity graph + salience for entries
      final knownCharacterNames = <String>[];
      final activeEntries = book.entries
          .where((e) => e.status == 'active' && e.content.trim().isNotEmpty)
          .toList();

      for (final entry in activeEntries) {
        try {
          await _graphBuilder.updateForEntry(
            entry,
            sessionId: sessionId,
            knownCharacterNames: knownCharacterNames,
          );
        } catch (_) {
          // Graph update failure is non-fatal
        }
      }

      // Rescore salience for entries without it
      final existingSalience = await _salienceRepo.getBySessionId(sessionId);
      final scoredIds = existingSalience.map((s) => s.memoryEntryId).toSet();
      for (final entry in activeEntries) {
        if (!scoredIds.contains(entry.id)) {
          try {
            final salience = MemorySalienceScorer.score(
              entry,
              sessionId: sessionId,
            );
            await _salienceRepo.upsert(salience);
          } catch (_) {
            // Non-fatal
          }
        }
      }

      // Step 4: consolidation (Phase G5). Gated by cadence + settings.
      // NOTE: must evaluate shouldConsolidate BEFORE markRun('graph'),
      // because graph and consolidation share the same cadence counter —
      // markRun('graph') resets assistantMessagesSinceLastRun to 0.
      final settings = _readPipelineSettings();
      var didConsolidate = false;
      if (settings.consolidationEnabled) {
        final shouldConsolidate = await _cadenceService.shouldRun(
          sessionId,
          'consolidation',
          memoryMode: book.settings.memoryMode,
          cadenceInterval: book.settings.cadenceInterval,
        );
        didConsolidate = shouldConsolidate;
      }

      await _cadenceService.markRun(sessionId, 'graph');

      if (didConsolidate) {
        try {
          await _consolidationService.consolidateSession(
            sessionId,
            book.entries,
            settings: settings,
          );
          await _cadenceService.markRun(sessionId, 'consolidation');
        } catch (_) {
          // Decision G: consolidation errors surface to user via repo status
          // (the service saves an error row on failure), not via exception
          // propagation. Do not rethrow — post-turn is fire-and-forget.
        }
      }
    } catch (_) {
      // Post-turn failures are non-fatal; do not surface to user
    }
  }
}
