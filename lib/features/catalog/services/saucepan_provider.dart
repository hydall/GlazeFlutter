import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_http.dart';
import '../catalog_models.dart';

const _base = 'https://saucepan.ai';

/// Image variants served from `saucepan.ai/cdn/{id}/{variant}`. `card` is the
/// small grid thumbnail; `highres` is the full-size detail image.
const _imageVariantCard = 'card';
const _imageVariantHighres = 'highres';

/// Persisted Bearer token key. Saucepan gates full card info + the definition
/// endpoint behind a login, just like JanitorAI.
const _tokenKey = 'gz_saucepan_token';

const _headers = {
  'Accept': 'application/json',
  'Origin': 'https://saucepan.ai',
  'Referer': 'https://saucepan.ai/',
};

/// Maps our internal sort keys to Saucepan's `order_by` field (all descending).
const _orderByMap = <String, String>{
  'popular': 'popularity',
  'newest': 'posted_at',
  'updated': 'updated_at',
  'chats': 'chat_count',
};

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

Future<String?> saucepanGetToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_tokenKey);
}

Future<void> saucepanSetToken(String? token) async {
  final prefs = await SharedPreferences.getInstance();
  if (token == null || token.isEmpty) {
    await prefs.remove(_tokenKey);
  } else {
    await prefs.setString(_tokenKey, token);
  }
}

Future<void> saucepanLogout() => saucepanSetToken(null);

/// Signs in with a handle + password and persists the returned Bearer token.
Future<String> saucepanLogin(String handle, String password) async {
  final data = await catalogPost(
    '$_base/api/v1/auth/sign_in_password',
    {'handle': handle.trim(), 'password': password},
    {..._headers, 'Referer': '$_base/sign-in'},
  );
  final token = (data['token'] ??
      data['access_token'] ??
      data['session_token'] ??
      data['sessionToken']) as String?;
  if (token == null || token.isEmpty) {
    throw Exception('Saucepan: login succeeded but no token was returned');
  }
  await saucepanSetToken(token);
  return token;
}

