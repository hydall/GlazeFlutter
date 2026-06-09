import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'janitor_webview_proxy.dart';
import '../catalog_models.dart';

const _hampterUrl = 'https://janitorai.com/hampter/characters';
const _imageBase = 'https://ella.janitorai.com/bot-avatars/';

const _fallbackTagMap = <int, String>{
  1: 'Male',
  2: 'Female',
  3: 'Non-binary',
  4: 'Celebrity',
  5: 'OC',
  6: 'Fictional',
  7: 'Real',
  8: 'Game',
  9: 'Anime',
  10: 'Historical',
  11: 'Royalty',
  12: 'Detective',
  13: 'Hero',
  14: 'Villain',
  15: 'Magical',
  16: 'Non-human',
  17: 'Monster',
  18: 'Monster Girl',
  19: 'Alien',
  20: 'Robot',
  21: 'Politics',
  22: 'Vampire',
  23: 'Giant',
  24: 'OpenAI',
  25: 'Elf',
  26: 'Multiple',
  27: 'VTuber',
  28: 'Dominant',
  29: 'Submissive',
  30: 'Scenario',
  31: 'Pokemon',
  32: 'Assistant',
  34: 'Non-English',
  36: 'Philosophy',
  38: 'RPG',
  39: 'Religion',
  41: 'Books',
  42: 'AnyPOV',
  43: 'Angst',
  44: 'Demi-Human',
  45: 'Enemies to Lovers',
  46: 'Smut',
  47: 'MLM',
  48: 'WLW',
  49: 'Action',
  50: 'Romance',
  51: 'Horror',
  52: 'Slice of Life',
  53: 'Fantasy',
  54: 'Drama',
  55: 'Comedy',
  56: 'Mystery',
  57: 'Sci-Fi',
  59: 'Yandere',
  60: 'Furry',
  61: 'Movies/TV',
};

List<CatalogTag> _cachedJanitorTags = [];
Map<int, String> _janitorTagMap = Map.from(_fallbackTagMap);
bool _tagsFetched = false;
List<CatalogTag> getCachedJanitorTags() => _cachedJanitorTags;

Future<List<CatalogTag>> fetchJanitorTags() async {
  if (_tagsFetched) return _cachedJanitorTags;
  try {
    const tagsUrl = 'https://janitorai.com/hampter/tags';
    final data = (await _janitorFetch(tagsUrl) as List).cast<dynamic>();
    if (data.isNotEmpty) {
      _cachedJanitorTags = data
          .map((t) => CatalogTag(
                id: t['id'] as int?,
                name: (t['name'] ?? '') as String,
                slug: (t['slug'] ?? '') as String?,
              ))
          .toList();
      final map = <int, String>{};
      for (final t in data) {
        if (t['id'] != null) map[t['id'] as int] = (t['name'] ?? '') as String;
      }
      _janitorTagMap = map;
    } else {
      _cachedJanitorTags = _fallbackTagMap.entries
          .map((e) => CatalogTag(id: e.key, name: e.value))
          .toList();
    }
    _tagsFetched = true;
  } catch (_) {
    if (_cachedJanitorTags.isEmpty) {
      _cachedJanitorTags = _fallbackTagMap.entries
          .map((e) => CatalogTag(id: e.key, name: e.value))
          .toList();
    }
  }
  return _cachedJanitorTags;
}

/// Fetches [url] from inside the janitor WebView session and decodes the JSON
/// body. The WebView proxy transparently solves the Cloudflare Turnstile
/// challenge (see [JanitorWebViewProxy] for why Dio can't be used here).
Future<dynamic> _janitorFetch(String url) async {
  debugPrint('[CF] janitorFetch: ${url.length > 80 ? url.substring(0, 80) : url}');
  final body = await JanitorWebViewProxy.instance.fetch(url);
  return jsonDecode(body);
}

Future<CatalogSearchResult> janitorSearch({
  String query = '',
  int page = 1,
  CatalogFilters filters = const CatalogFilters(),
}) async {
  final activeSort = filters.sort;
  String sortMode = 'trending';
  if (activeSort == 'popular' || activeSort == 'trending_week') {
    sortMode = 'trending';
  } else if (activeSort == 'trending_24h') {
    sortMode = 'trending24';
  } else if (activeSort == 'newest' || activeSort == 'latest') {
    sortMode = 'latest';
  } else {
    sortMode = activeSort;
  }

  final params = StringBuffer('sort=$sortMode&page=$page');
  if (query.isNotEmpty) params.write('&search=${Uri.encodeComponent(query)}');
  params.write(filters.nsfw ? '&mode=all' : '&mode=sfw');

  for (final tagId in filters.tagIds) {
    params.write('&tag_id[]=$tagId');
  }
  for (final tagName in filters.tagNames) {
    params.write('&custom_tags[]=${Uri.encodeComponent(tagName)}');
  }

  final searchUrl = '$_hampterUrl?$params';
  final data = await _janitorFetch(searchUrl);

  List<dynamic> hits;
  if (data is List) {
    hits = data;
  } else {
    hits = (data['characters'] as List?) ?? (data['data'] as List?) ?? [];
  }

  return CatalogSearchResult(
    characters: hits.map(_normalizeHit).toList(),
    total: data is Map ? (data['total'] as int?) ?? 0 : hits.length,
  );
}

