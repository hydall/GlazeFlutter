import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/memory_graph.dart';
import '../../utils/time_helpers.dart';
import '../app_db.dart';

class MemoryConsolidationRepo {
  final AppDatabase db;

  const MemoryConsolidationRepo(this.db);

  Future<List<MemoryConsolidation>> getBySessionId(
    String sessionId, {
    int? tier,
  }) {
    final query = db.select(db.memoryConsolidationRows)
      ..where((row) => row.chatSessionId.equals(sessionId));
    if (tier != null) {
      query.where((row) => row.tier.equals(tier));
    }
    query.orderBy([(row) => OrderingTerm(expression: row.messageRangeStart)]);
    return query.get().then((rows) => rows.map(_rowToModel).toList());
  }

  Future<List<MemoryConsolidation>> getUnconsolidated(String sessionId) {
    return (db.select(db.memoryConsolidationRows)
          ..where(
            (row) =>
                row.chatSessionId.equals(sessionId) &
                row.status.equals('pending'),
          ))
        .get()
        .then((rows) => rows.map(_rowToModel).toList());
  }

  Future<void> upsert(MemoryConsolidation consolidation) {
    return db.into(db.memoryConsolidationRows).insertOnConflictUpdate(
      MemoryConsolidationRowsCompanion.insert(
        id: consolidation.id,
        chatSessionId: consolidation.chatSessionId,
        tier: Value(consolidation.tier),
        title: Value(consolidation.title),
        summary: Value(consolidation.summary),
        sourceEntryIdsJson: Value(jsonEncode(consolidation.sourceEntryIds)),
        entityIdsJson: Value(jsonEncode(consolidation.entityIds)),
        messageRangeStart: Value(consolidation.messageRangeStart),
        messageRangeEnd: Value(consolidation.messageRangeEnd),
        salienceAvg: Value(consolidation.salienceAvg),
        emotionalTagsJson: Value(jsonEncode(consolidation.emotionalTags)),
        tokenCount: Value(consolidation.tokenCount),
        sourceModel: Value(consolidation.sourceModel),
        status: Value(consolidation.status),
        errorMessage: Value(consolidation.errorMessage),
        createdAt: Value(consolidation.createdAt),
        updatedAt: Value(currentTimestampSeconds()),
      ),
    );
  }

  Future<void> updateStatus(
    String id,
    String status,
    String? errorMessage,
  ) {
    return (db.update(db.memoryConsolidationRows)
          ..where((row) => row.id.equals(id)))
        .write(MemoryConsolidationRowsCompanion(
      status: Value(status),
      errorMessage: Value(errorMessage ?? ''),
      updatedAt: Value(currentTimestampSeconds()),
    ));
  }

  Future<void> deleteBySessionId(String sessionId) {
    return (db.delete(
      db.memoryConsolidationRows,
    )..where((row) => row.chatSessionId.equals(sessionId))).go();
  }

  MemoryConsolidation _rowToModel(MemoryConsolidationRow row) {
    List<String> sourceEntryIds;
    try {
      sourceEntryIds = (jsonDecode(row.sourceEntryIdsJson) as List<dynamic>)
          .map((e) => e as String)
          .toList();
    } catch (_) {
      sourceEntryIds = [];
    }

    List<String> entityIds;
    try {
      entityIds = (jsonDecode(row.entityIdsJson) as List<dynamic>)
          .map((e) => e as String)
          .toList();
    } catch (_) {
      entityIds = [];
    }

    List<String> emotionalTags;
    try {
      emotionalTags = (jsonDecode(row.emotionalTagsJson) as List<dynamic>)
          .map((e) => e as String)
          .toList();
    } catch (_) {
      emotionalTags = [];
    }

    return MemoryConsolidation(
      id: row.id,
      chatSessionId: row.chatSessionId,
      tier: row.tier,
      title: row.title,
      summary: row.summary,
      sourceEntryIds: sourceEntryIds,
      entityIds: entityIds,
      messageRangeStart: row.messageRangeStart,
      messageRangeEnd: row.messageRangeEnd,
      salienceAvg: row.salienceAvg,
      emotionalTags: emotionalTags,
      tokenCount: row.tokenCount,
      sourceModel: row.sourceModel,
      status: row.status,
      errorMessage: row.errorMessage,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
