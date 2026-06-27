import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';

import '../models/api_config.dart';
import '../models/preset.dart';
import '../models/studio_config.dart';
import '../utils/time_helpers.dart';
import 'reasoning_stripper.dart';
import 'studio_block_classifier.dart';
import 'studio_block_expander.dart';
import 'studio_block_router.dart';
import 'studio_build_llm_client.dart';
import 'studio_controller_ontology.dart';

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

  StudioDecompositionService(Ref ref)
      : _buildLlm = StudioBuildLlmClient(ref);

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

    final result = _normalizeStudioAgents(agents);
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
    final promptShard = await _synthesizePromptShard(
      spec: spec,
      blocks: blocks,
      apiConfig: apiConfig,
      builderPromptTemplate: builderPromptTemplate,
      routingMode: routingMode,
      cancelToken: cancelToken,
    );
    return _normalizeStudioAgent(
      agent.copyWith(
        name: spec.name,
        role: 'system',
        promptShard: promptShard,
        sourceBlockNames: _sourceBlockNames(blocks),
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
    final promptShard = await _synthesizePromptShard(
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
      sourceBlockNames: _sourceBlockNames(blocks),
      refreshPolicy: spec.refreshPolicy,
      invalidationSignals: spec.invalidationSignals,
      phase: spec.phase,
    );
  }

  Future<String> _synthesizePromptShard({
    required StudioControllerSpec spec,
    required List<PresetBlock> blocks,
    ApiConfig? apiConfig,
    String builderPromptTemplate = '',
    String routingMode = 'verbatim',
    CancelToken? cancelToken,
  }) async {
    if (blocks.isEmpty) return spec.fallbackPrompt;

    // Stage 3: verbatim routing — concatenate blocks directly, no LLM call.
    // The preset is the source of truth; the agent sees its assigned blocks
    // дословно. See docs/PLAN_AGENTIC_STUDIO.md §11.
    if (routingMode == 'verbatim') {
      return _synthesizeRoutedShard(spec: spec, blocks: blocks);
    }

    // Legacy: LLM-compiled shard (переваривание).
    final prompt = _buildControllerPrompt(
      spec: spec,
      blocks: blocks,
      builderPromptTemplate: builderPromptTemplate,
    );
    try {
      final raw = await _callLlm(
        prompt,
        apiConfig: apiConfig,
        cancelToken: cancelToken,
      );
      final text = raw?.trim() ?? '';
      final cleaned = _stripMarkdownFence(text);
      if (cleaned.isNotEmpty && !_isBuilderRefusal(cleaned)) return cleaned;
      if (cleaned.isNotEmpty) {
        _log('controller build refusal name="${spec.name}"; using fallback');
      }
    } on TimeoutException {
      _log('controller build timeout name="${spec.name}"; using fallback');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      _log('controller build error name="${spec.name}" error=$e');
    }
    return '${spec.fallbackPrompt}\n\nSource blocks: ${_sourceBlockNames(blocks)}';
  }

  /// Stage 3: Verbatim routing — produces the promptShard by concatenating
  /// assigned preset blocks дословно, without any LLM compilation.
  ///
  /// Each block is emitted with a header `[Block: <name>]` followed by its
  /// content. Blocks are in preset order (priority = position in preset, §12).
  /// A conflict-resolution footer is appended: "при конфликте следуй последнему
  /// блоку".
  ///
  /// This makes the preset the direct source of truth for the agent — no
  /// intermediary LLM distorts the user's instructions. See
  /// docs/PLAN_AGENTIC_STUDIO.md §11.
  String _synthesizeRoutedShard({
    required StudioControllerSpec spec,
    required List<PresetBlock> blocks,
  }) {
    final parts = <String>[];
    for (final block in blocks) {
      final name = block.name.isNotEmpty ? block.name : block.id;
      final content = block.content.trim();
      if (content.isEmpty) continue;
      parts.add('[Block: $name]\n$content');
    }
    if (parts.isEmpty) return spec.fallbackPrompt;

    final body = parts.join('\n\n---\n\n');
    // Conflict resolution footer (§12): when two blocks contradict, the one
    // later in the preset wins (higher priority = closer to the end).
    const conflictFooter =
        '\n\n---\n\n[Conflict resolution: if two blocks above contradict each '
        'other, follow the one that appears LAST.]';

    return '$body$conflictFooter';
  }

  String _buildControllerPrompt({
    required StudioControllerSpec spec,
    required List<PresetBlock> blocks,
    String builderPromptTemplate = '',
  }) {
    final custom = _isLegacyDecompositionTemplate(builderPromptTemplate)
        ? ''
        : builderPromptTemplate.trim();
    final blocksSummary = _blocksSummary(blocks);
    if (custom.isNotEmpty) {
      return '''$custom

Build only this Studio controller instruction:
Controller: ${spec.name}
Purpose: ${spec.purpose}
Output contract: ${spec.outputContract}

Assigned preset blocks:
$blocksSummary''';
    }
    return '''You are a build-time Studio compiler. You are not roleplaying and you are not preparing the next chat reply.

Build a reusable instruction prompt for one later Studio agent from the assigned roleplay preset blocks.

Create the build-time promptShard for ONE visible Studio agent/controller.
Controller: ${spec.name}
Purpose: ${spec.purpose}

Rules:
- Output only the final instruction text for this controller, no JSON and no markdown wrapper.
- This promptShard will be saved in the database and reused later; write stable operating instructions, not current-scene content.
- The later agent will prepare guidance for the roleplay game. It must not act as a character, narrator, player, or final responder unless this is the Main Responder controller.
- Preserve enforceable rules from assigned blocks, but compress duplicates.
- Do not include hidden chain-of-thought directives, <think> tags, or instructions to reveal reasoning.
- If assigned blocks contain Lumia/meta-weaver/OOC behavior, convert it to silent final-model policy or OOC interface rules; do not make this controller write Lumia scene prose.
- Intermediate controllers must produce operational briefs only, never in-scene prose or dialogue.
- ${spec.outputContract}

Assigned preset blocks:
$blocksSummary''';
  }

  bool _isLegacyDecompositionTemplate(String template) {
    final text = template.toLowerCase();
    return text.contains('respond with only a json array') ||
        text.contains('create 3-6 agents') ||
        text.contains(
          'decompose the following rp preset blocks into a multi-agent pipeline',
        );
  }

  String _blocksSummary(List<PresetBlock> blocks) {
    return blocks
        .asMap()
        .entries
        .map((entry) {
          final i = entry.key;
          final b = entry.value;
          final content = _truncate(b.content, _blockLimitFor(b));
          return 'Block $i: name="${b.name}" role="${b.role}" insertion="${b.insertionMode}"${b.depth != null ? ' depth=${b.depth}' : ''}\n$content';
        })
        .join('\n\n---\n\n');
  }

  String _stripMarkdownFence(String text) {
    final fenced = RegExp(
      r'^```(?:\w+)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(text.trim());
    return (fenced?.group(1) ?? text).trim();
  }

  bool _isBuilderRefusal(String text) {
    final lower = text.toLowerCase();
    return lower.startsWith("i can't build") ||
        lower.startsWith('i cannot build') ||
        lower.startsWith("i won't build") ||
        lower.startsWith('i will not build') ||
        lower.contains("i can't build this controller") ||
        lower.contains('i cannot build this controller');
  }

  int _blockLimitFor(PresetBlock block) {
    final bucket = _bucketForBlock(block);
    if (bucket == 'meta') return 6000;
    if (bucket == 'final') return 3500;
    return 2500;
  }

  String _truncate(String text, int limit) {
    if (text.length <= limit) return text;
    return '${text.substring(0, limit)}...';
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

  String _sourceBlockNames(List<PresetBlock> blocks) {
    final names = <String>[];
    for (final block in blocks) {
      final name = block.name.trim();
      if (name.isEmpty) continue;
      if (names.any((n) => n.toLowerCase() == name.toLowerCase())) continue;
      names.add(name);
    }
    return names.join(', ');
  }

  String buildDecompositionPrompt({
    required String blocksSummary,
    String builderPromptTemplate = '',
  }) {
    final template = builderPromptTemplate.trim().isNotEmpty
        ? builderPromptTemplate.trim()
        : defaultBuilderPromptTemplate;
    if (template.contains('{{blocksSummary}}')) {
      return template.replaceAll('{{blocksSummary}}', blocksSummary);
    }
    return '$template\n\nEnabled preset blocks:\n$blocksSummary';
  }

  static const defaultBuilderPromptTemplate =
      '''You are a build-time Studio compiler. You are not roleplaying and you are not writing the next chat reply.

Build ONE reusable Studio controller instruction from assigned roleplay preset blocks.

Output only the final promptShard text for the requested controller. Do not output JSON, markdown fences, explanations, or the RP reply.

Controller rules:
- The promptShard will be saved in the database and reused later; write stable operating instructions, not current-scene content.
- The later agent prepares guidance for the roleplay game. It must not act as a character, narrator, player, or final responder unless it is the final responder controller.
- Compress duplicate instructions into one clear operating contract.
- Preserve enforceable rules from the assigned blocks.
- Convert style, pacing, dialogue, world, agency, guard, or meta rules into instructions for the later chat-time controller.
- Intermediate controllers must produce operational briefs only, never in-scene prose or dialogue.
- Do not include hidden chain-of-thought directives, <think> tags, or instructions to reveal reasoning.
- If assigned blocks contain Lumia/meta-weaver/OOC behavior, preserve it as silent meta-policy/OOC interface rules. Do not make the controller write Lumia scene prose.
- The final responder controller is the only controller allowed to produce the final visible RP response at chat time.

Assigned preset blocks:
{{blocksSummary}}''';

  List<StudioAgent> _normalizeStudioAgents(List<StudioAgent> agents) {
    if (agents.isEmpty) return agents;
    final ordered = agents.toList()..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < ordered.length; i++)
        _normalizeStudioAgent(ordered[i], isFinal: i == ordered.length - 1),
    ];
  }

  StudioAgent _normalizeStudioAgent(
    StudioAgent agent, {
    required bool isFinal,
  }) {
    var prompt = _stripPromptLevelReasoning(agent.promptShard);
    prompt = isFinal
        ? _appendSentence(prompt, _finalResponderGuard)
        : _appendSentence(prompt, _intermediateBriefGuard);

    return agent.copyWith(
      promptShard: prompt,
      sourceBlockNames: _stripReasoningSourceNames(agent.sourceBlockNames),
    );
  }

  String _stripPromptLevelReasoning(String text) =>
      ReasoningStripper.stripPromptShardReasoning(text);

  String _stripReasoningSourceNames(String text) {
    return text
        .replaceAll(RegExp(r',?\s*Block \d+ \(CoT Gemini think template\)'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  String _appendSentence(String text, String sentence) {
    if (text.toLowerCase().contains(sentence.toLowerCase())) return text;
    if (text.trim().isEmpty) return sentence;
    return '${text.trim()} $sentence';
  }

  static const _intermediateBriefGuard =
      "When giving style guidance, you may include brief do/don't examples derived from the user's preset, but never draft or continue the current scene, never write in-scene dialogue/actions as if it were the final reply, and never output hidden reasoning.";

  static const _finalResponderGuard =
      'Do not output or request hidden reasoning blocks; generate only the final visible reply.';

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

