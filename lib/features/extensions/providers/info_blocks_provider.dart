import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/state/db_provider.dart';
import '../models/block_run_status.dart';
import '../models/info_block.dart';

final infoBlocksProvider = StateNotifierProvider.family<
    InfoBlocksNotifier, List<InfoBlock>, String>(
  (ref, sessionId) => InfoBlocksNotifier(ref, sessionId),
);

class InfoBlocksNotifier extends StateNotifier<List<InfoBlock>> {
  InfoBlocksNotifier(this._ref, this.sessionId) : super([]) {
    _load();
  }

  final Ref _ref;
  final String sessionId;

  InfoBlocksRepository get _repo =>
      InfoBlocksRepository(_ref.read(appDbProvider));

  Future<void> _load() async {
    state = await _repo.getBySessionId(sessionId);
  }

  /// Inserts or replaces a block in state (matched by id).
  /// Does NOT write to DB — caller is responsible for DB persistence.
  void addOrReplace(InfoBlock block) {
    final idx = state.indexWhere((b) => b.id == block.id);
    if (idx >= 0) {
      final updated = List<InfoBlock>.from(state);
      updated[idx] = block;
      state = updated;
    } else {
      state = [block, ...state];
    }
  }

  /// Removes all blocks for [messageId] + [blockId] from in-memory state.
  /// Does NOT delete from DB — caller handles that.
  void removeByBlockId({required String messageId, required String blockId}) {
    state = state
        .where((b) => !(b.messageId == messageId && b.blockId == blockId))
        .toList();
  }

  /// Updates the status of a block in state.
  void updateStatus(String id, BlockRunStatus status) {
    final idx = state.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    final updated = List<InfoBlock>.from(state);
    updated[idx] = updated[idx].copyWith(status: status);
    state = updated;
  }

  Future<void> delete(String id) async {
    await _repo.deleteInfoBlock(id);
    state = state.where((b) => b.id != id).toList();
  }

  Future<void> clear() async {
    await _repo.deleteBySessionId(sessionId);
    state = [];
  }

  Future<void> refresh() async {
    await _load();
  }

  /// Returns all blocks for a specific message, sorted by order.
  List<InfoBlock> getByMessageId(String messageId) {
    return state
        .where((b) => b.messageId == messageId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Aggregated status for a message:
  /// - 'running' if any block is running
  /// - 'error' if any block errored (and none running)
  /// - 'done' if all blocks done/stopped
  /// - null if no blocks
  String? aggregatedStatus(String messageId) {
    final blocks = getByMessageId(messageId);
    if (blocks.isEmpty) return null;
    if (blocks.any((b) => b.status == BlockRunStatus.running)) return 'running';
    if (blocks.any((b) => b.status == BlockRunStatus.error)) return 'error';
    return 'done';
  }
}
