import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/character.dart';
import '../models/lorebook.dart';
import '../utils/sync_deletion_tracker.dart';
import 'db_provider.dart';
import 'lorebook_provider.dart';

final charactersProvider = AsyncNotifierProvider<CharactersNotifier, List<Character>>(
  CharactersNotifier.new,
);

final characterByIdProvider = Provider.family<Character?, String>((ref, id) {
  ref.watch(avatarVersionProvider);
  final chars = ref.watch(charactersProvider).value ?? [];
  return chars.where((c) => c.id == id).firstOrNull;
});

final avatarVersionProvider = StateProvider<int>((ref) => 0);

void bumpAvatarVersion(dynamic ref) {
  ref.read(avatarVersionProvider.notifier).state++;
}

class CharactersNotifier extends AsyncNotifier<List<Character>> {
  StreamSubscription<List<Character>>? _sub;

  @override
  Future<List<Character>> build() async {
    ref.keepAlive();
    await _sub?.cancel();
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
    ref.invalidateSelf();
  }

  Future<void> save(Character character) async {
    final repo = ref.read(characterRepoProvider);
    await repo.put(character);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    final repo = ref.read(characterRepoProvider);
    await repo.delete(id);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final repo = ref.read(characterRepoProvider);
    final chatRepo = ref.read(chatRepoProvider);
    final lorebookRepo = ref.read(lorebookRepoProvider);
    final embeddingRepo = ref.read(embeddingRepoProvider);
    final character = await repo.getById(id);

    await chatRepo.transaction(() async {
      final deletedSessionIds = await chatRepo.deleteByCharacterId(id);
      for (final sid in deletedSessionIds) {
        await SyncDeletionTracker.record('chat', sid);
        await SyncDeletionTracker.record('memory_book', sid);
      }

      final lorebooks = await lorebookRepo.getByScopeAndTarget('character', id);
      for (final lb in lorebooks) {
        await lorebookRepo.delete(lb.id);
        await embeddingRepo.deleteBySourceId(lb.id);
        await SyncDeletionTracker.record('lorebooks', lb.id);
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
    });

    if (character != null) {
      await _cleanupFiles(character);
    }
  }

  Future<void> _cleanupFiles(Character character) async {
    try {
      if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
        final avatar = File(character.avatarPath!);
        if (await avatar.exists()) await avatar.delete();
        final name = p.basenameWithoutExtension(character.avatarPath!);
        final dir = p.dirname(p.dirname(character.avatarPath!));
        final thumb = File(p.join(dir, 'thumbnails', '$name.jpg'));
        if (await thumb.exists()) await thumb.delete();
      }
      if (character.gallery.isNotEmpty) {
        final avatarDir = character.avatarPath != null
            ? p.dirname(character.avatarPath!)
            : null;
        if (avatarDir != null) {
          final galleryDir = Directory(p.join(p.dirname(avatarDir), 'gallery', character.id));
          if (await galleryDir.exists()) await galleryDir.delete(recursive: true);
        }
      }
    } catch (_) {}
  }
}
