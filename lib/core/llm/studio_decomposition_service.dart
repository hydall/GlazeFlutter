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

  factory StudioDecompositionService(Ref ref) {
    final buildLlm = StudioBuildLlmClient(ref);
    return StudioDecompositionService._(
      buildLlm,
      StudioShardSynthesizer(buildLlm, _logStatic),
    );
  }

  StudioDecompositionService._(this._buildLlm, this._synthesizer);

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
    // <think> directive inside an agent is redundant and conflicts with the
    // "produce a brief, not prose / no hidden reasoning" contract. Drop them
    // after macro expansion. See docs/PLAN_AGENTIC_STUDIO.md §11.
    final reasoningBlocks = expandedBlocks.where(isReasoningBlock).toList();
    final enabledBlocks = expandedBlocks
        .where((b) => !isReasoningBlock(b))
        .toList();
    if (reasoningBlocks.isNotEmpty) {
      _log(
        'dropped ${reasoningBlocks.length} reasoning/CoT block(s) from routing: '
        '${reasoningBlocks.map((b) => b.name.isNotEmpty ? b.name : b.id).join(', ')}',
      );
    }
    if (enabledBlocks.isEmpty) return const [];

    final totalChars = enabledBlocks.fold<int>(
      0,
      (sum, b) => sum + b.content.length,
    );
    _log(
      'build start session=$sessionId preset="${preset.name}" '
      'blocks=${enabledBlocks.length} chars=$totalChars '
      'model=${apiConfig?.model ?? '<active>'}',
    );

    // §11: LLM router classifies block -> agent ONCE at build-time. Falls back
    // to deterministic keyword bucketing if the LLM is unavailable/refuses, so
    // Studio always builds. Skipped only when there is no build model.
    final routingMapResult = await _routeBlocks(
      blocks: enabledBlocks,
      apiConfig: apiConfig,
      cancelToken: cancelToken,
    );
    _log(
      'routing: ${routingMapResult.fromLlm ? 'LLM' : 'keyword-fallback'} '
      '(${routingMapResult.blockToBucket.length}/${enabledBlocks.length} mapped)',
    );

    final now = currentTimestampSeconds();
    final assignments = _assignBlocks(enabledBlocks, routingMapResult);
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
        .where((b) => !isReasoningBlock(b) && isBroadcastBlock(b))
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
    final allEnabled = preset.blocks
        .where((b) => b.enabled)
        .toList();
    final expandedBlocks = expandBlocksForRouting(allEnabled)
        .where((b) => !isReasoningBlock(b))
        .toList();
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
  }) async {
    final promptShard = await _synthesizer.synthesizePromptShard(
      spec: spec,
      blocks: blocks,
      apiConfig: apiConfig,
      builderPromptTemplate: builderPromptTemplate,
      routingMode: routingMode,
      cancelToken: cancelToken,
    );
    return StudioAgent(
      id: 'agent_${sessionId}_${spec.id}_$now',
      name: spec.name,
      role: 'system',
      promptShard: promptShard,
      order: index,
      enabled: true,
      modelSource: 'current',
      temperature: spec.temperature,
      maxTokens: spec.maxTokens,
      timeoutMs: spec.timeoutMs,
      sourceBlockNames: _synthesizer.sourceBlockNames(blocks),
      refreshPolicy: spec.refreshPolicy,
      invalidationSignals: spec.invalidationSignals,
      phase: spec.phase,
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
    final map = {for (final spec in StudioControllerOntology.specs) spec.id: <PresetBlock>[]};
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
  }) =>
      _buildLlm.call(prompt, apiConfig: apiConfig, cancelToken: cancelToken);

  void _log(String message) {
    debugPrint('[StudioBuild] $message');
  }
}

