import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/character_tokens.dart';
import '../../core/models/character.dart';
import '../../core/state/character_folder_provider.dart';
import '../../core/state/character_provider.dart';
import 'widgets/character_grid.dart' show SortType, SortDir;

/// Immutable description of a My-Characters query: which characters to keep
/// (search + filters + optional folder) and how to order them. Value equality
/// lets [filteredCharactersProvider] cache the result and recompute only when
/// the inputs actually change — keeping the (potentially O(n log n)) filter +
/// sort out of the widget build method.
@immutable
class CharacterQuery {
  final String search;
  final bool favOnly;
  final List<String> tags; // kept sorted by the caller
  final int minTokens;
  final int maxTokens;
  final bool hasTokenFilter;
  final SortType sortBy;
  final SortDir sortDir;
  final String? folderId;

  const CharacterQuery({
    required this.search,
    required this.favOnly,
    required this.tags,
    required this.minTokens,
    required this.maxTokens,
    required this.hasTokenFilter,
    required this.sortBy,
    required this.sortDir,
    this.folderId,
  });

  @override
  bool operator ==(Object other) =>
      other is CharacterQuery &&
      other.search == search &&
      other.favOnly == favOnly &&
      other.minTokens == minTokens &&
      other.maxTokens == maxTokens &&
      other.hasTokenFilter == hasTokenFilter &&
      other.sortBy == sortBy &&
      other.sortDir == sortDir &&
      other.folderId == folderId &&
      listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(
        search,
        favOnly,
        minTokens,
        maxTokens,
        hasTokenFilter,
        sortBy,
        sortDir,
        folderId,
        Object.hashAll(tags),
      );
}

/// Filtered + sorted characters for a [CharacterQuery]. Depends on
/// [charactersProvider] (and [folderMembershipsProvider] when scoped to a
/// folder), so it re-runs reactively when the library changes, and is cached
/// per distinct query otherwise.
final filteredCharactersProvider =
    Provider.autoDispose.family<List<Character>, CharacterQuery>((ref, q) {
  final all = ref.watch(charactersProvider).value ?? const <Character>[];

  Iterable<Character> list = all;
  if (q.folderId != null) {
    final memberships =
        ref.watch(folderMembershipsProvider).value ?? FolderMemberships.empty;
    final ids = memberships.charsIn(q.folderId!);
    list = list.where((c) => ids.contains(c.id));
  }

  final result = list.where((c) => _passes(q, c)).toList();
  _sort(result, q);
  return result;
});

bool _passes(CharacterQuery q, Character c) {
  if (q.search.isNotEmpty) {
    final query = q.search.toLowerCase();
    final displayName = c.displayName?.toLowerCase() ?? '';
    final matchesSearch = c.fav ||
        c.name.toLowerCase().contains(query) ||
        displayName.contains(query);
    if (!matchesSearch) return false;
  }
  if (q.favOnly && !c.fav) return false;
  if (q.tags.isNotEmpty) {
    final charTags = c.tags.toSet();
    if (!q.tags.every(charTags.contains)) return false;
  }
  if (q.hasTokenFilter) {
    final tokens = c.tokenCount > 0 ? c.tokenCount : estimateCharacterTokens(c);
    if (tokens < q.minTokens || tokens > q.maxTokens) return false;
  }
  return true;
}

String _displayNameOf(Character c) {
  final displayName = c.displayName?.trim();
  return (displayName != null && displayName.isNotEmpty)
      ? displayName
      : c.name;
}

void _sort(List<Character> list, CharacterQuery q) {
  // lastChat ordering isn't available client-side here; fall back to name.
  final effectiveSort = q.sortBy == SortType.lastChat ? SortType.name : q.sortBy;
  list.sort((a, b) {
    if (a.fav != b.fav) return a.fav ? -1 : 1;
    final cmp = switch (effectiveSort) {
      SortType.name => _displayNameOf(a)
          .toLowerCase()
          .compareTo(_displayNameOf(b).toLowerCase()),
      SortType.date => a.createdAt.compareTo(b.createdAt),
      SortType.lastChat => _displayNameOf(a)
          .toLowerCase()
          .compareTo(_displayNameOf(b).toLowerCase()),
    };
    if (cmp != 0) return q.sortDir == SortDir.desc ? -cmp : cmp;
    return a.id.compareTo(b.id);
  });
}
