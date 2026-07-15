import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import '../db/repositories/character_repo.dart';
import '../models/character.dart';
import '../models/lorebook.dart';
import '../utils/id_generator.dart';
import '../utils/sync_deletion_tracker.dart';
import '../utils/platform_paths.dart';
import '../utils/time_helpers.dart';
import 'db_provider.dart';
import 'lorebook_provider.dart';

const int kCharactersPageSize = 25;

class InfiniteCharactersKey {
  final CharacterSortField sort;
  final CharacterSortDir dir;

  /// When true the page query includes hidden characters (the user revealed
  /// them via the secret gesture). Part of the key so toggling reveal rebuilds
  /// the provider with a fresh query.
  final bool showHidden;

  const InfiniteCharactersKey({
    required this.sort,
    required this.dir,
    this.showHidden = false,
  });

  @override
  bool operator ==(Object other) =>
      other is InfiniteCharactersKey &&
      other.sort == sort &&
      other.dir == dir &&
      other.showHidden == showHidden;

  @override
  int get hashCode => Object.hash(sort, dir, showHidden);
}

/// Default key for the My Characters grid: newest first.
///
/// Must match the initial sort/dir of [CharacterListScreen] (`SortType.date` /
/// `SortDir.desc`). Used to warm [infiniteCharactersProvider] at startup so the
/// grid renders populated instead of flashing a spinner — keep the two in sync.
const kDefaultInfiniteCharactersKey = InfiniteCharactersKey(
  sort: CharacterSortField.date,
  dir: CharacterSortDir.desc,
);

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

/// All variations belonging to one variation group (representative first),
/// reactive to DB changes. Keyed by the group's [Character.variantGroupId].
final characterVariantsProvider = StreamProvider.autoDispose
    .family<List<Character>, String>((ref, groupId) {
      ref.watch(avatarVersionProvider);
      return ref.read(characterRepoProvider).watchVariants(groupId);
    });

final infiniteCharactersProvider =
    AsyncNotifierProvider.family<
      InfiniteCharactersNotifier,
      InfiniteCharactersState,
      InfiniteCharactersKey
    >(InfiniteCharactersNotifier.new);

final avatarVersionProvider = StateProvider<int>((ref) => 0);

/// Incremented each time the user taps the Characters navbar tab while that
/// branch is **already active** (a "re-tap"). The Characters screen listens and
/// scrolls the current sub-view (My / Discover) to the top; when Discover is
/// already at the top it switches back to the My Characters sub-tab instead.
final charactersTabReTapProvider = StateProvider<int>((ref) => 0);

void bumpAvatarVersion(dynamic ref) {
  ref.read(avatarVersionProvider.notifier).state++;
}

/// Number of taps on the Characters tab required to toggle reveal-hidden mode.
const int kRevealHiddenTapCount = 10;

/// Window in which those taps must occur.
const Duration kRevealHiddenTapWindow = Duration(milliseconds: 1500);

/// Whether hidden characters are currently revealed in the My Characters list.
///
/// Session-only (resets to `false` on app restart) so hidden characters re-hide
/// themselves automatically — the gesture must be repeated to reveal them again.
/// Toggled by [RevealHiddenNotifier.registerCharactersTabTap] when the user taps
/// the Characters tab [kRevealHiddenTapCount] times within [kRevealHiddenTapWindow].
final revealHiddenCharactersProvider =
    NotifierProvider<RevealHiddenNotifier, bool>(RevealHiddenNotifier.new);

class RevealHiddenNotifier extends Notifier<bool> {
  final List<int> _tapTimes = <int>[];

  @override
  bool build() => false;

