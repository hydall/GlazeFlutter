import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/api_config.dart';
import '../models/preset.dart';
import 'json_repair.dart';

/// Signature of the LLM call the router delegates to. The decomposition
/// service supplies its existing build-model call (`_callLlm`) so the router
/// stays decoupled from API-config resolution (CODE_STYLE: one class = one job).
typedef RouterLlmCall =
    Future<String?> Function(
      String prompt, {
      ApiConfig? apiConfig,
      CancelToken? cancelToken,
    });

/// One routable agent bucket the router can assign blocks to.
///
/// Decouples the router from the tracker specs. Callers map their tracker
/// configurations to these descriptors before calling.
class RouterBucket {
  final String id;
  final String name;
  final String purpose;

  const RouterBucket({
    required this.id,
    required this.name,
    required this.purpose,
  });
}

/// Reserved bucket id meaning "this block is a chain-of-thought / reasoning
/// template — drop it, do not route it to any agent". The multi-agent pipeline
/// already externalizes reasoning, so a per-turn `<think>` directive is
/// redundant. See docs/PLAN_AGENTIC_STUDIO.md §11.
const String kRouterDropBucketId = 'drop';

/// Result of a routing pass: a map of `blockId -> bucketId`.
///
/// A bucket id of [kRouterDropBucketId] means the LLM judged the block to be a
/// reasoning/CoT template that should be dropped (not assigned to any agent).
///
/// [fromLlm] records whether the LLM classifier produced the map (true) or
/// the caller should fall back to its deterministic keyword router (false).
class BlockRoutingMap {
  final Map<String, String> blockToBucket;
  final bool fromLlm;

  const BlockRoutingMap({required this.blockToBucket, required this.fromLlm});

  static const BlockRoutingMap empty = BlockRoutingMap(
    blockToBucket: {},
    fromLlm: false,
  );

  String? bucketFor(String blockId) => blockToBucket[blockId];

  /// True if the LLM explicitly marked [blockId] as a reasoning block to drop.
  bool isDropped(String blockId) => blockToBucket[blockId] == kRouterDropBucketId;
}

/// LLM-powered classifier that routes preset blocks to Studio agent buckets.
///
/// Implements docs/PLAN_AGENTIC_STUDIO.md §11: the classifier reads the preset
/// blocks once at build-time and decides `block -> agent(s)`. It does NOT
/// rewrite block content (that is verbatim synthesis, a separate step). The
/// returned map is saved by the caller into the StudioConfig so chat-time does
/// not re-run any LLM.
///
/// On any failure (timeout, refusal, malformed JSON) the router returns a
/// non-LLM [BlockRoutingMap] so the caller can fall back to its deterministic
/// keyword bucketing — Studio always builds.
class StudioBlockRouter {
  final RouterLlmCall _callLlm;

  StudioBlockRouter(this._callLlm);

  /// Classify [blocks] into one of [buckets]. Returns a `blockId -> bucketId`
  /// map. Only ids present in [buckets] are accepted; unknown/missing ids are
  /// dropped (the caller then falls back per-block).
  Future<BlockRoutingMap> route({
    required List<PresetBlock> blocks,
    required List<RouterBucket> buckets,
    ApiConfig? apiConfig,
    CancelToken? cancelToken,
  }) async {
    if (blocks.isEmpty || buckets.isEmpty) return BlockRoutingMap.empty;

    final prompt = _buildPrompt(blocks: blocks, buckets: buckets);
    try {
      final raw = await _callLlm(
        prompt,
        apiConfig: apiConfig,
        cancelToken: cancelToken,
      );
      final text = (raw ?? '').trim();
      if (text.isEmpty) {
        _log('empty classifier response; falling back to keywords');
        return BlockRoutingMap.empty;
      }
      final validBucketIds = buckets.map((b) => b.id).toSet()
        ..add(kRouterDropBucketId);
      final validBlockIds = blocks.map((b) => b.id).toSet();
      final parsed = _parse(text, validBucketIds, validBlockIds);
      if (parsed.isEmpty) {
        _log('classifier produced no usable assignments; using keywords');
        return BlockRoutingMap.empty;
      }
      _log('classified ${parsed.length}/${blocks.length} blocks via LLM');
      return BlockRoutingMap(blockToBucket: parsed, fromLlm: true);
    } on TimeoutException {
      _log('classifier timeout; falling back to keywords');
      return BlockRoutingMap.empty;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      _log('classifier error: $e; falling back to keywords');
      return BlockRoutingMap.empty;
    } catch (e) {
      _log('classifier unexpected error: $e; falling back to keywords');
      return BlockRoutingMap.empty;
    }
  }

