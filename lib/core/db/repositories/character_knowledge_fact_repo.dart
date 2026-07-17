import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/character_knowledge_fact.dart';
import '../../utils/time_helpers.dart';
import '../app_db.dart';

/// Transactional lifecycle store for swipe-safe atomic character facts.
class CharacterKnowledgeFactRepo {
  const CharacterKnowledgeFactRepo(this.db);

  final AppDatabase db;

  Future<void> insertTentative(CharacterKnowledgeFact fact) =>
      insertAllTentative([fact]);

  /// Replaying a Ledger export replaces only the facts at its exact anchor.
  /// This makes retry safe without imposing a false global uniqueness rule.
  Future<void> replaceTentativeAnchor({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    required List<CharacterKnowledgeFact> facts,
  }) async {
    if (facts.any(
      (fact) =>
          fact.chatSessionId != sessionId ||
          fact.sourceMessageId != messageId ||
          fact.sourceSwipeId != swipeId ||
          fact.sourceAgentSwipeId != agentSwipeId,
    )) {
      throw ArgumentError('A tentative batch must share one source anchor.');
    }

    await db.transaction(() async {
      await _deleteAnchor(
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
        agentSwipeId: agentSwipeId,
      );
      for (final fact in facts) {
        await db
            .into(db.characterKnowledgeFactRows)
            .insert(
              _toRow(
                fact.copyWith(
                  lifecycle: CharacterKnowledgeFactLifecycle.tentative,
                ),
              ),
            );
      }
    });
  }

  Future<void> insertAllTentative(List<CharacterKnowledgeFact> facts) async {
    if (facts.isEmpty) return;
    final anchor = facts.first;
    await replaceTentativeAnchor(
      sessionId: anchor.chatSessionId,
      messageId: anchor.sourceMessageId,
      swipeId: anchor.sourceSwipeId,
      agentSwipeId: anchor.sourceAgentSwipeId,
      facts: facts,
    );
  }

  Future<void> activateAnchor({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
  }) async {
    await db.transaction(() async {
      final incoming = await getBySourceAnchor(
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
        agentSwipeId: agentSwipeId,
      );
      for (final fact in incoming) {
        final activeRows = await _activeQuery(sessionId).get();
        final previous = activeRows
            .map(_fromRow)
            .where(
              (candidate) =>
                  candidate.id != fact.id &&
                  semanticSlotKey(candidate) == semanticSlotKey(fact),
            )
            .toList();
        for (final old in previous) {
          await (db.update(
            db.characterKnowledgeFactRows,
          )..where((row) => row.id.equals(old.id))).write(
            CharacterKnowledgeFactRowsCompanion(
              lifecycle: const Value('superseded'),
              updatedAt: Value(currentTimestampSeconds()),
            ),
          );
        }
        await (db.update(
          db.characterKnowledgeFactRows,
        )..where((row) => row.id.equals(fact.id))).write(
          CharacterKnowledgeFactRowsCompanion(
            supersedesId: Value(
              previous.isEmpty ? fact.supersedesId : previous.first.id,
            ),
            lifecycle: const Value('active'),
            updatedAt: Value(currentTimestampSeconds()),
          ),
        );
      }
    });
  }

  Future<void> retractAnchor({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
  }) async {
    await db.transaction(() async {
      final facts = await getBySourceAnchor(
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
        agentSwipeId: agentSwipeId,
      );
      await _setAnchorLifecycle(
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
        agentSwipeId: agentSwipeId,
        lifecycle: CharacterKnowledgeFactLifecycle.retracted,
      );
      await _reactivatePredecessors(facts);
    });
  }

  /// Retracts every fact generated for a deleted message, including all of its
  /// green/blue swipes. Rows remain as provenance tombstones.
  Future<void> retractForMessage(String sessionId, String messageId) async {
    await retractForMessages(sessionId, {messageId});
  }

  /// Retracts facts generated for any of the deleted messages in one pass.
  Future<void> retractForMessages(
    String sessionId,
    Set<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return;
    await db.transaction(() async {
      final rows =
          await (db.select(db.characterKnowledgeFactRows)
                ..where((row) => row.chatSessionId.equals(sessionId))
                ..where((row) => row.sourceMessageId.isIn(messageIds)))
              .get();
      await (db.update(db.characterKnowledgeFactRows)
            ..where((row) => row.chatSessionId.equals(sessionId))
            ..where((row) => row.sourceMessageId.isIn(messageIds)))
          .write(
            CharacterKnowledgeFactRowsCompanion(
              lifecycle: const Value('retracted'),
              updatedAt: Value(currentTimestampSeconds()),
            ),
          );
      await _reactivatePredecessors(
        rows.map(_fromRow),
        excludedMessageIds: messageIds,
      );
    });
  }

