import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/db_provider.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import 'janitor_lorebook_rebuilder.dart';
import 'janitor_provider.dart';
import 'janitor_separate.dart';
import 'janitor_webview_proxy.dart';

/// Result of the capture+separate pass: the recovered character (with the
/// hidden card now in `description`), the isolated closed-lorebook text, and
/// the context used to rebuild it. No DB writes yet — the UI previews this,
/// then calls [JanitorExtractor.commit].
class ExtractionResult {
  final String characterId; // JanitorAI character UUID
  final String sourceUrl;
  final DownloadedCharacter character;
  final String lorebookText;
  final int entryBlockCount;
  final String cardContext;
  final String catalogContext;

  const ExtractionResult({
    required this.characterId,
    required this.sourceUrl,
    required this.character,
    required this.lorebookText,
    required this.entryBlockCount,
    required this.cardContext,
    required this.catalogContext,
  });

  bool get hasLorebook => lorebookText.trim().isNotEmpty;
}

/// Summary returned after persisting an [ExtractionResult] to the DB.
class CommitResult {
  final String glazeCharacterId;
  final String characterName;
  final int lorebookEntryCount;
  final String? lorebookError;
  const CommitResult({
    required this.glazeCharacterId,
    required this.characterName,
    required this.lorebookEntryCount,
    this.lorebookError,
  });
}

/// Orchestrates the JanitorAI "closed lorebook + hidden card" extraction —
/// the Dart port of the SillyTavern `janitor-lorebook` extension's pipeline,
/// built on Glaze's own webview proxy ([JanitorWebViewProxy]) and active LLM.
class JanitorExtractor {
  JanitorExtractor(this._ref);
  final Ref _ref;

