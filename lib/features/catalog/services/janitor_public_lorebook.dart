import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/lorebook.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/time_helpers.dart';
import 'janitor_webview_proxy.dart';

/// Public lorebooks attached to a JanitorAI character.
///
/// Dart port of JAR's `publiclore.js` + `worldinfo.js`. A character can have
/// **public** lorebooks listed in its `scripts` metadata (`type:"lorebook"`).
/// Unlike a *closed* lorebook — which only surfaces as triggered text inside a
/// `generateAlpha` response and must be rebuilt by an LLM (see
/// [JanitorExtractor]) — a public lorebook can be downloaded whole, in its
/// original structured form, from:
///
///   GET https://janitorai.com/hampter/script/{scriptId}
///
/// whose JSON has a `script` field (a JSON **string**) holding the entries in
/// JanitorAI's native shape. That array maps onto a Glaze [Lorebook] (or a
/// SillyTavern World Info `.json` for export).

/// A lorebook script reference ({id, title, isPublic}) attached to a character.
class JanitorScriptRef {
  final String id;
  final String title;
  final bool isPublic;
  const JanitorScriptRef({
    required this.id,
    required this.title,
    required this.isPublic,
  });
}

/// One fetched public lorebook. [accessible] is false when the script could not
/// be downloaded or yielded no entries (the closed-lorebook LLM path is then the
/// only way to recover it).
class PublicLorebook {
  final String id;
  final String title;
  final String description;
  final bool accessible;
  final int entryCount;

  /// The raw JanitorAI entries (native shape) — kept so the caller can build a
  /// Glaze [Lorebook] ([toLorebook]) or a SillyTavern `.json` ([toTavernJson]).
  final List<dynamic> rawEntries;
  final String? error;

  const PublicLorebook({
    required this.id,
    required this.title,
    this.description = '',
    this.accessible = false,
    this.entryCount = 0,
    this.rawEntries = const [],
    this.error,
  });

  /// Convert to a Glaze [Lorebook]. When [characterId] is given the book is
  /// scoped to that character, otherwise global.
  Lorebook toLorebook({String? characterId}) => convertJanitorScript(
        rawEntries,
        name: title.isNotEmpty ? title : 'Janitor Lorebook',
        characterId: characterId,
      );

  /// Convert to a SillyTavern World Info `{entries:{...}}` map for `.json`
  /// export.
  Map<String, dynamic> toTavernJson() =>
      janitorScriptToTavernJson(rawEntries, name: title);
}

const _origin = 'https://janitorai.com';

/// Lorebook script references attached to [meta] (`/hampter/characters/{id}`).
List<JanitorScriptRef> lorebookScriptRefs(Map<String, dynamic>? meta) {
  final scripts = meta?['scripts'];
  if (scripts is! List) return const [];
  return scripts
      .whereType<Map<String, dynamic>>()
      .where((s) => s['type'] == 'lorebook' && s['id'] != null)
      .map((s) => JanitorScriptRef(
            id: s['id'].toString(),
            title: (s['title'] ?? '').toString(),
            isPublic: s['is_public'] != false,
          ))
      .toList();
}

