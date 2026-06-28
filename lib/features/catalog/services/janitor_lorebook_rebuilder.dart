import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/transport/chat_transport_request.dart';
import '../../../core/llm/transport/transport_factory.dart';
import '../../../core/models/lorebook.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/time_helpers.dart';
import '../../settings/api_list_provider.dart';

/// Rebuilds raw, concatenated closed-lorebook text into structured
/// [LorebookEntry]s using Glaze's **active LLM connection** — a Dart port of
/// the SillyTavern `janitor-lorebook` frontend extension's `buildWithActiveLLM`.
///
/// The capture step (see `JanitorWebViewProxy.captureGenerateAlpha`) yields the
/// concatenated bodies of the entries the platform injected; this asks the LLM
/// to split them back into discrete, keyed World Info entries.

const String _systemPrompt = '''You reconstruct a SillyTavern World Info (lorebook) from raw text.

You are given text extracted from an LLM chat prompt: one or more lorebook entries a
roleplay platform injected because their trigger keywords matched. The character card and
user persona have already been removed; what remains is lorebook entry bodies concatenated
together (often separated by blank lines). You may also be given the character card and a
catalog/world description as CONTEXT — use those ONLY to infer better keys, never output
them as entries.

Your job:
1. Split the text into discrete, self-contained World Info entries. Each coherent block
   about one topic (a person, place, faction, item, rule, lore fact) is one entry. Do NOT
   merge unrelated topics; do NOT split a single topic across entries.
2. For each entry write:
   - "content": the entry body, faithful to the source.
   - "key": array of primary trigger keywords/phrases (names, aliases, places, distinctive
     nouns), inferred from the content and the provided context.
   - "keysecondary": optional array of secondary keywords (else []).
   - "comment": a short title (the topic name).
   - "order": optional integer insertion order; default 100.
3. Output ONLY a JSON object:
   { "entries": [ { "comment": "...", "key": ["..."], "keysecondary": [], "content": "...", "order": 100 }, ... ] }
No markdown, no prose, no code fences — JSON only.''';

/// Thrown when no usable LLM connection is configured.
class NoActiveConnectionException implements Exception {
  @override
  String toString() =>
      'No active LLM connection. Configure one in Settings → API first.';
}

/// Assembles the exact chat messages sent to the build LLM: a `system` prompt
/// plus a single `user` message bundling every selected context block followed
/// by the raw lorebook text. Exposed so the UI can PREVIEW the prompt without
/// spending a call. Port of JAR `extract.js` `buildExtractionMessages`.
///
/// Every context string is used ONLY to help the model infer better trigger
/// keys — none of it is ever emitted as a lorebook entry.
List<Map<String, String>> buildLorebookMessages(
  String lorebookText, {
  String card = '',
  String catalog = '',
  String scenario = '',
  String greetings = '',
  String lorebookDescs = '',
  String extra = '',
}) {
  final userParts = <String>[];
  void add(String value, String intro) {
    if (value.trim().isNotEmpty) userParts.add('$intro\n\n${value.trim()}');
  }

  add(card,
      'CONTEXT — the character card these entries accompany. Use it ONLY to infer better trigger keys and resolve names/aliases. Do NOT output any of this card text as entries:');
  add(catalog,
      'CONTEXT — the public catalog description for this character as shown on the site (setting, place and faction names). Use it ONLY to infer better trigger keys. Do NOT output any of this as entries:');
  add(scenario,
      'CONTEXT — the scenario / setup for this roleplay. Use it ONLY to infer better trigger keys (names, places, situations). Do NOT output any of this as entries:');
  add(greetings,
      "CONTEXT — the character's opening message(s) / greeting(s). Use them ONLY to infer better trigger keys (names, places, items mentioned). Do NOT output any of this as entries:");
  add(lorebookDescs,
      'CONTEXT — the public descriptions of lorebooks attached to this character (titles and descriptions only — the lorebook contents themselves are NOT included here). Use them ONLY to infer better trigger keys. Do NOT output any of this as entries:');
  add(extra,
      'CONTEXT — additional notes provided by the user (names, aliases, setting details). Use it ONLY to infer better trigger keys. Do NOT output any of this as entries:');

  userParts.add('Raw lorebook text to convert into entries:\n\n$lorebookText');

  return [
    {'role': 'system', 'content': _systemPrompt},
    {'role': 'user', 'content': userParts.join('\n\n---\n\n')},
  ];
}

/// Strips markdown code fences and trims to the outermost JSON object/array.
/// Port of the extension's `stripFences`.
String _stripFences(String text) {
  var t = text.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false)
      .firstMatch(t);
  if (fence != null) t = fence[1]!.trim();
  final first = t.indexOf(RegExp(r'[\[{]'));
  final last = [t.lastIndexOf('}'), t.lastIndexOf(']')].reduce((a, b) => a > b ? a : b);
  if (first >= 0 && last > first) t = t.substring(first, last + 1);
  return t;
}