  /// Builds the classifier prompt. Public for testing.
  @visibleForTesting
  String buildPromptForTest({
    required List<PresetBlock> blocks,
    required List<RouterBucket> buckets,
  }) => _buildPrompt(blocks: blocks, buckets: buckets);

  /// Parses classifier JSON output. Public for testing.
  @visibleForTesting
  Map<String, String> parseForTest(
    String text,
    Set<String> validBucketIds,
    Set<String> validBlockIds,
  ) => _parse(text, validBucketIds, validBlockIds);

  String _buildPrompt({
    required List<PresetBlock> blocks,
    required List<RouterBucket> buckets,
  }) {
    final agentLines = buckets
        .map((b) => '- ${b.id}: ${b.name} — ${b.purpose}')
        .join('\n');

    final blockLines = blocks.map((b) {
      final name = b.name.trim().isNotEmpty ? b.name.trim() : b.id;
      final preview = _preview(b.content);
      return 'id: ${b.id}\nname: $name\nrole: ${b.role}\ncontent: $preview';
    }).join('\n---\n');

    return '''You are a build-time Studio router. You are NOT roleplaying and you are NOT writing any reply. Your only job is to assign each roleplay preset block to the single most appropriate agent bucket.

Available agent buckets:
$agentLines

There is also ONE special bucket:
- $kRouterDropBucketId: DROP. Use ONLY for a block that is itself a chain-of-thought / reasoning / thinking TEMPLATE — i.e. the block's primary purpose is to make the model produce hidden step-by-step reasoning (e.g. a "CoT" block whose body is mostly a "<think> ... </think>" scaffold of internal planning steps). This multi-agent pipeline already does the reasoning, so such a block is redundant and must be dropped.

Routing rules:
- Assign every block to exactly ONE bucket id (one of the agent buckets above, or "$kRouterDropBucketId").
- Choose the bucket whose purpose best matches what the block actually does, judging by its name AND content (not just keywords).
- Use "$kRouterDropBucketId" ONLY for genuine reasoning/CoT templates as defined above. A block that merely MENTIONS reasoning or a <think> tag is NOT a reasoning template:
  * A language/format block (e.g. "everything after </think> must be written in Russian") is about output language — route it to the final responder bucket, do NOT drop it.
  * A meta/persona/lore block that references a <think> block while describing OOC behavior is NOT a reasoning template — route it to the matching agent bucket, do NOT drop it.
- A block that defines the final output format, language, or the visible reply itself belongs to the final responder bucket.
- If genuinely unsure, pick the final responder bucket. NEVER drop a block when unsure. Never invent a bucket.

Output STRICT JSON only, no markdown fences, no prose, in this exact shape:
{"assignments": [{"block": "<block id>", "bucket": "<bucket id>"}, ...]}

Preset blocks to route:
$blockLines''';
  }

  String _preview(String content) {
    final collapsed = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 400) return collapsed;
    return '${collapsed.substring(0, 400)}…';
  }

  /// Parse the classifier JSON. Tolerates surrounding text/markdown fences by
  /// extracting the first JSON object. Drops assignments referencing unknown
  /// block or bucket ids.
  Map<String, String> _parse(
    String text,
    Set<String> validBucketIds,
    Set<String> validBlockIds,
  ) {
    final jsonText = extractJsonObject(text);
    if (jsonText == null) return const {};
    final Object? decoded;
    try {
      decoded = jsonDecode(repairJson(jsonText));
    } catch (_) {
      return const {};
    }
    if (decoded is! Map) return const {};
    final list = decoded['assignments'];
    if (list is! List) return const {};

    final result = <String, String>{};
    for (final item in list) {
      if (item is! Map) continue;
      final block = item['block']?.toString();
      final bucket = item['bucket']?.toString();
      if (block == null || bucket == null) continue;
      if (!validBlockIds.contains(block)) continue;
      if (!validBucketIds.contains(bucket)) continue;
      result[block] = bucket;
    }
    return result;
  }

  void _log(String message) {
    debugPrint('[StudioRouter] $message');
  }
}
