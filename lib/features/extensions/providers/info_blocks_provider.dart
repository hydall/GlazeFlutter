import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/state/db_provider.dart';
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

  Future<void> add(InfoBlock block) async {
    await _repo.insert(block);
    state = [block, ...state];
  }

  Future<void> delete(String id) async {
    await _repo.deleteInfoBlock(id);
    state = state.where((b) => b.id != id).toList();
  }

  Future<List<InfoBlock>> getRecentBlocks(String blockName, int count) async {
    return await _repo.getRecentBlocks(sessionId, blockName, count);
  }

  Future<void> clear() async {
    await _repo.deleteBySessionId(sessionId);
    state = [];
  }

  Future<void> refresh() async {
    await _load();
  }
}
