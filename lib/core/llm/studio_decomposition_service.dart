import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';

import '../models/api_config.dart';
import '../models/preset.dart';
import '../models/studio_config.dart';
import '../utils/time_helpers.dart';
import 'studio_block_classifier.dart';
import 'studio_block_expander.dart';
import 'studio_beauty_extractor.dart';
import 'studio_block_router.dart';
import 'studio_build_llm_client.dart';
import 'studio_controller_ontology.dart';
import 'studio_shard_synthesizer.dart';

/// LLM-powered preset decomposition service for Studio Mode.
///
/// Takes enabled preset blocks, assigns them to stable hard-controller slots,
/// then asks an LLM to synthesize each visible controller instruction. Each
/// agent gets:
/// - A stable controller name (e.g. "Continuity Controller")
/// - A role
/// - A prompt shard (instructions accumulated from assigned preset blocks)
/// - A pipeline order
/// - The source block names it was derived from
///
/// The decomposition is cached per-session and only re-run when the preset
/// changes (detected via sourcePresetHash).
class StudioDecompositionService {
  final StudioBuildLlmClient _buildLlm;
  final StudioShardSynthesizer _synthesizer;
  final StudioBeautyExtractor _beautyExtractor;

  factory StudioDecompositionService(Ref ref) {
    final buildLlm = StudioBuildLlmClient(ref);
    return StudioDecompositionService._(
      buildLlm,
      StudioShardSynthesizer(buildLlm, _logStatic),
      StudioBeautyExtractor(buildLlm.call),
    );
  }

  StudioDecompositionService._(
    this._buildLlm,
    this._synthesizer,
    this._beautyExtractor,
  );

  static void _logStatic(String message) {
    debugPrint('[StudioBuild] $message');
  }

