import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/api_config.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/sync_deletion_tracker.dart';

final apiListProvider = AsyncNotifierProvider<ApiListNotifier, List<ApiConfig>>(
  ApiListNotifier.new,
);

class ApiListNotifier extends AsyncNotifier<List<ApiConfig>> {
  @override
  Future<List<ApiConfig>> build() async {
    return ref.watch(apiConfigRepoProvider).getAll();
  }

  Future<void> put(ApiConfig config) async {
    await ref.read(apiConfigRepoProvider).put(config);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(apiConfigRepoProvider).delete(id);
    await SyncDeletionTracker.record('api_presets', id);
    ref.invalidateSelf();
  }
}
