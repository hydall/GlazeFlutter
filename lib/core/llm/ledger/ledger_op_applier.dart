import 'package:flutter/foundation.dart';

import '../../db/repositories/tracker_repo.dart';
import '../../models/studio_ledger_export.dart';
import 'ledger_provenance.dart';

/// Applies a single [LedgerOp] to the [TrackerRepo].
///
/// Handles `set`, `append_unique`, and `delete` ops. Respects `canon_lock`
/// keys — when `canon_lock:<key>` is set to `'true'`, the op is blocked.
class LedgerOpApplier {
  const LedgerOpApplier();

  /// Apply [op] to [trackerRepo] for [sessionId].
  ///
  /// [messageId], [swipeId], [agentSwipeId] form the provenance anchor.
  Future<void> applyOp({
    required LedgerOp op,
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    required TrackerRepo trackerRepo,
  }) async {
    // Plan §Manual Overrides and Locks: if canon_lock:<key> = 'true',
    // Studio Ledger must not update that state key.
    final lockKey = 'canon_lock:${op.key}';
    final lock = await trackerRepo.get(sessionId, lockKey);
    if (lock != null && lock.value.trim().toLowerCase() == 'true') {
      debugPrint('[StudioLedger] op blocked by canon_lock key=${op.key}');
      return;
    }

    final provenance = buildLedgerProvenance(
      messageId: messageId,
      swipeId: swipeId,
      agentSwipeId: agentSwipeId,
      evidence: op.evidence,
    );

    switch (op.op) {
      case 'set':
        await trackerRepo.upsertValue(
          sessionId,
          op.key,
          op.value,
          scope: 'ledger',
          provenance: provenance,
        );
      case 'append_unique':
        // Read current value and append if not already present.
        final existing = await trackerRepo.get(sessionId, op.key);
        final currentValue = existing?.value ?? '';
        if (containsValue(currentValue, op.value)) {
          debugPrint(
            '[StudioLedger] append_unique skipped (already present) '
            'key=${op.key}',
          );
          return;
        }
        final newValue = currentValue.isEmpty
            ? op.value
            : '$currentValue\n${op.value}';
        await trackerRepo.upsertValue(
          sessionId,
          op.key,
          newValue,
          scope: 'ledger',
          provenance: provenance,
        );
      case 'delete':
        await trackerRepo.delete(sessionId, op.key);
    }
  }

  /// Returns true when [haystack] already contains [needle] as a line
  /// (case-insensitive, trimmed). Used for append_unique semantics.
  bool containsValue(String haystack, String needle) {
    if (haystack.isEmpty || needle.isEmpty) return false;
    final needleLower = needle.trim().toLowerCase();
    return haystack
        .split('\n')
        .any((line) => line.trim().toLowerCase() == needleLower);
  }
}