/// Coerces the parsed JSON into a list of raw entry maps. Port of `coerceEntries`.
List<dynamic> _coerceEntries(dynamic parsed) {
  if (parsed is List) return parsed;
  if (parsed is Map) {
    final entries = parsed['entries'];
    if (entries is List) return entries;
    if (entries is Map) return entries.values.toList();
    if (parsed['lorebook'] is List) return parsed['lorebook'] as List;
  }
  return const [];
}

List<String> _asKeys(dynamic v) {
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  if (v is String) {
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

LorebookEntry _buildEntry(Map<String, dynamic> raw, int index) {
  final keys = _asKeys(raw['key'] ?? raw['keys'] ?? raw['keywords']);
  final secondary =
      _asKeys(raw['keysecondary'] ?? raw['secondary_keys'] ?? raw['keySecondary']);
  final content = (raw['content'] ?? raw['text'] ?? '').toString().trim();
  final comment = (raw['comment'] ??
          raw['title'] ??
          raw['name'] ??
          raw['category'] ??
          'Entry $index')
      .toString()
      .trim();
  final order = (raw['order'] is num)
      ? (raw['order'] as num).toInt()
      : (raw['priority'] is num)
          ? (raw['priority'] as num).toInt()
          : (raw['insertion_order'] is num)
              ? (raw['insertion_order'] as num).toInt()
              : 100;
  return LorebookEntry(
    id: 'jle_${DateTime.now().millisecondsSinceEpoch}_$index',
    comment: comment,
    keys: keys,
    secondaryKeys: secondary,
    content: content,
    order: order,
    constant: raw['constant'] == true,
    position: 'matchGlobal',
  );
}

/// Builds a [Lorebook] from [lorebookText] using the active LLM. [card] and
/// [catalog] are optional context for key inference. [name] is the lorebook
/// title; [characterId], when given, scopes the book to that character.
///
/// Throws [NoActiveConnectionException] when no connection is configured, or
/// [Exception] when the LLM response can't be parsed into entries.
Future<Lorebook> rebuildLorebookWithActiveLlm(
  Ref ref, {
  required String lorebookText,
  required String name,
  String card = '',
  String catalog = '',
  String scenario = '',
  String greetings = '',
  String lorebookDescs = '',
  String extra = '',
  String? characterId,
}) async {
  await ref.read(apiListProvider.future);
  final config = ref.read(activeApiConfigProvider);
  if (config == null || config.endpoint.isEmpty || config.model.isEmpty) {
    throw NoActiveConnectionException();
  }

  final messages = buildLorebookMessages(
    lorebookText,
    card: card,
    catalog: catalog,
    scenario: scenario,
    greetings: greetings,
    lorebookDescs: lorebookDescs,
    extra: extra,
  );
  final completer = Completer<String>();
  final transport = pickChatTransport(config.protocol);

  unawaited(transport.stream(
    request: ChatTransportRequest(
      endpoint: config.endpoint,
      apiKey: config.apiKey,
      model: config.model,
      messages: messages,
      maxTokens: config.maxTokens > 0 ? config.maxTokens : 8192,
      temperature: 0.2,
      topP: 1.0,
      stream: false,
    ),
    cancelToken: CancelToken(),
    onComplete: (text, _, {rawResponseJson}) {
      if (!completer.isCompleted) completer.complete(text);
    },
    onError: (error) {
      if (!completer.isCompleted) completer.completeError(error);
    },
  ));

  final raw = await completer.future;

  dynamic parsed;
  try {
    parsed = jsonDecode(_stripFences(raw));
  } catch (_) {
    final preview = raw.length > 300 ? raw.substring(0, 300) : raw;
    throw Exception('LLM did not return valid JSON. First 300 chars:\n$preview');
  }

  final rawEntries = _coerceEntries(parsed);
  final entries = <LorebookEntry>[];
  for (var i = 0; i < rawEntries.length; i++) {
    final e = rawEntries[i];
    if (e is! Map) continue;
    final entry = _buildEntry(Map<String, dynamic>.from(e), i);
    if (entry.content.isEmpty) continue;
    entries.add(entry);
  }
  if (entries.isEmpty) {
    throw Exception('LLM produced no usable lorebook entries.');
  }

  debugPrint('[janitor-extractor] rebuilt ${entries.length} lorebook entries');

  return Lorebook(
    id: generateId(),
    name: name,
    enabled: true,
    activationScope: characterId != null ? 'character' : 'global',
    activationTargetId: characterId,
    entries: entries,
    updatedAt: currentTimestampSeconds(),
  );
}
