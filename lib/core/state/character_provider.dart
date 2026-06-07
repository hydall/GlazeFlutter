import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import '../db/repositories/character_repo.dart';
import '../models/character.dart';
import '../models/lorebook.dart';
import '../utils/sync_deletion_tracker.dart';
import 'db_provider.dart';
import 'lorebook_provider.dart';

const int kCharactersPageSize = 25;

class InfiniteCharactersKey {
  final CharacterSortField sort;
  final CharacterSortDir dir;

  const InfiniteCharactersKey({required this.sort, required this.dir});

  @override
  bool operator ==(Object other) =>
      other is InfiniteCharactersKey && other.sort == sort && other.dir == dir;

  @override
  int get hashCode => Object.hash(sort, dir);
}

class InfiniteCharactersState {
  final List<Character> items;
  final int totalCount;
  final int loadedLimit;
  final bool isLoadingMore;

  const InfiniteCharactersState({
    required this.items,
    required this.totalCount,
    required this.loadedLimit,
    this.isLoadingMore = false,
  });

  bool get hasMore => items.length < totalCount;

  InfiniteCharactersState copyWith({
    List<Character>? items,
    int? totalCount,
    int? loadedLimit,
    bool? isLoadingMore,
  }) => InfiniteCharactersState(
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    loadedLimit: loadedLimit ?? this.loadedLimit,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );
}

final charactersProvider =
    AsyncNotifierProvider<CharactersNotifier, List<Character>>(
      CharactersNotifier.new,
    );

final characterByIdProvider = Provider.family<Character?, String>((ref, id) {
  ref.watch(avatarVersionProvider);
  final chars = ref.watch(charactersProvider).value ?? [];
  return chars.where((c) => c.id == id).firstOrNull;
});

final infiniteCharactersProvider =
    AsyncNotifierProvider.family<
      InfiniteCharactersNotifier,
      InfiniteCharactersState,
      InfiniteCharactersKey
    >(InfiniteCharactersNotifier.new);

final avatarVersionProvider = StateProvider<int>((ref) => 0);

void bumpAvatarVersion(dynamic ref) {
  ref.read(avatarVersionProvider.notifier).state++;
}

class InfiniteCharactersNotifier
    extends AsyncNotifier<InfiniteCharactersState> {
  InfiniteCharactersNotifier(this.arg);

  final InfiniteCharactersKey arg;
  StreamSubscription<List<Character>>? _itemsSub;
  StreamSubscription<int>? _countSub;
  int _loadedLimit = kCharactersPageSize;

  @override
  Future<InfiniteCharactersState> build() async {
    final repo = ref.read(characterRepoProvider);
    _loadedLimit = kCharactersPageSize;

    await _itemsSub?.cancel();
    await _countSub?.cancel();

    final initialCount = await repo.watchTotalCount().first;
    final initialItems = await repo.getPage(
      limit: _loadedLimit,
      offset: 0,
      sort: arg.sort,
      dir: arg.dir,
    );

    state = AsyncData(
      InfiniteCharactersState(
        items: initialItems,
        totalCount: initialCount,
        loadedLimit: _loadedLimit,
      ),
    );

    _subscribeItems();
    _subscribeCount();

    ref.onDispose(() {
      _itemsSub?.cancel();
      _countSub?.cancel();
    });

    return state.value!;
  }

  void _subscribeItems() {
    final repo = ref.read(characterRepoProvider);
    _itemsSub?.cancel();
    _itemsSub = repo
        .watchPage(limit: _loadedLimit, offset: 0, sort: arg.sort, dir: arg.dir)
        .listen(
          (data) {
            final current = state.value;
            if (current == null) return;
            state = AsyncData(
              current.copyWith(
                items: data,
                loadedLimit: _loadedLimit,
                isLoadingMore: false,
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncError<InfiniteCharactersState>(error, stackTrace);
          },
        );
  }

  void _subscribeCount() {
    final repo = ref.read(characterRepoProvider);
    _countSub?.cancel();
    _countSub = repo.watchTotalCount().listen(
      (count) {
        final current = state.value;
        if (current == null) return;
        state = AsyncData(current.copyWith(totalCount: count));
      },
      onError: (Object error, StackTrace stackTrace) {
        state = AsyncError<InfiniteCharactersState>(error, stackTrace);
      },
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    _loadedLimit += kCharactersPageSize;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    _subscribeItems();
  }
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
        final cleaned = LorebookActivations(
          character: charMap,
          chat: activations.chat,
        );
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
          final galleryDir = Directory(
            p.join(p.dirname(avatarDir), 'gallery', character.id),
          );
          if (await galleryDir.exists()) {
            await galleryDir.delete(recursive: true);
          }
        }
      }
    } catch (_) {}
  }
}
