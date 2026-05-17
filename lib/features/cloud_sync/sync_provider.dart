import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/db_provider.dart';
import '../../../core/services/image_storage_service.dart';
import 'services/sync_conflict.dart';
import 'services/sync_engine.dart';
import 'services/sync_service.dart';
import 'sync_config.dart';
import 'sync_models.dart';

final imageStorageProvider = FutureProvider<ImageStorageService>((ref) {
  return ImageStorageService.create();
});

final syncServiceProvider = FutureProvider<SyncService>((ref) async {
  await SyncConfig.load();

  final imageStorage = await ref.watch(imageStorageProvider.future);

  final service = SyncService(
    characterRepo: ref.watch(characterRepoProvider),
    chatRepo: ref.watch(chatRepoProvider),
    personaRepo: ref.watch(personaRepoProvider),
    presetRepo: ref.watch(presetRepoProvider),
    apiRepo: ref.watch(apiConfigRepoProvider),
    lorebookRepo: ref.watch(lorebookRepoProvider),
    embeddingRepo: ref.watch(embeddingRepoProvider),
    imageStorage: imageStorage,
  );
  await service.init();

  ref.read(syncProviderProvider.notifier).state = service.provider;
  ref.read(syncConnectedProvider.notifier).state = service.isConnected();
  ref.read(syncAutoEnabledProvider.notifier).state = service.autoSyncEnabled;

  return service;
});

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);
final syncProviderProvider = StateProvider<SyncProvider>((ref) => SyncProvider.dropbox);
final syncConnectedProvider = StateProvider<bool>((ref) => false);
final syncAutoEnabledProvider = StateProvider<bool>((ref) => false);
final syncConflictsProvider = StateProvider<List<SyncConflict>>((ref) => []);
final syncProgressProvider = StateProvider<SyncProgress?>((ref) => null);
final syncLastErrorProvider = StateProvider<String?>((ref) => null);

final autoSyncMessageCounterProvider = StateProvider<int>((ref) => 0);

void notifySyncMessageGenerated(Ref ref) {
  final autoEnabled = ref.read(syncAutoEnabledProvider);
  if (!autoEnabled) return;

  final counter = ref.read(autoSyncMessageCounterProvider) + 1;
  ref.read(autoSyncMessageCounterProvider.notifier).state = counter;

  final threshold = 5;
  if (counter >= threshold) {
    ref.read(autoSyncMessageCounterProvider.notifier).state = 0;
    final syncAsync = ref.read(syncServiceProvider);
    syncAsync.whenData((service) {
      if (service.isConnected()) {
        service.fullPush();
      }
    });
  }
}
