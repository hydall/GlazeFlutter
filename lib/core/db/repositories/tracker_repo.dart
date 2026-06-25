import 'package:drift/drift.dart';

import '../../models/tracker.dart';
import '../../utils/time_helpers.dart';
import '../app_db.dart';

class TrackerRepo {
  final AppDatabase db;

  const TrackerRepo(this.db);

  Future<List<Tracker>> getBySessionId(String sessionId) {
    return (db.select(db.trackerRows)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get()
        .then((rows) => rows.map(_rowToModel).toList());
  }

  Future<List<Tracker>> getBySessionAndScope(
    String sessionId,
    String scope,
  ) {
    return (db.select(db.trackerRows)
          ..where((t) => t.sessionId.equals(sessionId))
          ..where((t) => t.scope.equals(scope))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get()
        .then((rows) => rows.map(_rowToModel).toList());
  }

  Future<Tracker?> get(String sessionId, String name) async {
    final row = await (db.select(db.trackerRows)
          ..where((t) => t.sessionId.equals(sessionId))
          ..where((t) => t.name.equals(name)))
        .getSingleOrNull();
    return row == null ? null : _rowToModel(row);
  }

  /// Atomic upsert by natural key (sessionId, name). If a tracker with the
  /// same name already exists for the session, its value/scope/provenance/
  /// updatedAt are overwritten. Safe under concurrent writes — Drift resolves
  /// the PK conflict in a single statement.
  Future<void> upsert(Tracker tracker) {
    return db.into(db.trackerRows).insertOnConflictUpdate(
      TrackerRowsCompanion.insert(
        sessionId: tracker.sessionId,
        name: tracker.name,
        value: Value(tracker.value),
        scope: Value(tracker.scope),
        provenance: Value(tracker.provenance),
        updatedAt: Value(tracker.updatedAt == 0
            ? currentTimestampSeconds()
            : tracker.updatedAt),
      ),
    );
  }

  /// Convenience: upsert with explicit fields (avoids constructing a Tracker
  /// at call sites that only have the new value).
  Future<void> upsertValue(
    String sessionId,
    String name,
    String value, {
    String scope = 'chat',
    String provenance = '',
  }) {
    return db.into(db.trackerRows).insertOnConflictUpdate(
      TrackerRowsCompanion.insert(
        sessionId: sessionId,
        name: name,
        value: Value(value),
        scope: Value(scope),
        provenance: Value(provenance),
        updatedAt: Value(currentTimestampSeconds()),
      ),
    );
  }

  Future<void> delete(String sessionId, String name) {
    return (db.delete(db.trackerRows)
          ..where((t) => t.sessionId.equals(sessionId))
          ..where((t) => t.name.equals(name)))
        .go();
  }

  Future<void> clearForSession(String sessionId) {
    return (db.delete(db.trackerRows)
          ..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }

  /// Atomically replaces all trackers for [sessionId] with [trackers].
  /// Wraps delete + insert in a single transaction so a concurrent read never
  /// observes a half-replaced state.
  Future<void> replaceForSession(
    String sessionId,
    List<Tracker> trackers,
  ) {
    return db.transaction(() async {
      await clearForSession(sessionId);
      for (final t in trackers) {
        await upsert(t);
      }
    });
  }

  Stream<List<Tracker>> watchBySessionId(String sessionId) {
    return (db.select(db.trackerRows)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch()
        .map((rows) => rows.map(_rowToModel).toList());
  }

  Tracker _rowToModel(TrackerRow row) {
    return Tracker(
      sessionId: row.sessionId,
      name: row.name,
      value: row.value,
      scope: row.scope,
      provenance: row.provenance,
      updatedAt: row.updatedAt,
    );
  }
}