Future<DownloadedCharacter> janitorFetchCharacter(String id) async {
  final charUrl = '$_hampterUrl/$id';
  final data = await _janitorFetch(charUrl) as Map<String, dynamic>;
  return _convertToGlaze(data);
}

String? resolveJanitorAvatar(String? url) {
  if (url == null) return null;
  if (url.startsWith('http')) return url;
  if (url.startsWith('/')) return 'https://ella.janitorai.com$url?width=400';
  if (!url.contains('/')) return '$_imageBase$url?width=400';
  return 'https://ella.janitorai.com/$url?width=400';
}

List<String> _tagIdsToNames(List<dynamic> tagIds) {
  return tagIds
      .map((id) => _janitorTagMap[id])
      .where((name) => name != null)
      .cast<String>()
      .toList();
}

CatalogItem _normalizeHit(dynamic hit) {
  final m = hit as Map<String, dynamic>;
  List<String> standardTags;
  if (m['tags'] is List) {
    standardTags = (m['tags'] as List)
        .map((t) => t is String ? t : (t['name'] ?? t['slug'] ?? '') as String)
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.toLowerCase() != 'limitless')
        .toList();
  } else {
    standardTags = _tagIdsToNames(m['tagIds'] as List? ?? [])
        .where((t) => t.toLowerCase() != 'limitless')
        .toList();
  }

  final isNsfw = (m['isNsfw'] as bool?) ?? (m['is_nsfw'] as bool?) ?? false;
  final tags = [isNsfw ? 'NSFW' : 'SFW', ...standardTags];
  if (m['custom_tags'] is List) {
    tags.addAll((m['custom_tags'] as List).map((t) => '#$t'));
  }

  return CatalogItem(
    id: (m['id'] ?? '') as String,
    name: (m['name'] ?? m['bot_name'] ?? 'Unknown') as String,
    avatarUrl: resolveJanitorAvatar(
        (m['avatar'] ?? m['image']) as String?),
    description: (m['description'] ?? m['short_description'] ?? '') as String,
    tags: tags.toSet().toList(),
    tokens: (m['totalToken'] ?? m['total_tokens'] ?? 0) as int,
    chatCount: (m['stats']?['chat'] ?? m['public_chat_count'] ?? 0) as int,
    messageCount:
        (m['stats']?['message'] ?? m['public_message_count'] ?? 0) as int,
    creator: (m['creatorUsername'] ?? m['creator'] ?? '') as String,
    creatorId: (m['creator_id'] ?? m['creatorId'] ?? '') as String?,
    nsfw: isNsfw,
    slug: (m['slug'] ?? m['id'] ?? '') as String?,
    source: 'janitor',
  );
}

DownloadedCharacter _convertToGlaze(Map<String, dynamic> m) {
  List<String> standardTags;
  if (m['tags'] is List) {
    standardTags = (m['tags'] as List)
        .map((t) => t is String ? t : (t['name'] ?? t['slug'] ?? '') as String)
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.toLowerCase() != 'limitless')
        .toList();
  } else {
    standardTags = _tagIdsToNames(m['tagIds'] as List? ?? [])
        .where((t) => t.toLowerCase() != 'limitless')
        .toList();
  }

  final isNsfw = (m['is_nsfw'] ?? m['isNsfw']) as bool? ?? false;
  final tags = [isNsfw ? 'NSFW' : 'SFW', ...standardTags];
  if (m['custom_tags'] is List) {
    tags.addAll((m['custom_tags'] as List).map((t) => '#$t'));
  }

  return DownloadedCharacter(
    charData: CharacterData(
      name: (m['name'] ?? m['chat_name'] ?? 'Unknown') as String,
      description: '',
      personality: (m['personality'] ?? m['description'] ?? '') as String,
      scenario: (m['scenario'] ?? '') as String,
      firstMes: (m['first_message'] ?? m['first_mes'] ?? '') as String,
      mesExample:
          (m['example_dialogs'] ?? m['mes_example'] ?? m['example_dialogs'] ?? '')
              as String,
      creatorNotes: (m['description'] ?? m['creator_notes'] ?? '') as String,
      systemPrompt: '',
      postHistoryInstructions: '',
      alternateGreetings: m['first_messages'] is List
          ? (m['first_messages'] as List).cast<String>()
          : <String>[],
      tags: tags.toSet().toList(),
      creator: (m['creator_name'] ?? m['creator'] ?? '') as String,
      creatorId: (m['creator_id'] ?? '') as String,
      characterBook: null,
    ),
    avatarUrl: resolveJanitorAvatar(
        (m['avatar'] ?? m['image']) as String?),
  );
}