  /// Decompose a preset into build-time Studio controller agents.
  /// Returns a list of [StudioAgent]s ordered by pipeline execution order.
  Future<List<StudioAgent>> decompose({
    required Preset preset,
    required String sessionId,
    ApiConfig? apiConfig,
    String builderPromptTemplate = '',
    String routingMode = 'verbatim',
    CancelToken? cancelToken,
  }) async {
    final allEnabled = preset.blocks.where((b) => b.enabled).toList();
    if (allEnabled.isEmpty) return const [];

    // Expand setvar/getvar macros in block order BEFORE routing. This
    // resolves the variable pipeline (setvar→store→getvar) so rule values
    // reach their destination blocks. setvar-only blocks (e.g. LENGTH) have
    // their rule values surfaced as content. The CoT dispatcher — which
    // previously read all variables via getvar — can then be safely dropped
    // without losing rules. See docs/PLAN_AGENTIC_STUDIO.md §11.
    final expandedBlocks = expandBlocksForRouting(allEnabled);

    // CoT / reasoning / thinking blocks are NOT routed to any agent: the
    // multi-agent pipeline IS the externalized chain-of-thought, so a per-turn
    // ilda directive inside an agent is redundant and conflicts with the
    // "produce a brief, not prose / no hidden reasoning" contract. Drop them
    // after macro expansion. See docs/PLAN_AGENTIC_STUDIO.md §11.
    final reasoningBlocks = expandedBlocks.where(isReasoningBlock).toList();
    // Assistant-role blocks (prefill) are NOT routed to any agent in Studio
    // mode. In SillyTavern these act as assistant prefill (the model continues
    // from this text), but in the Studio pipeline they would land mid-conversation
    // as orphan assistant turns, breaking the conversation flow. Assistant
    // prefill is a transport-layer concern (API config prefix field), not a
    // preset-block concern. Drop them from routing.
    final droppedRoleBlocks = expandedBlocks
        .where((b) => b.role == 'assistant')
        .toList();
    final enabledBlocks = expandedBlocks
        .where((b) => !isReasoningBlock(b) && b.role != 'assistant')
        .toList();
    if (reasoningBlocks.isNotEmpty) {
      _log(
        'dropped ${reasoningBlocks.length} reasoning/CoT block(s) from routing: '
        '${reasoningBlocks.map((b) => b.name.isNotEmpty ? b.name : b.id).join(', ')}',
      );
    }
    if (droppedRoleBlocks.isNotEmpty) {
      _log(
        'dropped ${droppedRoleBlocks.length} assistant-role/prefill block(s) '
        'from routing (Studio does not support prefill in shards): '
        '${droppedRoleBlocks.map((b) => b.name.isNotEmpty ? b.name : b.id).join(', ')}',
      );
    }

    // Length-hint extraction: when a dropped CoT/reasoning block contains a
    // length instruction (word count / word budget / paragraph target) and NO
    // enabled non-reasoning block already carries one, extract the length line
    // from the dropped block and add it as a standalone block so the final
    // agent still sees the length guidance. Without this, presets whose ONLY
    // length rule lives inside the CoT template (e.g. Fawnie's "fawn's cot"
    // block: "Word budget is {{getvar::length}}") would lose all length
    // guidance when the CoT block is dropped.
    final lengthHint = _extractLengthHintFromReasoning(
      reasoningBlocks: reasoningBlocks,
      enabledBlocks: enabledBlocks,
    );
    final enabledBlocksWithLength = lengthHint != null
        ? [...enabledBlocks, lengthHint]
        : enabledBlocks;
    if (lengthHint != null) {
      _log(
        'extracted length hint from dropped CoT block: '
        '"${lengthHint.content.substring(0, lengthHint.content.length.clamp(0, 120))}"',
      );
    }
    if (enabledBlocksWithLength.isEmpty) return const [];

    final totalChars = enabledBlocksWithLength.fold<int>(
      0,
      (sum, b) => sum + b.content.length,
    );
    _log(
      'build start session=$sessionId preset="${preset.name}" '
      'blocks=${enabledBlocksWithLength.length} chars=$totalChars '
      'model=${apiConfig?.model ?? '<active>'}',
    );

    final beautyExtraction = await _beautyExtractor.extract(
      blocks: enabledBlocksWithLength,
      apiConfig: apiConfig,
      cancelToken: cancelToken,
    );
    final beautyBlockIds = beautyExtraction.beautyBlockIds;
    final beautyBlocks = enabledBlocksWithLength
        .where((b) => beautyBlockIds.contains(b.id))
        .toList();
    final routableBlocks = enabledBlocksWithLength
        .where((b) => !beautyBlockIds.contains(b.id))
        .toList();
    if (beautyBlocks.isNotEmpty ||
        beautyExtraction.syntheticContract.isNotEmpty) {
      _log(
        'beauty pre-pass: selected ${beautyBlocks.length} reusable style block(s); '
        'routing remaining ${routableBlocks.length}',
      );
    }

    // §11: LLM router classifies block -> agent ONCE at build-time. Falls back
    // to deterministic keyword bucketing if the LLM is unavailable/refuses, so
    // Studio always builds. Skipped only when there is no build model.
    final routingMapResult = await _routeBlocks(
      blocks: routableBlocks,
      apiConfig: apiConfig,
      cancelToken: cancelToken,
    );
    _log(
      'routing: ${routingMapResult.fromLlm ? 'LLM' : 'keyword-fallback'} '
      '(${routingMapResult.blockToBucket.length}/${routableBlocks.length} mapped)',
    );

    final now = currentTimestampSeconds();
    final assignments = _assignBlocks(routableBlocks, routingMapResult);
    if (beautyBlocks.isNotEmpty ||
        beautyExtraction.syntheticContract.isNotEmpty) {
      assignments['beauty'] = [
        if (beautyExtraction.syntheticContract.isNotEmpty)
          PresetBlock(
            id: '_beauty_extractor_contract',
            name: 'Beauty extractor normalized contract',
            role: 'system',
            content: beautyExtraction.syntheticContract,
          ),
        ...beautyBlocks,
        ...?assignments['beauty'],
      ];
    }
    // Meta-weaver detection (plan §Part A/B): if any block routed to the
    // `meta` bucket is a meta-weaver/OOC block, the Meta-Weaver gets a counting
    // duty suffix and the Main Responder gets a compact meta output contract.
    final lumiaActive = _bucketHasLumia(assignments['meta'] ?? const []);
    final agents = <StudioAgent>[];
    for (final spec in StudioControllerOntology.specs) {
      final blocks = assignments[spec.id] ?? const <PresetBlock>[];
      agents.add(
        await _buildAgentForSpec(
          spec: spec,
          blocks: blocks,
          sessionId: sessionId,
          index: agents.length,
          now: now,
          apiConfig: apiConfig,
          builderPromptTemplate: builderPromptTemplate,
          routingMode: routingMode,
          cancelToken: cancelToken,
          lumiaActive: lumiaActive,
        ),
      );
    }

    final result = _synthesizer.normalizeStudioAgents(agents);
    _log('build complete session=$sessionId agents=${result.length}');
    return result;
  }

