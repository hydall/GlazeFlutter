import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/api_config.dart';
import '../models/preset.dart';
import 'json_repair.dart';
import 'studio_block_router.dart';

/// Result of the build-time Beauty pre-pass.
class StudioBeautyExtractionResult {
  final Set<String> beautyBlockIds;
  final String syntheticContract;
  final bool fromLlm;

  const StudioBeautyExtractionResult({
    required this.beautyBlockIds,
    required this.syntheticContract,
    required this.fromLlm,
  });

  static const empty = StudioBeautyExtractionResult(
    beautyBlockIds: {},
    syntheticContract: '',
    fromLlm: false,
  );
}

/// Build-time pre-pass that extracts reusable HTML/CSS beauty settings before
/// the general Studio router sees the preset.
///
/// The extractor selects only blocks whose primary purpose is reusable visual
/// styling (palette, fonts, colors, typography). It must NOT select semantic
/// blocks that merely contain colors (Lumia/OOC, trackers, infoblocks, image
/// generation, concrete HTML widgets). For those, it may return reserved style
/// notes in [syntheticContract] while leaving the source block in normal routing.
class StudioBeautyExtractor {
  final RouterLlmCall _callLlm;

  StudioBeautyExtractor(this._callLlm);

  Future<StudioBeautyExtractionResult> extract({
    required List<PresetBlock> blocks,
    ApiConfig? apiConfig,
    CancelToken? cancelToken,
  }) async {
    if (blocks.isEmpty) return StudioBeautyExtractionResult.empty;
    final prompt = _buildPrompt(blocks);
    try {
      final raw = await _callLlm(
        prompt,
        apiConfig: apiConfig,
        cancelToken: cancelToken,
      );
      final text = (raw ?? '').trim();
      if (text.isEmpty) {
        _log('empty beauty extractor response; using normal router');
        return StudioBeautyExtractionResult.empty;
      }
      final parsed = _parse(text, blocks.map((b) => b.id).toSet());
      if (parsed.beautyBlockIds.isEmpty && parsed.syntheticContract.isEmpty) {
        _log('beauty extractor produced no usable output; using normal router');
        return StudioBeautyExtractionResult.empty;
      }
      _log(
        'beauty extractor selected ${parsed.beautyBlockIds.length}/${blocks.length} block(s)',
      );
      return parsed;
    } on TimeoutException {
      _log('beauty extractor timeout; using normal router');
      return StudioBeautyExtractionResult.empty;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      _log('beauty extractor error: $e; using normal router');
      return StudioBeautyExtractionResult.empty;
    } catch (e) {
      _log('beauty extractor unexpected error: $e; using normal router');
      return StudioBeautyExtractionResult.empty;
    }
  }

  @visibleForTesting
  String buildPromptForTest(List<PresetBlock> blocks) => _buildPrompt(blocks);

  @visibleForTesting
  StudioBeautyExtractionResult parseForTest(String text, Set<String> blockIds) {
    return _parse(text, blockIds);
  }

  String _buildPrompt(List<PresetBlock> blocks) {
    final blockLines = blocks
        .map((b) {
          final name = b.name.trim().isNotEmpty ? b.name.trim() : b.id;
          final preview = _preview(b.content);
          return 'id: ${b.id}\nname: $name\nrole: ${b.role}\ncontent: $preview';
        })
        .join('\n---\n');

    return '''You are a build-time Beauty Extractor for a Studio multi-agent roleplay pipeline. You are NOT roleplaying and you are NOT routing every block. Your only job is to identify reusable visual styling settings that should be owned by the Beauty Shard tracker.

SELECT a block as beauty ONLY when its primary purpose is reusable presentation state, such as:
- global HTML/CSS style defaults
- palette / color scheme
- background color, main text color, font family
- per-speaker dialogue colors or thought colors
- gradients, text shadows, glow/highlight/mark styles, typography defaults
- rules like "reuse colors for the same speaker" or "keep the same font/style"

DO NOT SELECT blocks whose primary purpose is semantic behavior or a concrete artifact, even if they contain colors:
- Lumia/OOC/meta-persona behavior, periodic OOC rules, wrappers like <lumiaooc>
- trackers, stats panels, relationship metrics, cycle/pregnancy, hidden ledgers
- infoblocks/general_stats/secondary_infoblock/topbar/infoboard
- image generation, [IMG:GEN], data-iig-instruction, comics/illustration/image prompts
- concrete HTML widgets/windows: phone screens, taxi-call menus, terminals, HUDs, scrolls, cards, maps, buttons, carousels, page flips, scene objects

Reserved-color rule:
- If a semantic block (for example Lumia/OOC) contains a reserved color, DO NOT select that block as beauty.
- Instead, copy only the reserved color into reserved_style_notes / normalized_style_contract.reserved so Beauty Shard knows not to reuse it for speakers.
- If unsure whether a color is global style or semantic widget/persona color, leave the block unselected and optionally add a conservative reserved note.

Output STRICT JSON only, no markdown fences, no prose, in this exact shape:
{
  "beauty_block_ids": ["<block id whose primary purpose is reusable style>"],
  "reserved_style_notes": [
    {"source_block_id":"<id>","key":"lumia_ooc","value":"#9370DB","note":"reserved for Lumia/OOC; do not assign to speakers"}
  ],
  "normalized_style_contract": {
    "palette":"dark|light|unknown",
    "background":"#hex or empty",
    "text":"#hex or empty",
    "font":"font-family or empty",
    "speaker_colors":"rule summary",
    "reserved":{"key":"value"}
  }
}

Preset blocks:
$blockLines''';
  }

  StudioBeautyExtractionResult _parse(String text, Set<String> validBlockIds) {
    final jsonText = extractJsonObject(text);
    if (jsonText == null) return StudioBeautyExtractionResult.empty;
    final Object? decoded;
    try {
      decoded = jsonDecode(repairJson(jsonText));
    } catch (_) {
      return StudioBeautyExtractionResult.empty;
    }
    if (decoded is! Map) return StudioBeautyExtractionResult.empty;

    final ids = <String>{};
    final rawIds = decoded['beauty_block_ids'];
    if (rawIds is List) {
      for (final item in rawIds) {
        final id = item?.toString();
        if (id != null && validBlockIds.contains(id)) ids.add(id);
      }
    }

    final contract = <String, dynamic>{};
    final normalized = decoded['normalized_style_contract'];
    if (normalized is Map) {
      contract['normalized_style_contract'] = normalized;
    }
    final reserved = decoded['reserved_style_notes'];
    if (reserved is List && reserved.isNotEmpty) {
      contract['reserved_style_notes'] = reserved;
    }

    final synthetic = contract.isEmpty
        ? ''
        : '[Beauty extractor normalized contract]\n${jsonEncode(contract)}';
    return StudioBeautyExtractionResult(
      beautyBlockIds: ids,
      syntheticContract: synthetic,
      fromLlm: true,
    );
  }

  String _preview(String content) {
    final collapsed = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 700) return collapsed;
    return '${collapsed.substring(0, 700)}…';
  }

  void _log(String message) {
    debugPrint('[StudioBeautyExtractor] $message');
  }
}
