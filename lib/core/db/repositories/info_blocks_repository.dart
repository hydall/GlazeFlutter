import 'package:drift/drift.dart';

import '../app_db.dart';
import '../tables.dart';
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
    String messageId,
  ) async {
    final rows = await (select(infoBlocks)
          ..where((tbl) =>
              tbl.sessionId.equals(sessionId) &
              tbl.messageId.equals(messageId))
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

  Future<void> deleteBySessionId(String sessionId) async {
    await (delete(infoBlocks)
          ..where((tbl) => tbl.sessionId.equals(sessionId)))
        .go();
  }

  Future<void> deleteInfoBlock(String id) async {
    await (delete(infoBlocks)..where((tbl) => tbl.id.equals(id))).go();
  }

  InfoBlock _rowToModel(InfoBlockRow row) {
    return InfoBlock(
      id: row.id,
      sessionId: row.sessionId,
      messageId: row.messageId,
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