/// Parse the entries array out of a `/hampter/script/<id>` record (the `script`
/// field is a JSON **string** holding an array).
List<dynamic> parseScriptEntries(dynamic rec) {
  if (rec is! Map) return const [];
  final raw = rec['script'];
  if (raw is List) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final a = jsonDecode(raw);
      return a is List ? a : const [];
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

/// Fetch a single public lorebook by script id. Never throws — on any failure
/// it returns a record with `accessible:false` so the caller can flag it as
/// "private / download-blocked" (those go through the closed-lorebook LLM path).
Future<PublicLorebook> fetchPublicLorebook(
  String scriptId, {
  String title = '',
}) async {
  try {
    final body = await JanitorWebViewProxy.instance
        .fetch('$_origin/hampter/script/$scriptId');
    final rec = jsonDecode(body);
    if (rec is! Map) {
      return PublicLorebook(
          id: scriptId, title: title, error: 'response was not JSON');
    }
    final entries = parseScriptEntries(rec);
    final usable = entries
        .whereType<Map<String, dynamic>>()
        .where((e) => (e['content'] ?? '').toString().trim().isNotEmpty)
        .length;
    return PublicLorebook(
      id: (rec['id'] ?? scriptId).toString(),
      title: (rec['title'] ?? title).toString(),
      description: (rec['description'] ?? '').toString(),
      // Downloadable only if it actually yielded entries with content.
      accessible: usable > 0,
      entryCount: usable,
      rawEntries: entries,
    );
  } catch (e) {
    debugPrint('[janitor-public-lore] fetch $scriptId failed: $e');
    return PublicLorebook(id: scriptId, title: title, error: e.toString());
  }
}

/// Fetch every public lorebook attached to a character (from its metadata).
Future<List<PublicLorebook>> fetchPublicLorebooks(
  Map<String, dynamic>? meta,
) async {
  final refs = lorebookScriptRefs(meta);
  final out = <PublicLorebook>[];
  for (final ref in refs) {
    out.add(await fetchPublicLorebook(ref.id, title: ref.title));
  }
  return out;
}

/// The verbatim entry contents of accessible public lorebooks — subtracted from
/// the closed-lorebook extraction so public content never leaks into it (see
/// JanitorSeparate / JAR `separate()`).
List<String> publicEntryContents(List<PublicLorebook> books) {
  final out = <String>[];
  for (final b in books) {
    if (!b.accessible) continue;
    for (final e in b.rawEntries) {
      if (e is Map) {
        final c = (e['content'] ?? '').toString();
        if (c.trim().isNotEmpty) out.add(c);
      }
    }
  }
  return out;
}

// ─── Conversion ──────────────────────────────────────────────────────────────

List<String> _asKeys(dynamic v) {
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  if (v is String) {
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

int _asOrder(Map<String, dynamic> e) {
  for (final k in ['order', 'insertion_order', 'priority']) {
    final v = e[k];
    if (v is num) return v.toInt();
  }
  return 100;
}

/// JanitorAI numeric/string position → Glaze position token. Mirrors the
/// mapping in `character_book_converter.dart`.
String _mapPosition(dynamic pos) {
  if (pos is String) {
    switch (pos) {
      case 'before_char':
      case 'before_character':
      case 'worldInfoBefore':
        return 'worldInfoBefore';
      case 'at_depth':
      case 'lorebooksMacro':
        return 'lorebooksMacro';
      default:
        return 'worldInfoAfter';
    }
  }
  if (pos is num) {
    switch (pos.toInt()) {
      case 0:
      case 2:
      case 4:
        return 'worldInfoBefore';
      default:
        return 'worldInfoAfter';
    }
  }
  return 'worldInfoAfter';
}

/// Map JanitorAI's native entry shape → Glaze [LorebookEntry]. Tolerant of the
/// loose field names JanitorAI / SillyTavern use (`key`/`keys`/`keysRaw`, …).
LorebookEntry _toEntry(Map<String, dynamic> e, int index) {
  final keys = _asKeys(e['key'] ?? e['keys'] ?? e['keysRaw'] ?? e['keywords']);
  final secondary = _asKeys(
      e['keysecondary'] ?? e['secondary_keys'] ?? e['keySecondary']);
  final content = (e['content'] ?? e['text'] ?? '').toString();
  final comment =
      (e['comment'] ?? e['title'] ?? e['name'] ?? e['category'] ?? 'Entry $index')
          .toString()
          .trim();
  final rawProb = e['probability'];
  final probability = rawProb is num
      ? (rawProb <= 1 ? (rawProb * 100).round() : rawProb.round()).clamp(0, 100)
      : 100;
  final selectiveLogic =
      e['selectiveLogic'] is num ? (e['selectiveLogic'] as num).toInt() : 5;
  return LorebookEntry(
    id: 'jpl_${index}_${generateId()}',
    comment: comment,
    keys: keys,
    secondaryKeys: secondary,
    content: content,
    enabled: e['enabled'] != false && e['disable'] != true,
    constant: e['constant'] == true,
    position: _mapPosition(e['position']),
    order: _asOrder(e),
    selectiveLogic: selectiveLogic,
    probability: probability,
    caseSensitive: e['case_sensitive'] is bool ? e['case_sensitive'] as bool : null,
    matchWholeWords:
        e['match_whole_words'] is bool ? e['match_whole_words'] as bool : null,
    preventRecursion: e['prevent_recursion'] == true,
  );
}

/// Build a Glaze [Lorebook] from JanitorAI script [entries].
Lorebook convertJanitorScript(
  List<dynamic> entries, {
  required String name,
  String? characterId,
}) {
  final out = <LorebookEntry>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (e is! Map) continue;
    final entry = _toEntry(Map<String, dynamic>.from(e), i);
    if (entry.content.trim().isEmpty) continue;
    out.add(entry);
  }
  return Lorebook(
    id: generateId(),
    name: name,
    enabled: true,
    activationScope: characterId != null ? 'character' : 'global',
    activationTargetId: characterId,
    entries: out,
    updatedAt: currentTimestampSeconds(),
  );
}

// ─── SillyTavern World Info export ───────────────────────────────────────────

int _tavernPosition(dynamic pos) {
  if (pos is num) return pos.toInt();
  switch (pos) {
    case 'before_char':
    case 'before_character':
    case 'worldInfoBefore':
      return 0;
    case 'at_depth':
    case 'lorebooksMacro':
      return 4;
    default:
      return 1;
  }
}

Map<String, dynamic> _tavernEntry(Map<String, dynamic> e, int uid) {
  final key = _asKeys(e['key'] ?? e['keys'] ?? e['keysRaw'] ?? e['keywords']);
  final keysecondary = _asKeys(
      e['keysecondary'] ?? e['secondary_keys'] ?? e['keySecondary']);
  final content = (e['content'] ?? e['text'] ?? '').toString().trim();
  final comment =
      (e['comment'] ?? e['title'] ?? e['name'] ?? e['category'] ?? 'Entry $uid')
          .toString()
          .trim();
  final constant = e['constant'] == true;
  final rawProb = e['probability'];
  final probability = rawProb is num
      ? (rawProb <= 1 ? (rawProb * 100).round() : rawProb.round())
      : 100;
  return {
    'uid': uid,
    'key': key,
    'keysecondary': keysecondary,
    'comment': comment,
    'content': content,
    'constant': constant,
    'selective': !constant,
    'order': _asOrder(e),
    'position': _tavernPosition(e['position']),
    'disable': e['enabled'] == false || e['disable'] == true,
    'displayIndex': uid,
    'addMemo': true,
    'group': '',
    'groupOverride': false,
    'groupWeight': 100,
    'sticky': 0,
    'cooldown': 0,
    'delay': 0,
    'probability': probability,
    'depth': 4,
    'useProbability': true,
    'role': null,
    'vectorized': false,
    'excludeRecursion': false,
    'preventRecursion': e['prevent_recursion'] == true,
    'delayUntilRecursion': false,
    'scanDepth': null,
    'caseSensitive':
        e['case_sensitive'] is bool ? e['case_sensitive'] : null,
    'matchWholeWords':
        e['match_whole_words'] is bool ? e['match_whole_words'] : null,
    'useGroupScoring': null,
    'automationId': '',
    'selectiveLogic':
        e['selectiveLogic'] is num ? (e['selectiveLogic'] as num).toInt() : 0,
    'ignoreBudget': false,
    'characterFilter': {'isExclude': false, 'names': <String>[], 'tags': <String>[]},
  };
}

/// Emit a SillyTavern World Info book (`{name, entries:{...}}`) for `.json`
/// export. Port of JAR `worldinfo.buildWorldInfo` / `buildEntry`.
Map<String, dynamic> janitorScriptToTavernJson(
  List<dynamic> entries, {
  String name = '',
}) {
  final out = <String, dynamic>{};
  var uid = 0;
  for (final e in entries) {
    if (e is! Map) continue;
    final entry = _tavernEntry(Map<String, dynamic>.from(e), uid);
    if ((entry['content'] as String).isEmpty) continue;
    out['$uid'] = entry;
    uid += 1;
  }
  return {
    if (name.isNotEmpty) 'name': name,
    'entries': out,
  };
}

int _glazeTavernPosition(String pos) {
  switch (pos) {
    case 'worldInfoBefore':
      return 0;
    case 'lorebooksMacro':
      return 4;
    default:
      return 1;
  }
}

/// Emit a SillyTavern World Info book from a Glaze [Lorebook] (e.g. a closed
/// lorebook freshly rebuilt by the LLM) for `.json` export.
Map<String, dynamic> glazeLorebookToTavernJson(Lorebook book) {
  final out = <String, dynamic>{};
  var uid = 0;
  for (final e in book.entries) {
    if (e.content.trim().isEmpty) continue;
    out['$uid'] = {
      'uid': uid,
      'key': e.keys,
      'keysecondary': e.secondaryKeys,
      'comment': e.comment,
      'content': e.content,
      'constant': e.constant,
      'selective': !e.constant,
      'order': e.order,
      'position': _glazeTavernPosition(e.position),
      'disable': !e.enabled,
      'displayIndex': uid,
      'addMemo': true,
      'group': e.group,
      'groupOverride': false,
      'groupWeight': 100,
      'sticky': e.sticky,
      'cooldown': e.cooldown,
      'delay': e.delay,
      'probability': e.probability,
      'depth': 4,
      'useProbability': true,
      'role': null,
      'vectorized': false,
      'excludeRecursion': false,
      'preventRecursion': e.preventRecursion,
      'delayUntilRecursion': false,
      'scanDepth': e.scanDepth,
      'caseSensitive': e.caseSensitive,
      'matchWholeWords': e.matchWholeWords,
      'useGroupScoring': null,
      'automationId': '',
      'selectiveLogic': e.selectiveLogic,
      'ignoreBudget': false,
      'characterFilter': {
        'isExclude': false,
        'names': <String>[],
        'tags': <String>[],
      },
    };
    uid += 1;
  }
  return {'name': book.name, 'entries': out};
}