/// Base headers plus the Bearer token when the user is logged in.
Future<Map<String, String>> _authHeaders() async {
  final token = await saucepanGetToken();
  return {
    ..._headers,
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
}

// ---------------------------------------------------------------------------
// Fragment deobfuscation
// ---------------------------------------------------------------------------

const _fnvOffset = 0x811C9DC5; // 2166136261
const _fnvPrime = 0x01000193; // 16777619
const _mask32 = 0xFFFFFFFF;

int _rotl(int v, int bits) => ((v << bits) | (v >>> (32 - bits))) & _mask32;

/// FNV-1a over the UTF-8 text, seeded from the block `mask` and the fragment's
/// derived key (`key XOR mask`). A fragment is real iff this equals its `proof`.
int _fragmentHash(int mask, int derivedKey, String text) {
  var h = (_fnvOffset ^ _rotl(mask, 7) ^ _rotl(derivedKey, 13)) & _mask32;
  for (final b in utf8.encode(text)) {
    h ^= b;
    h = (h * _fnvPrime) & _mask32;
  }
  return h & _mask32;
}

/// Reassembles a scrambled Saucepan fragment block (used for the description,
/// starting-scenario greetings, and each definition section).
///
/// Saucepan mixes the real text fragments with filler decoys. Each fragment's
/// position is `key XOR mask`; only fragments whose `proof` validates against
/// [_fragmentHash] are kept (this drops the decoys, including the ones that
/// collide on a real position), then they're ordered by position and joined.
String assembleFragments(Map<String, dynamic>? block) {
  if (block == null) return '';
  final mask = ((block['mask'] as int?) ?? 0) & _mask32;
  final frags = (block['fragments'] as List?)?.whereType<Map<String, dynamic>>();
  if (frags == null) return '';

  final kept = <MapEntry<int, String>>[];
  for (final f in frags) {
    final key = f['key'] as int?;
    final text = f['text'] as String?;
    final proof = f['proof'] as int?;
    if (key == null || text == null || proof == null) continue;
    final derivedKey = (key ^ mask) & _mask32;
    if (_fragmentHash(mask, derivedKey, text) == (proof & _mask32)) {
      kept.add(MapEntry(derivedKey, text));
    }
  }
  kept.sort((a, b) => a.key.compareTo(b.key));
  return kept.map((e) => e.value).join();
}

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

String? _resolveImageUrl(String? imageId, {String variant = _imageVariantCard}) {
  if (imageId == null || imageId.isEmpty) return null;
  return '$_base/cdn/$imageId/$variant';
}

String? _imageIdOf(Map<String, dynamic> c) {
  final img = c['image'];
  if (img is Map) return img['id'] as String?;
  return null;
}

String _prettifyTag(String tag) => tag.replaceAll('_', ' ').trim();

CatalogItem _normalizeListItem(Map<String, dynamic> c) {
  final rawTags = (c['tags'] as List?)?.whereType<String>().toList() ?? [];
  final tags = rawTags.map(_prettifyTag).where((t) => t.isNotEmpty).toList();
  final isNsfw = (c['sus'] as bool?) ?? false;

  return CatalogItem(
    id: (c['id'] ?? '') as String,
    name: (c['display_name'] ?? c['name'] ?? 'Unknown') as String,
    avatarUrl: _resolveImageUrl(_imageIdOf(c)),
    description: (c['short_description'] ?? '') as String,
    tags: [isNsfw ? 'NSFW' : 'SFW', ...tags],
    tokens: (c['card_token_count'] as int?) ?? 0,
    chatCount: (c['chat_count'] as int?) ?? 0,
    messageCount: (c['interaction_count'] as int?) ?? 0,
    creator: (c['author_handle'] ?? '') as String,
    creatorId: (c['author_id'] ?? '') as String?,
    nsfw: isNsfw,
    source: 'saucepan',
  );
}

Future<CatalogSearchResult> saucepanSearch({
  String query = '',
  int page = 1,
  int limit = 24,
  CatalogFilters filters = const CatalogFilters(),
}) async {
  final offset = (page - 1) * limit;
  final trimmed = query.trim();

  final body = <String, dynamic>{
    'text_search': trimmed.isEmpty ? null : trimmed,
    'tags': filters.tagNames,
    'excluded_tags': filters.excludeTagNames,
    'fandom_tags': <String>[],
    'excluded_fandom_tags': <String>[],
    'match_all_fandom_tags': false,
    'limit': limit,
    'offset': offset,
    // `sus` gates NSFW cards; `extra_spicy` (very_sus / NSFL) is left
    // unconstrained unless the user explicitly opts into NSFL.
    'sus': filters.nsfw,
    'extra_spicy': filters.nsfl ? true : null,
    'order_by': _orderByMap[filters.sort] ?? 'popularity',
    'asc': false,
    'posted_at_from': null,
    'posted_at_to': null,
    'match_all_tags': true,
    'hide_hidden_content': false,
  };

  final data = await catalogPost('$_base/api/v1/search', body, await _authHeaders());
  final list = ((data['companions'] as List?) ?? []).cast<Map<String, dynamic>>();
  final total = (data['total_count'] as int?) ?? list.length;

  return CatalogSearchResult(
    characters: list.map(_normalizeListItem).toList(),
    total: total,
    hasMore: offset + list.length < total,
  );
}

/// Fetches the definition endpoint and returns a `title -> decoded text` map
/// (e.g. `Companion Core`, `Example Dialogue`, `Advanced Prompt`,
/// `Response Formatting Instructions`). Requires a logged-in token.
Future<Map<String, String>> saucepanGetDefinition(String id) async {
  final data = await catalogGet(
    '$_base/api/v1/companion/definition?companion_id=$id',
    await _authHeaders(),
  );
  final sections = (data['sections'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      const <Map<String, dynamic>>[];
  final out = <String, String>{};
  for (final s in sections) {
    final title = s['title'] as String?;
    final content = s['content'];
    if (title == null || title.isEmpty || content is! Map<String, dynamic>) {
      continue;
    }
    out[title] = assembleFragments(content);
  }
  return out;
}

/// Fetches a companion card + its open definition and maps them to a Glaze
/// character (mirrors the JAR extractor).
///
/// - `description` ← the `Companion Core` section (falls back to the public
///   full description when the definition isn't available).
/// - `firstMes` / `alternateGreetings` ← the starting-scenario greetings.
/// - `mesExample` ← the `Example Dialogue` section.
/// - `creatorNotes` ← short description + `Advanced Prompt` + `Response
///   Formatting Instructions`.
///
/// Full card info and the definition require a login; without a token the card
/// still returns public metadata + the public description, but greetings and
/// definition sections will be empty.
Future<DownloadedCharacter> saucepanGetCharacter(String id) async {
  final cardData = await catalogGet('$_base/api/v2/companions/$id', await _authHeaders());
  final c = (cardData['companion'] ?? cardData) as Map<String, dynamic>;

  Map<String, String> sections = const {};
  try {
    sections = await saucepanGetDefinition(id);
  } catch (_) {
    // Closed definition, no token, or endpoint error — fall back to public info.
  }

  var description = sections['Companion Core'] ?? '';
  if (description.isEmpty) {
    description = assembleFragments(
      c['full_description_fragments'] as Map<String, dynamic>?,
    );
  }

  final greetings = <String>[];
  final scenarios = (c['starting_scenarios_fragments'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      const <Map<String, dynamic>>[];
  for (final sc in scenarios) {
    final text = assembleFragments(sc['message'] as Map<String, dynamic>?);
    if (text.trim().isNotEmpty) greetings.add(text);
  }

  final notes = <String>[];
  final shortDesc = (c['short_description'] as String?)?.trim() ?? '';
  if (shortDesc.isNotEmpty) notes.add(shortDesc);
  final advanced = sections['Advanced Prompt'];
  if (advanced != null && advanced.trim().isNotEmpty) {
    notes.add('--- Advanced Prompt ---\n$advanced');
  }
  final formatting = sections['Response Formatting Instructions'];
  if (formatting != null && formatting.trim().isNotEmpty) {
    notes.add('--- Response Formatting ---\n$formatting');
  }

  final rawTags = (c['tags'] as List?)?.whereType<String>().toList() ?? [];

  return DownloadedCharacter(
    charData: CharacterData(
      name: (c['display_name'] ?? c['name'] ?? 'Unknown') as String,
      description: description,
      mesExample: sections['Example Dialogue'] ?? '',
      firstMes: greetings.isNotEmpty ? greetings.first : '',
      alternateGreetings: greetings.length > 1 ? greetings.sublist(1) : const [],
      creatorNotes: notes.join('\n\n'),
      tags: rawTags.map(_prettifyTag).where((t) => t.isNotEmpty).toList(),
      creator: (c['author_handle'] ?? '') as String,
      creatorId: (c['author_id'] ?? '') as String,
    ),
    avatarUrl: _resolveImageUrl(_imageIdOf(c), variant: _imageVariantHighres),
  );
}