  Future<void> supersede(
    String oldId,
    CharacterKnowledgeFact replacement,
  ) async {
    await db.transaction(() async {
      final old = await getById(oldId);
      if (old == null) {
        throw StateError('Cannot supersede missing fact: $oldId');
      }
      await (db.update(
        db.characterKnowledgeFactRows,
      )..where((row) => row.id.equals(oldId))).write(
        CharacterKnowledgeFactRowsCompanion(
          lifecycle: const Value('superseded'),
          updatedAt: Value(currentTimestampSeconds()),
        ),
      );
      await db
          .into(db.characterKnowledgeFactRows)
          .insert(
            _toRow(
              replacement.copyWith(
                supersedesId: oldId,
                lifecycle: CharacterKnowledgeFactLifecycle.active,
              ),
            ),
          );
    });
  }

  Future<CharacterKnowledgeFact?> getById(String id) async {
    final row = await (db.select(
      db.characterKnowledgeFactRows,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<List<CharacterKnowledgeFact>> getActiveForSession(String sessionId) {
    return _activeQuery(
      sessionId,
    ).get().then((rows) => rows.map(_fromRow).toList(growable: false));
  }

  Future<List<CharacterKnowledgeFact>> getActiveForKnowers(
    String sessionId,
    Iterable<String> knowers,
  ) async {
    final values = knowers.where((value) => value.isNotEmpty).toSet();
    if (values.isEmpty) return const [];
    final rows = await (_activeQuery(
      sessionId,
    )..where((row) => row.knowerKey.isIn(values))).get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<CharacterKnowledgeFact>> getBySourceAnchor({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
  }) async {
    final rows = await (_anchorQuery(
      sessionId: sessionId,
      messageId: messageId,
      swipeId: swipeId,
      agentSwipeId: agentSwipeId,
    )..orderBy([(row) => OrderingTerm.asc(row.createdAt)])).get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> copyForSessionBranch({
    required String fromSessionId,
    required String toSessionId,
    required Set<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final rows =
        await (db.select(db.characterKnowledgeFactRows)
              ..where((row) => row.chatSessionId.equals(fromSessionId))
              ..where((row) => row.sourceMessageId.isIn(messageIds)))
            .get();
    final copiedIds = rows.map((row) => row.id).toSet();
    final copiedSupersededIds = rows
        .map((row) => row.supersedesId)
        .whereType<String>()
        .toSet();
    await db.transaction(() async {
      for (final row in rows) {
        final fact = _fromRow(row);
        final copiedId = '${fact.id}@$toSessionId';
        final copiedSupersedes =
            fact.supersedesId != null && copiedIds.contains(fact.supersedesId)
            ? '${fact.supersedesId}@$toSessionId'
            : null;
        final copiedLifecycle =
            fact.lifecycle == CharacterKnowledgeFactLifecycle.superseded &&
                !copiedSupersededIds.contains(fact.id)
            ? CharacterKnowledgeFactLifecycle.active
            : fact.lifecycle;
        await db
            .into(db.characterKnowledgeFactRows)
            .insertOnConflictUpdate(
              _toRow(
                fact.copyWith(
                  id: copiedId,
                  chatSessionId: toSessionId,
                  supersedesId: copiedSupersedes,
                  clearSupersedesId: copiedSupersedes == null,
                  lifecycle: copiedLifecycle,
                ),
              ),
            );
      }
    });
  }

  Future<void> deleteBySessionId(String sessionId) {
    return (db.delete(
      db.characterKnowledgeFactRows,
    )..where((row) => row.chatSessionId.equals(sessionId))).go();
  }

  SimpleSelectStatement<
    $CharacterKnowledgeFactRowsTable,
    CharacterKnowledgeFactRow
  >
  _activeQuery(String sessionId) {
    return db.select(db.characterKnowledgeFactRows)
      ..where((row) => row.chatSessionId.equals(sessionId))
      ..where((row) => row.lifecycle.equals('active'))
      ..orderBy([
        (row) => OrderingTerm.desc(row.importance),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
  }

  SimpleSelectStatement<
    $CharacterKnowledgeFactRowsTable,
    CharacterKnowledgeFactRow
  >
  _anchorQuery({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
  }) {
    return db.select(db.characterKnowledgeFactRows)
      ..where((row) => row.chatSessionId.equals(sessionId))
      ..where((row) => row.sourceMessageId.equals(messageId))
      ..where((row) => row.sourceSwipeId.equals(swipeId))
      ..where((row) => row.sourceAgentSwipeId.equals(agentSwipeId));
  }

  Future<void> _setAnchorLifecycle({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    required CharacterKnowledgeFactLifecycle lifecycle,
  }) {
    return (db.update(db.characterKnowledgeFactRows)
          ..where((row) => row.chatSessionId.equals(sessionId))
          ..where((row) => row.sourceMessageId.equals(messageId))
          ..where((row) => row.sourceSwipeId.equals(swipeId))
          ..where((row) => row.sourceAgentSwipeId.equals(agentSwipeId)))
        .write(
          CharacterKnowledgeFactRowsCompanion(
            lifecycle: Value(lifecycle.wireName),
            updatedAt: Value(currentTimestampSeconds()),
          ),
        );
  }

  Future<void> _deleteAnchor({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
  }) {
    return (db.delete(db.characterKnowledgeFactRows)
          ..where((row) => row.chatSessionId.equals(sessionId))
          ..where((row) => row.sourceMessageId.equals(messageId))
          ..where((row) => row.sourceSwipeId.equals(swipeId))
          ..where((row) => row.sourceAgentSwipeId.equals(agentSwipeId)))
        .go();
  }

  Future<void> _reactivatePredecessors(
    Iterable<CharacterKnowledgeFact> retracted, {
    Set<String> excludedMessageIds = const {},
  }) async {
    for (final fact in retracted) {
      final predecessorId = fact.supersedesId;
      if (predecessorId == null) continue;
      final predecessor = await getById(predecessorId);
      if (predecessor == null ||
          excludedMessageIds.contains(predecessor.sourceMessageId) ||
          predecessor.lifecycle != CharacterKnowledgeFactLifecycle.superseded) {
        continue;
      }
      final activeRows = await _activeQuery(fact.chatSessionId).get();
      final hasActiveSuccessor = activeRows
          .map(_fromRow)
          .any(
            (candidate) =>
                semanticSlotKey(candidate) == semanticSlotKey(predecessor),
          );
      if (hasActiveSuccessor) continue;
      await (db.update(
        db.characterKnowledgeFactRows,
      )..where((row) => row.id.equals(predecessorId))).write(
        CharacterKnowledgeFactRowsCompanion(
          lifecycle: const Value('active'),
          updatedAt: Value(currentTimestampSeconds()),
        ),
      );
    }
  }

  CharacterKnowledgeFactRow _toRow(CharacterKnowledgeFact fact) {
    final now = currentTimestampSeconds();
    return CharacterKnowledgeFactRow(
      id: fact.id,
      chatSessionId: fact.chatSessionId,
      knowerKey: fact.knowerKey,
      knowerName: fact.knowerName,
      subjectKey: fact.subjectKey,
      subjectName: fact.subjectName,
      factClass: fact.factClass.wireName,
      scopeKey: fact.scopeKey,
      predicate: fact.predicate,
      object: fact.object,
      epistemicState: fact.epistemicState.wireName,
      confidence: fact.confidence.clamp(0, 1),
      importance: fact.importance.clamp(0, 1),
      entitiesJson: jsonEncode(fact.entities),
      topicsJson: jsonEncode(fact.topics),
      sourceMessageId: fact.sourceMessageId,
      sourceSwipeId: fact.sourceSwipeId,
      sourceAgentSwipeId: fact.sourceAgentSwipeId,
      sourceKind: fact.sourceKind,
      supersedesId: fact.supersedesId,
      lifecycle: fact.lifecycle.wireName,
      createdAt: fact.createdAt == 0 ? now : fact.createdAt,
      updatedAt: fact.updatedAt == 0 ? now : fact.updatedAt,
    );
  }

  CharacterKnowledgeFact _fromRow(CharacterKnowledgeFactRow row) =>
      CharacterKnowledgeFact(
        id: row.id,
        chatSessionId: row.chatSessionId,
        knowerKey: row.knowerKey,
        knowerName: row.knowerName,
        subjectKey: row.subjectKey,
        subjectName: row.subjectName,
        factClass: CharacterKnowledgeFactClass.fromWireName(row.factClass),
        scopeKey: row.scopeKey,
        predicate: row.predicate,
        object: row.object,
        epistemicState: CharacterKnowledgeEpistemicState.fromWireName(
          row.epistemicState,
        ),
        confidence: row.confidence,
        importance: row.importance,
        entities: _decodeStrings(row.entitiesJson),
        topics: _decodeStrings(row.topicsJson),
        sourceMessageId: row.sourceMessageId,
        sourceSwipeId: row.sourceSwipeId,
        sourceAgentSwipeId: row.sourceAgentSwipeId,
        sourceKind: row.sourceKind,
        supersedesId: row.supersedesId,
        lifecycle: CharacterKnowledgeFactLifecycle.fromWireName(row.lifecycle),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  List<String> _decodeStrings(String json) {
    try {
      return (jsonDecode(json) as List).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }
}

String semanticSlotKey(CharacterKnowledgeFact fact) => [
  fact.knowerKey,
  fact.subjectKey,
  fact.factClass.wireName,
  fact.scopeKey,
  fact.factClass == CharacterKnowledgeFactClass.relationship
      ? 'current_relationship_state'
      : fact.predicate.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
].join('\u0000');