  /// Collects "broadcast" blocks: cross-cutting rules that must reach more than
  /// one stage. Output language and prose-quality guards (anti-loop / anti-echo
  /// / anti-cliché / anti-slop / banlists) are not properties of a single agent
  /// — they govern the final visible reply AND the POST-cleaner rewrite. They
  /// are still routed to their primary agent (e.g. the guard agent) via
  /// [_assignBlocks]; this method additionally surfaces their verbatim content
  /// so the caller can (a) duplicate them into the Main Responder and (b)
  /// persist them for the POST-cleaner. See docs/PLAN_AGENTIC_STUDIO.md §11.
  ///
  /// Returns blocks in preset order (priority = position, §12). Reasoning/CoT
  /// blocks are excluded.
  List<PresetBlock> collectBroadcastBlocks(Preset preset) {
    final allEnabled = preset.blocks.where((b) => b.enabled).toList();
    final expanded = expandBlocksForRouting(allEnabled);
    return expanded
        .where(
          (b) =>
              !isReasoningBlock(b) &&
              b.role != 'assistant' &&
              isBroadcastBlock(b),
        )
        .toList();
  }

  /// Expands `{{setvar}}`/`{{getvar}}`/`{{trim}}` macros across all blocks in
  /// preset order, threading the variable store forward (matching
  /// `prompt_builder.dart` block-order semantics).
  ///
  /// This resolves the setvar→getvar pipeline at BUILD time so that rule
  /// values reach their destination blocks even when the CoT dispatcher
  /// (which previously read all variables via getvar) is dropped as a
  /// reasoning block. Other macros (`{{char}}`, `{{user}}`, …) are left
  /// untouched for chat-time expansion.
  ///
  /// **setvar-only blocks** (pure `{{setvar::…}}` — content is empty after
  /// expansion but variables were set) are surfaced: their rule-like variable
  /// values (`*_rules`, `*_target`, or multi-line/long text) become the
  /// block's content, so the rules reach an agent instead of vanishing.
  /// Technical flags (`*_mode`, `*_min`, `*_max` — short single-word/number
  /// values) are discarded.
  ///
  /// Returns a new list of [PresetBlock]s with expanded content, in the same
  /// order. Blocks whose expanded content is still empty (no setvar, no
  /// getvar, no text) are dropped.
  /// Static delegator — see [StudioBlockExpander.expandBlocksForRouting].
  /// Kept on this class because tests reference
  /// `StudioDecompositionService.expandBlocksForRouting`.
  @visibleForTesting
  static List<PresetBlock> expandBlocksForRouting(List<PresetBlock> blocks) =>
      StudioBlockExpander.expandBlocksForRouting(blocks);

  /// Regenerate the build-time prompt shard for one visible Studio agent.
  /// This rebuilds Studio setup, not chat-time agent output.
  Future<StudioAgent> regenerateAgentInstruction({
    required Preset preset,
    required StudioAgent agent,
    ApiConfig? apiConfig,
    String builderPromptTemplate = '',
    String routingMode = 'verbatim',
    CancelToken? cancelToken,
  }) async {
    final allEnabled = preset.blocks.where((b) => b.enabled).toList();
    final expandedBlocks = expandBlocksForRouting(
      allEnabled,
    ).where((b) => !isReasoningBlock(b)).toList();
    final spec = StudioControllerOntology.specForAgent(agent);
    // Single-agent regen reuses deterministic bucketing (no LLM router call);
    // the build-time LLM map only matters for a full decompose().
    final assignments = _assignBlocks(expandedBlocks, BlockRoutingMap.empty);
    final blocks = assignments[spec.id] ?? const <PresetBlock>[];
    final promptShard = await _synthesizer.synthesizePromptShard(
      spec: spec,
      blocks: blocks,
      apiConfig: apiConfig,
      builderPromptTemplate: builderPromptTemplate,
      routingMode: routingMode,
      cancelToken: cancelToken,
    );
    return _synthesizer.normalizeStudioAgent(
      agent.copyWith(
        name: spec.name,
        role: 'system',
        promptShard: promptShard,
        sourceBlockNames: _synthesizer.sourceBlockNames(blocks),
        refreshPolicy: spec.refreshPolicy,
        invalidationSignals: spec.invalidationSignals,
        contextSize: spec.contextSize > 0
            ? spec.contextSize
            : agent.contextSize,
      ),
      isFinal: spec.isFinal,
    );
  }