  /// Records a tap on the Characters tab. Returns the new reveal state when the
  /// gesture completes (toggle happened), or `null` when it didn't.
  bool? registerCharactersTabTap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _tapTimes.add(now);
    _tapTimes.removeWhere(
      (t) => now - t > kRevealHiddenTapWindow.inMilliseconds,
    );
    if (_tapTimes.length >= kRevealHiddenTapCount) {
      _tapTimes.clear();
      state = !state;
      return state;
    }
    return null;
  }
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

    final initialCount = await repo
        .watchTotalCount(includeHidden: arg.showHidden)
        .first;
    final initialItems = await repo.getPage(
      limit: _loadedLimit,
      offset: 0,
      sort: arg.sort,
      dir: arg.dir,
      includeHidden: arg.showHidden,
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
        .watchPage(
          limit: _loadedLimit,
          offset: 0,
          sort: arg.sort,
          dir: arg.dir,
          includeHidden: arg.showHidden,
        )
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
    _countSub = repo
        .watchTotalCount(includeHidden: arg.showHidden)
        .listen(
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
    final initial = await repo.getAll();
    // One-time: populate cached token counts for rows predating the column.
    // Unawaited + chunked so it never blocks first paint.
    unawaited(repo.backfillMissingTokenCounts());
    return initial;
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

  /// Creates a new variation cloned from [source] (copy-of-current-card). The
  /// new row joins [source]'s variation group at the next free order, gets its
  /// own copied avatar file (so deleting it never orphans a sibling), and
  /// starts with an empty gallery. Returns the created variation.
  Future<Character> addVariant(Character source, String name) async {
    final repo = ref.read(characterRepoProvider);
    final groupId = source.variantGroupId.isEmpty
        ? source.id
        : source.variantGroupId;
    final newId = generateId();
    final order = await repo.nextVariantOrder(groupId);

    // Copy the avatar so the variation owns its image file.
    String? avatarPath;
    final srcAvatar = source.avatarPath;
    if (srcAvatar != null && srcAvatar.isNotEmpty) {
      try {
        final imageStorage = await ref.read(imageStorageProvider.future);
        final resolved = resolveGlazeFilePath(srcAvatar) ?? srcAvatar;
        final bytes = await File(resolved).readAsBytes();
        avatarPath = await imageStorage.saveAvatar(newId, bytes);
      } catch (_) {
        avatarPath = null;
      }
    }

    final trimmed = name.trim();
    final now = currentTimestampSeconds();
    final variant = source.copyWith(
      id: newId,
      variantGroupId: groupId,
      variantName: trimmed.isEmpty ? null : trimmed,
      variantOrder: order,
      avatarPath: avatarPath,
      gallery: const [],
      fav: false,
      createdAt: now,
      updatedAt: now,
    );
    await repo.put(variant);
    ref.invalidateSelf();
    return variant;
  }

  Future<void> renameVariant(String charId, String name) async {
    await ref.read(characterRepoProvider).renameVariant(charId, name);
    ref.invalidateSelf();
  }

  /// Hides or reveals a character's whole variation group. Resolves the group
  /// from [charId] so callers can pass any member (including a standalone card).
  Future<void> setHidden(String charId, bool hidden) async {
    final repo = ref.read(characterRepoProvider);
    final char = await repo.getById(charId);
    final groupId = (char == null || char.variantGroupId.isEmpty)
        ? charId
        : char.variantGroupId;
    await repo.setHidden(groupId, hidden);
    ref.invalidateSelf();
  }

  Future<void> reorderVariants(String groupId, List<String> orderedIds) async {
    await ref.read(characterRepoProvider).reorderVariants(groupId, orderedIds);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    final repo = ref.read(characterRepoProvider);
    await repo.delete(id);
    ref.invalidateSelf();
  }

  /// Hides or reveals every character in [charIds] at once. Batched in one DB
  /// transaction (via [CharacterRepo.setHiddenMany]) so the grid rebuilds a
  /// single time — the cards leave together instead of one-by-one.
  Future<void> setHiddenMany(Set<String> charIds, bool hidden) async {
    if (charIds.isEmpty) return;
    final repo = ref.read(characterRepoProvider);
    await repo.setHiddenMany(charIds, hidden);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) => removeMany({id});

  /// Deletes every character in [ids] together. All row deletions run inside one
  /// transaction so the reactive `watchAll()` stream emits a **single** update —
  /// the selected cards leave the grid in one frame instead of disappearing
  /// one-by-one (the lag the bulk-delete flow used to have). Per-character file
  /// cleanup runs afterwards, outside the transaction.
  Future<void> removeMany(Set<String> ids) async {
    if (ids.isEmpty) return;
    final repo = ref.read(characterRepoProvider);
    final chatRepo = ref.read(chatRepoProvider);
    final lorebookRepo = ref.read(lorebookRepoProvider);
    final embeddingRepo = ref.read(embeddingRepoProvider);

    final characters = <Character>[];
    for (final id in ids) {
      final character = await repo.getById(id);
      if (character != null) characters.add(character);
    }

    await chatRepo.transaction(() async {
      for (final id in ids) {
        final deletedSessionIds = await chatRepo.deleteByCharacterId(id);
        for (final sid in deletedSessionIds) {
          final studioConfig = await ref
              .read(studioConfigRepoProvider)
              .getBySessionId(sid);
          await ref.read(studioConfigRepoProvider).deleteBySessionId(sid);
          await SyncDeletionTracker.record('chat', sid);
          await SyncDeletionTracker.record('memory_book', sid);
          await SyncDeletionTracker.record('tracker_value', sid);
          await SyncDeletionTracker.record('tracker_snapshot', sid);
          final studioProfileId = studioConfig?.profileId ?? '';
          if (studioConfig != null &&
              (studioProfileId.isEmpty || studioProfileId == sid)) {
            await SyncDeletionTracker.record('studio_config', sid);
          }
        }

        final lorebooks =
            await lorebookRepo.getByScopeAndTarget('character', id);
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
      }
    });

    for (final character in characters) {
      await _cleanupFiles(character);
    }
  }

  Future<void> _cleanupFiles(Character character) async {
    try {
      if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
        final resolved =
            resolveGlazeFilePath(character.avatarPath!) ??
            character.avatarPath!;
        final avatar = File(resolved);
        if (await avatar.exists()) await avatar.delete();
        final name = p.basenameWithoutExtension(resolved);
        final dir = p.dirname(p.dirname(resolved));
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