  static final _uuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      caseSensitive: false);

  /// Phase 1: capture the assembled prompt for [url] and separate it into the
  /// recovered card + isolated lorebook text. Marks the catalog active so the
  /// proxy WebView stays up for the duration.
  Future<ExtractionResult> extract(
    String url, {
    void Function(String phase)? onPhase,
  }) async {
    final characterId = _parseCharacterId(url);
    final proxy = JanitorWebViewProxy.instance;
    proxy.setActive(true);
    try {
      // Catalog meta gives the public name/tags/scenario and first message we
      // use both as LLM context and as extra trigger text for keyword matches.
      onPhase?.call('fetching metadata');
      final meta = await _fetchMeta(characterId);
      final catalog = _buildCatalogContext(meta);
      final firstMessageMeta = (meta?['first_message'] ?? '').toString();

      final payload = await proxy.captureGenerateAlpha(
        characterId: characterId,
        triggerText: firstMessageMeta,
        onPhase: onPhase,
      );

      onPhase?.call('separating');
      final card = extractCard(payload);
      final sep = separate(payload, card);

      final name = extractCharName(payload).isNotEmpty
          ? extractCharName(payload)
          : (meta?['name'] ?? 'Unknown').toString();
      final scenario = extractScenario(payload).isNotEmpty
          ? extractScenario(payload)
          : (meta?['scenario'] ?? '').toString();
      final firstMes = extractFirstMessage(payload).isNotEmpty
          ? extractFirstMessage(payload)
          : firstMessageMeta;
      final example = extractExample(payload);
      final tags = (meta?['custom_tags'] is List)
          ? (meta!['custom_tags'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final avatar = resolveJanitorAvatar(meta?['avatar'] as String?);

      final downloaded = DownloadedCharacter(
        charData: CharacterData(
          name: name,
          description: card,
          scenario: scenario,
          firstMes: firstMes,
          mesExample: example,
          creatorNotes: _htmlToText((meta?['description'] ?? '').toString()),
          tags: tags,
          creator: (meta?['creator_name'] ?? meta?['creator'] ?? '').toString(),
          creatorId: (meta?['creator_id'] ?? '').toString(),
        ),
        avatarUrl: avatar,
      );

      return ExtractionResult(
        characterId: characterId,
        sourceUrl: url,
        character: downloaded,
        lorebookText: sep.lorebookText,
        entryBlockCount: sep.entries.length,
        cardContext: card,
        catalogContext: catalog,
      );
    } finally {
      proxy.setActive(false);
    }
  }

  /// Phase 2: import the recovered character into the Glaze DB, then (if there
  /// is lorebook text) rebuild it with the active LLM and persist it scoped to
  /// the new character. A lorebook failure does not discard the character — it
  /// is reported via [CommitResult.lorebookError].
  Future<CommitResult> commit(
    ExtractionResult result, {
    void Function(String phase)? onPhase,
  }) async {
    onPhase?.call('importing character');
    final glazeId = await _ref
        .read(catalogProvider.notifier)
        .importCharacter(result.character, sourceUrl: result.sourceUrl);

    if (!result.hasLorebook) {
      return CommitResult(
        glazeCharacterId: glazeId,
        characterName: result.character.charData.name,
        lorebookEntryCount: 0,
      );
    }

    try {
      onPhase?.call('rebuilding lorebook (LLM)');
      final lorebook = await rebuildLorebookWithActiveLlm(
        _ref,
        lorebookText: result.lorebookText,
        name: '${result.character.charData.name} — Closed Lorebook',
        card: result.cardContext,
        catalog: result.catalogContext,
        characterId: glazeId,
      );
      onPhase?.call('saving lorebook');
      await _ref.read(lorebookRepoProvider).put(lorebook);
      return CommitResult(
        glazeCharacterId: glazeId,
        characterName: result.character.charData.name,
        lorebookEntryCount: lorebook.entries.length,
      );
    } catch (e) {
      debugPrint('[janitor-extractor] lorebook rebuild failed: $e');
      return CommitResult(
        glazeCharacterId: glazeId,
        characterName: result.character.charData.name,
        lorebookEntryCount: 0,
        lorebookError: e.toString(),
      );
    }
  }

  String _parseCharacterId(String input) {
    final m = _uuid.firstMatch(input.trim());
    if (m == null) {
      throw Exception('No character id found in: $input');
    }
    return m[0]!;
  }

  Future<Map<String, dynamic>?> _fetchMeta(String characterId) async {
    try {
      final body = await JanitorWebViewProxy.instance
          .fetch('https://janitorai.com/hampter/characters/$characterId');
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } catch (e) {
      debugPrint('[janitor-extractor] meta fetch failed: $e');
      return null;
    }
  }

  /// Builds the catalog/world context block (port of `buildCatalogContext`).
  String _buildCatalogContext(Map<String, dynamic>? meta) {
    if (meta == null) return '';
    final parts = <String>[];
    final name = (meta['name'] ?? '').toString();
    if (name.isNotEmpty) parts.add('Name: $name');
    final tags = meta['custom_tags'];
    if (tags is List && tags.isNotEmpty) {
      parts.add('Tags: ${tags.join(', ')}');
    }
    final desc = _htmlToText((meta['description'] ?? '').toString());
    if (desc.isNotEmpty) parts.add('Catalog description:\n$desc');
    final scenario = _htmlToText((meta['scenario'] ?? '').toString());
    if (scenario.isNotEmpty) parts.add('Scenario:\n$scenario');
    final scripts = meta['scripts'];
    if (scripts is List) {
      final books = scripts
          .whereType<Map<String, dynamic>>()
          .where((s) => s['type'] == 'lorebook')
          .map((s) =>
              '- ${s['title'] ?? ''}${s['description'] != null ? ': ${s['description']}' : ''}')
          .toList();
      if (books.isNotEmpty) {
        parts.add(
            'Attached lorebooks (titles only — contents are hidden):\n${books.join('\n')}');
      }
    }
    return parts.join('\n\n');
  }

  /// Minimal HTML → text (port of `htmlToText`).
  String _htmlToText(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|li|h\d)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'&#39;|&apos;'), "'")
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }
}

/// Provider for the JanitorAI extractor service.
final janitorExtractorProvider = Provider<JanitorExtractor>(
  (ref) => JanitorExtractor(ref),
);