  Future<StudioAgent> _buildAgentForSpec({
    required StudioControllerSpec spec,
    required List<PresetBlock> blocks,
    required String sessionId,
    required int index,
    required int now,
    ApiConfig? apiConfig,
    String builderPromptTemplate = '',
    String routingMode = 'verbatim',
    CancelToken? cancelToken,
    bool lumiaActive = false,
  }) async {
    final promptShard = await _synthesizer.synthesizePromptShard(
      spec: spec,
      blocks: blocks,
      apiConfig: apiConfig,
      builderPromptTemplate: builderPromptTemplate,
      routingMode: routingMode,
      cancelToken: cancelToken,
      lumiaActive: lumiaActive,
    );
    return StudioAgent(
      id: 'agent_${sessionId}_${spec.id}_$now',
      name: spec.name,
      role: 'system',
      promptShard: promptShard,
      order: index,
      // Meta-Weaver: auto-disable when the preset has no meta-weaver/OOC
      // block. Without a meta block the agent would run every turn (refresh
      // policy 'turn') on a bare fallback prompt and burn an LLM call to
      // output "inert" — pointless latency. The user can still re-enable it
      // manually in the Studio UI if they add a meta block later. See
      // docs/plans/PLAN_STUDIO_PROMPT_FILTERING.md §Part A.
      enabled: !(spec.id == 'meta' && !lumiaActive),
      modelSource: 'current',
      temperature: spec.temperature,
      maxTokens: spec.maxTokens,
      timeoutMs: spec.timeoutMs,
      sourceBlockNames: _synthesizer.sourceBlockNames(blocks),
      refreshPolicy: spec.refreshPolicy,
      invalidationSignals: spec.invalidationSignals,
      phase: spec.phase,
      contextSize: spec.contextSize > 0 ? spec.contextSize : 5,
    );
  }

  /// Assigns blocks to controller buckets. Prefers the LLM [routing] map when
  /// it provides a valid bucket for a block; otherwise falls back per-block to
  /// the deterministic keyword bucketing. This keeps Studio building even if
  /// the classifier was unavailable or only partially mapped the blocks.
  ///
  /// A block the LLM marked [kRouterDropBucketId] (a genuine reasoning/CoT
  /// template) is excluded entirely. As a safety net the deterministic
  /// [isReasoningBlock] check (run earlier in [decompose]) already removed
  /// obvious CoT blocks; this honors the LLM's per-block drop decision too.
  ///
  /// "Broadcast" blocks (output language + prose-quality guards) are placed in
  /// their primary bucket AND duplicated into the final responder bucket, since
  /// those rules must also govern the final visible reply. They are not
  /// duplicated if they were already routed to `final`.
  Map<String, List<PresetBlock>> _assignBlocks(
    List<PresetBlock> blocks,
    BlockRoutingMap routing,
  ) {
    final validIds = StudioControllerOntology.specs.map((s) => s.id).toSet();
    final map = {
      for (final spec in StudioControllerOntology.specs)
        spec.id: <PresetBlock>[],
    };
    for (final block in blocks) {
      // Honor an explicit LLM drop decision (reasoning/CoT template).
      if (routing.isDropped(block.id)) continue;

      final routed = routing.bucketFor(block.id);
      final bucket = (routed != null && validIds.contains(routed))
          ? routed
          : _bucketForBlock(block);
      map[bucket]!.add(block);

      // Broadcast: also ensure cross-cutting rules reach the final responder.
      if (bucket != 'final' && isBroadcastBlock(block)) {
        map['final']!.add(block);
      }
    }
    return map;
  }

  /// Static delegator — see [StudioBlockClassifier.isBroadcastBlock]. Kept on
  /// this class because tests reference `StudioDecompositionService.isBroadcastBlock`.
  @visibleForTesting
  static bool isBroadcastBlock(PresetBlock block) =>
      StudioBlockClassifier.isBroadcastBlock(block);

  /// Runs the LLM block router over [blocks]. Maps the private controller specs
  /// to public [RouterBucket]s and delegates to [StudioBlockRouter]. Returns an
  /// empty (non-LLM) map on any failure so callers fall back to keywords.
  Future<BlockRoutingMap> _routeBlocks({
    required List<PresetBlock> blocks,
    ApiConfig? apiConfig,
    CancelToken? cancelToken,
  }) async {
    final buckets = [
      for (final spec in StudioControllerOntology.specs)
        RouterBucket(id: spec.id, name: spec.name, purpose: spec.purpose),
    ];
    final router = StudioBlockRouter(_callLlm);
    return router.route(
      blocks: blocks,
      buckets: buckets,
      apiConfig: apiConfig,
      cancelToken: cancelToken,
    );
  }

