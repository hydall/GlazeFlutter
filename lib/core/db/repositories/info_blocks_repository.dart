import 'package:drift/drift.dart';

import '../app_db.dart';
import '../tables.dart';
import '../../../core/utils/sync_deletion_tracker.dart';
import '../../../features/extensions/models/block_run_status.dart';
import '../../../features/extensions/models/info_block.dart';

part 'info_blocks_repository.g.dart';

@DriftAccessor(tables: [InfoBlocks])
class InfoBlocksRepository extends DatabaseAccessor<AppDatabase>
    with _$InfoBlocksRepositoryMixin {
  InfoBlocksRepository(super.db);

  Future<void> insert(InfoBlock block) async {
    await into(infoBlocks).insert(InfoBlocksCompanion.insert(
      id: block.id,
      sessionId: block.sessionId,
      messageId: block.messageId,
      swipeId: Value(block.swipeId),
      blockId: block.blockId,
      blockType: block.blockType,
      blockName: block.blockName,
      content: block.content,
      createdAt: Value(block.createdAt),
      order_: Value(block.order),
      status: Value(block.status.name),
    ));
  }

  Future<void> updateStatus(String id, BlockRunStatus status) async {
    await (update(infoBlocks)..where((t) => t.id.equals(id)))
        .write(InfoBlocksCompanion(status: Value(status.name)));
  }

  Future<void> updateContent(String id, String content) async {
    await (update(infoBlocks)..where((t) => t.id.equals(id)))
        .write(InfoBlocksCompanion(content: Value(content)));
  }

  Future<List<InfoBlock>> getBySessionId(String sessionId) async {
    final rows = await (select(infoBlocks)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();

    return rows.map(_rowToModel).toList();
  }

  Future<List<InfoBlock>> getByMessageId(
    String sessionId,
    String messageId, {
    int swipeId = 0,
  }) async {
    final rows = await (select(infoBlocks)
          ..where((tbl) =>
              tbl.sessionId.equals(sessionId) &
              tbl.messageId.equals(messageId) &
              tbl.swipeId.equals(swipeId))
          ..orderBy([(t) => OrderingTerm.asc(t.order_)]))
        .get();

    return rows.map(_rowToModel).toList();
  }

  Future<List<InfoBlock>> getRecentBlocks(
    String sessionId,
    String blockName,
    int count,
  ) async {
    final rows = await (select(infoBlocks)
          ..where((tbl) =>
              tbl.sessionId.equals(sessionId) &
              tbl.blockName.equals(blockName))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.asc(t.order_),
          ])
          ..limit(count))
        .get();

    return rows.map(_rowToModel).toList();
  }

  /// Returns all distinct sessionIds that have at least one info block.
  Future<List<String>> getAllSessionIds() async {
    final rows = await customSelect(
      'SELECT DISTINCT session_id FROM info_blocks',
      readsFrom: {infoBlocks},
    ).get();
    return rows.map((r) => r.read<String>('session_id')).toList();
  }

  Future<void> deleteBySessionId(String sessionId) async {
    await (delete(infoBlocks)
          ..where((tbl) => tbl.sessionId.equals(sessionId)))
        .go();
    await SyncDeletionTracker.record('info_block', sessionId);
  }

  Future<void> deleteInfoBlock(String id) async {
    await (delete(infoBlocks)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> deleteByMessageId(
    String sessionId,
    String messageId, {
    int? swipeId,
  }) async {
    await (delete(infoBlocks)
          ..where((tbl) {
            final base =
                tbl.sessionId.equals(sessionId) & tbl.messageId.equals(messageId);
            return swipeId == null ? base : base & tbl.swipeId.equals(swipeId);
          }))
        .go();
  }

  InfoBlock _rowToModel(InfoBlockRow row) {
    return InfoBlock(
      id: row.id,
      sessionId: row.sessionId,
      messageId: row.messageId,
      swipeId: row.swipeId,
      blockId: row.blockId,
      blockName: row.blockName,
      blockType: row.blockType,
      content: row.content,
      createdAt: row.createdAt,
      order: row.order_,
      status: BlockRunStatus.values.byName(row.status),
    );
  }
}
