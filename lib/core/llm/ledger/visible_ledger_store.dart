import 'package:flutter/foundation.dart';

import '../../db/repositories/tracker_repo.dart';
import 'ledger_provenance.dart';

/// Stores the visible ledger as an internal diagnostic tracker row.
///
/// Key: `_ledger:$messageId` — scoped to a specific message. Long ledgers
/// are truncated to 8000 chars.
class VisibleLedgerStore {
  const VisibleLedgerStore();

  /// Store [visibleLedger] as a diagnostic tracker row for [sessionId].
  Future<void> storeVisibleLedger({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    required String visibleLedger,
    required TrackerRepo trackerRepo,
  }) async {
    if (visibleLedger.isEmpty) return;
    try {
      await trackerRepo.upsertValue(
        sessionId,
        '_ledger:$messageId',
        visibleLedger.length > 8000
            ? '${visibleLedger.substring(0, 8000)}…[truncated]'
            : visibleLedger,
        scope: 'ledger_diagnostic',
        provenance: buildLedgerProvenance(
          messageId: messageId,
          swipeId: swipeId,
          agentSwipeId: agentSwipeId,
        ),
      );
    } catch (e) {
      debugPrint('[StudioLedger] failed to store visible ledger: $e');
    }
  }
}
