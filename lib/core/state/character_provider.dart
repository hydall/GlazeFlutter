import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/character.dart';
import '../models/lorebook.dart';
import '../utils/sync_deletion_tracker.dart';
import 'db_provider.dart';
import 'lorebook_provider.dart';

final charactersProvider = AsyncNotifierProvider<CharactersNotifier, List<Character>>(
  CharactersNotifier.new,
);

class CharactersNotifier extends AsyncNotifier<List<Character>> {
  StreamSubscription<List<Character>>? _sub;

  @override
  Future<List<Character>> build() async {
    ref.keepAlive();
    _sub?.cancel();
    final repo = ref.read(characterRepoProvider);
    _sub = repo.watchAll().listen(
      (data) {
        if (state.hasValue && state.value!.length == data.length) {
          bool same = true;
          for (int i = 0; i < data.length; i++) {
            if (data[i] != state.value![i]) {
              same = false;
              break;
            }
          }
          if (same) return;
        }
        state = AsyncData(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        state = AsyncError(error, stackTrace);
      },
    );
    ref.onDispose(() => _sub?.cancel());
    return repo.getAll();
  }

  Future<void> add(Character character) async {
    final repo = ref.read(characterRepoProvider);
    await repo.put(character);
  }

  Future<void> remove(String id) async {
    final repo = ref.read(characterRepoProvider);
    final chatRepo = ref.read(chatRepoProvider);
    final deletedSessionIds = await chatRepo.deleteByCharacterId(id);
    for (final sid in deletedSessionIds) {
      await SyncDeletionTracker.record('chat', sid);
    }

    final lorebookRepo = ref.read(lorebookRepoProvider);
    final embeddingRepo = ref.read(embeddingRepoProvider);
    final lorebooks = await lorebookRepo.getAll();
    for (final lb in lorebooks) {
      if (lb.activationScope == 'character' && lb.activationTargetId == id) {
        await lorebookRepo.delete(lb.id);
        await embeddingRepo.deleteBySourceId(lb.id);
        await SyncDeletionTracker.record('lorebooks', lb.id);
      }
    }

    final activations = ref.read(lorebookActivationsProvider);
    if (activations.character.containsKey(id)) {
      final charMap = <String, List<String>>{};
      for (final e in activations.character.entries) {
        if (e.key != id) charMap[e.key] = List<String>.from(e.value);
      }
      final cleaned = LorebookActivations(character: charMap, chat: activations.chat);
      ref.read(lorebookActivationsProvider.notifier).state = cleaned;
      await saveLorebookActivations(cleaned);
    }

    await repo.delete(id);
    await SyncDeletionTracker.record('character', id);
  }
}
