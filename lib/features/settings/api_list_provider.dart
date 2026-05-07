import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/api_config.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/sync_deletion_tracker.dart';

final activeApiPresetIdProvider = StateProvider<String?>((ref) => null);

final activeApiConfigProvider = Provider<ApiConfig?>((ref) {
  final list = ref.watch(apiListProvider).valueOrNull;
  final id = ref.watch(activeApiPresetIdProvider);
  if (list == null || list.isEmpty) return null;
  if (id == null) return list.first;
  return list.firstWhere((c) => c.id == id, orElse: () => list.first);
});

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
