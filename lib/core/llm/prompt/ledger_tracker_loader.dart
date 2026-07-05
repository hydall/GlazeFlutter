import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/db_provider.dart';
import '../../models/tracker.dart';

/// Loads effective Studio Ledger tracker rows for a session.
///
/// Merges the latest committed snapshot with live manual overrides/locks from
/// `tracker_rows`. Snapshot rows are authoritative for model-written state;
/// live `canon_override:*` and `canon_lock:*` rows are user-owned and can be
/// newer than the snapshot, so they always win.
///
/// See docs/rules/database.md (INV-TS3: snapshot-first read path).
class LedgerTrackerLoader {
  final Ref _ref;

  LedgerTrackerLoader(this._ref);

  Future<List<Tracker>> loadEffectiveLedgerTrackers(String sessionId) async {
    final trackerRepo = _ref.read(trackerRepoProvider);
    final snapshot = await _ref
        .read(trackerSnapshotRepoProvider)
        .getLatestCommitted(sessionId);
    final liveLedger = await trackerRepo.getBySessionAndScope(
      sessionId,
      'ledger',
    );

    if (snapshot == null) return liveLedger;

    final byName = <String, Tracker>{
      for (final tracker in snapshot.trackers)
        if (tracker.scope == 'ledger') tracker.name: tracker,
    };

    // Manual overrides/locks are user-owned and can be newer than the latest
    // committed model snapshot. Keep them authoritative without admitting
    // uncommitted model-written rows from tracker_rows.
    for (final tracker in liveLedger) {
      if (tracker.name.startsWith('canon_override:') ||
          tracker.name.startsWith('canon_lock:')) {
        byName[tracker.name] = tracker;
      }
    }

    return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