  /// Static delegator — see [StudioBlockClassifier.isReasoningBlock]. Kept on
  /// this class because tests reference `StudioDecompositionService.isReasoningBlock`.
  @visibleForTesting
  static bool isReasoningBlock(PresetBlock block) =>
      StudioBlockClassifier.isReasoningBlock(block);

  String _bucketForBlock(PresetBlock block) =>
      StudioBlockClassifier.bucketForBlock(block);

  /// True if any block in [blocks] is a meta-weaver/OOC block (by name, id, or
  /// content keyword). Used to decide whether to append the Meta-Weaver
  /// counting duty suffix and the Main Responder compact meta contract.
  /// Mirrors the `meta` bucket keyword in `StudioBlockClassifier.bucketForBlock`.
  /// Detection is generalized: any block mentioning meta-weaver / OOC / weaver
  /// / a specific meta-persona name (e.g. "lumia", "ghost in the machine") counts.
  bool _bucketHasLumia(List<PresetBlock> blocks) {
    for (final block in blocks) {
      final text = '${block.name}\n${block.id}\n${block.content}'.toLowerCase();
      if (text.contains('lumia') ||
          text.contains('ghost in the machine') ||
          text.contains('meta-weaver') ||
          text.contains('meta weaver') ||
          text.contains('ooc interface') ||
          text.contains('ooc policy') ||
          text.contains('weaver')) {
        return true;
      }
    }
    return false;
  }

  /// Compute a hash of enabled blocks to detect preset changes.
  static String computePresetHash(List<PresetBlock> blocks) {
    final input = blocks
        .map((b) {
          return jsonEncode({
            'id': b.id,
            'name': b.name,
            'enabled': b.enabled,
            'role': b.role,
            'insertionMode': b.insertionMode,
            'depth': b.depth,
            'content': b.content,
          });
        })
        .join('\n');
    return sha1.convert(utf8.encode(input)).toString();
  }

  Future<String?> _callLlm(
    String prompt, {
    ApiConfig? apiConfig,
    CancelToken? cancelToken,
  }) => _buildLlm.call(prompt, apiConfig: apiConfig, cancelToken: cancelToken);

  void _log(String message) {
    debugPrint('[StudioBuild] $message');
  }

  /// Regex matching a length instruction line: word budget/count/length,
  /// paragraph target, "N-M words", "minimum N words", "maximum N words",
  /// "Response length: N-M words", "Always write N-M words".
  static final _lengthInstructionRegex = RegExp(
    r'^(?:.*(?:word\s+(?:budget|count|length|target|limit)|response\s+length|always\s+write|length\s*:|paragraph\s+(?:budget|count|target|limit))\s*:?\s*.*)$|'
    r'.{0,40}(?:\d+-\d+\s*words?|\d+\s*words?\s*(?:min|max|minimum|maximum|target|hard|soft)).{0,40}',
    caseSensitive: false,
    multiLine: true,
    unicode: true,
  );

  /// Extract a length hint from dropped CoT/reasoning blocks when no enabled
  /// block already carries one. Returns a new [PresetBlock] with the extracted
  /// length line as content, or null when:
  /// - no reasoning block contains a length instruction, or
  /// - an enabled non-reasoning block already contains one (no duplication).
  PresetBlock? _extractLengthHintFromReasoning({
    required List<PresetBlock> reasoningBlocks,
    required List<PresetBlock> enabledBlocks,
  }) {
    // Check if any enabled block already has a length instruction.
    final enabledHasLength = enabledBlocks.any(
      (b) => _lengthInstructionRegex.hasMatch(b.content),
    );
    if (enabledHasLength) return null;

    // Scan reasoning blocks for length instruction lines.
    for (final block in reasoningBlocks) {
      final lines = block.content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (_lengthInstructionRegex.hasMatch(trimmed)) {
          return PresetBlock(
            id: '_extracted_length_hint',
            name: 'Length hint (extracted from CoT)',
            role: 'system',
            content: trimmed,
          );
        }
      }
    }
    return null;
  }
}
