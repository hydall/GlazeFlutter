import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/character.dart';
import '../utils/sync_deletion_tracker.dart';
import 'db_provider.dart';

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
    _sub = repo.watchAll().listen((data) {
      if (state.hasValue && state.value!.length == data.length) {
        bool same = true;
        for (int i = 0; i < data.length; i++) {
          if (data[i].id != state.value![i].id ||
              data[i].updatedAt != state.value![i].updatedAt) {
            same = false;
            break;
          }
        }
        if (same) return;
      }
      state = AsyncData(data);
    });
    ref.onDispose(() => _sub?.cancel());
    return repo.getAll();
  }

  Future<void> add(Character character) async {
    final repo = ref.read(characterRepoProvider);
    await repo.put(character);
  }

  Future<void> remove(String id) async {
    final repo = ref.read(characterRepoProvider);
    await repo.delete(id);
    await SyncDeletionTracker.record('character', id);
  }
}
