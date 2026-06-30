import 'dart:async';

import '../db/repositories/memory_book_repo.dart';
import '../db/repositories/memory_salience_repo.dart';
import '../state/memory_settings_provider.dart';
import 'memory_cadence_service.dart';
import 'memory_graph_builder.dart';
import 'memory_salience_scorer.dart';

/// Post-turn memory pipeline (Phase G4).
///
/// Runs after the assistant response is saved. Fire-and-forget — does NOT
/// block generation. Performs:
/// 1. Increment assistant message counter.
/// 2. If cadence allows: rebuild entity graph for new/changed entries.
/// 3. Rescore salience for entries without salience.
/// 4. Mark cadence run.
///
/// Errors are logged, not shown to user.
class MemoryPostTurnService {
  final MemoryBookRepo _bookRepo;
  final MemorySalienceRepo _salienceRepo;
  final MemoryCadenceService _cadenceService;
  final MemoryGraphBuilder _graphBuilder;
  final MemoryGlobalSettings Function() _readGlobalSettings;

  MemoryPostTurnService(
    this._bookRepo,
    this._salienceRepo,
    this._cadenceService,
    this._graphBuilder,
    this._readGlobalSettings,
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

      await _cadenceService.markRun(sessionId, 'graph');
    } catch (_) {
      // Post-turn failures are non-fatal; do not surface to user
    }
  }
}
