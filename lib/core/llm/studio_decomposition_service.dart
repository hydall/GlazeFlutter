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

class _ControllerSpec {
  final String id;
  final String name;
  final String purpose;
  final String outputContract;
  final String fallbackPrompt;
  final String refreshPolicy;
  final List<String> invalidationSignals;
  final double temperature;
  final int maxTokens;
  final int timeoutMs;
  final bool isFinal;
  final String phase;

  const _ControllerSpec({
    required this.id,
    required this.name,
    required this.purpose,
    required this.outputContract,
    required this.fallbackPrompt,
    required this.refreshPolicy,
    required this.invalidationSignals,
    required this.temperature,
    required this.maxTokens,
    required this.timeoutMs,
    this.isFinal = false,
    // Feature 6 — which phase this controller's agent runs in. Default
    // `pre_generation` (runs before the final generator, produces a brief).
    // `post_processing` = runs after the generator, receives its response.
    // No built-in post-processing specs exist yet (the user's preset blocks
    // route to pre-gen trackers; post-processing is a future expansion), but
    // the field is here so the decomposition engine CAN produce
    // post-processing agents when such specs are added without touching the
    // spec class again. See docs/PLAN_AGENTIC_STUDIO.md §5.7.1 + Feature 6.
    // ignore: unused_element_parameter
    this.phase = 'pre_generation',
  });
}

const _controllerSpecs = <_ControllerSpec>[
  _ControllerSpec(
    id: 'continuity',
    name: 'Continuity Controller',
    purpose:
        'Track source-of-truth facts, recent chat state, unresolved threads, who knows what, and contradictions to avoid.',
    outputContract:
        'At chat time, output a compact continuity brief only: facts, constraints, risks, and next-turn continuity notes. No scene prose.',
    fallbackPrompt:
        'Review character, persona, scenario, memory, summary, lore, and recent chat. Produce a compact continuity brief with established facts, who knows what, active constraints, unresolved threads, and contradictions to avoid. Do not write scene prose or dialogue.',
    refreshPolicy: 'turn',
    invalidationSignals: ['last_user_message_changed', 'memory_changed'],
    temperature: 0.3,
    maxTokens: 1600,
    timeoutMs: 60000,
  ),
  _ControllerSpec(
    id: 'agency',
    name: 'Agency & Character Controller',
    purpose:
        'Enforce user sovereignty, character autonomy, character psychology, subjective knowledge, and believable behavior.',
    outputContract:
        'At chat time, output actionable constraints for user agency and character behavior. No scene prose, no drafted actions, no dialogue. You may add an optional "Options" list of 1-3 branchable character-behavior approaches the final writer can pick from (describe the approach only, e.g. "let the character deflect" vs "let a crack of honesty show"); never write ready-made lines or actions.',
    fallbackPrompt:
        'Enforce user autonomy and character authenticity. Never write the user\'s dialogue, actions, thoughts, feelings, intentions, or decisions. Characters act only from established knowledge, psychology, history, physical limits, and current pressure. Produce constraints only, not prose.',
    refreshPolicy: 'scene',
    invalidationSignals: ['active_cast_changed', 'relationship_state_changed'],
    temperature: 0.3,
    maxTokens: 1400,
    timeoutMs: 60000,
  ),
  _ControllerSpec(
    id: 'narrative',
    name: 'Narrative / Pacing / Style Controller',
    purpose:
        'Convert narrative mode, style, length, POV, pacing, sensory budget, tone, and genre rules into a controllable response contract. Set response length adaptively to scene tempo: the default target is 6-8 paragraphs; shorten in fast, dynamic, action, or rapid back-and-forth dialogue scenes so the user can react sooner; lengthen toward and beyond the default in slow, descriptive, introspective, or transitional scenes.',
    outputContract:
        'At chat time, output a brief with target length, paragraph budget, POV/camera, style mode, sensory budget, beat structure, dialogue/action balance, opening constraint, and stopping point. No scene prose. Choose the paragraph budget by reading the current scene tempo: default 6-8 paragraphs; fewer (around 2-4) in fast/dynamic/action/quick-dialogue beats to hand the turn back to the user; more (8+) in slow, atmospheric, or descriptive beats. Always state both the chosen number and why this tempo warrants it in one short note. You may add an optional "Options" list of 1-3 branchable structural/style approaches the final writer can pick from (describe the approach only, e.g. "open on a physical action" vs "open on a single line of dialogue"); never write ready-made prose.',
    fallbackPrompt:
        'Extract narrative mode, pacing, style, length, POV, tone, genre, and sensory budget into a concise response contract. Set length adaptively to scene tempo: default target 6-8 paragraphs; shorten to about 2-4 in fast, dynamic, action, or rapid-dialogue scenes so the user can react; lengthen to 8+ in slow, descriptive, or introspective scenes. Include dialogue/action balance and where the response should stop. Do not draft the reply.',
    refreshPolicy: 'scene',
    invalidationSignals: ['scene_changed', 'tone_changed', 'pacing_changed'],
    temperature: 0.3,
    maxTokens: 1600,
    timeoutMs: 60000,
  ),
  _ControllerSpec(
    id: 'dialogue',
    name: 'Dialogue Controller',
    purpose:
        'Control dialogue cadence, speech texture, monologue segmentation, interaction balance, and when silence is appropriate.',
    outputContract:
        'At chat time, output dialogue guidance only: who may plausibly speak, desired dialogue ratio, speech constraints, and silence constraints. No drafted lines. You may add an optional "Options" list of 1-3 branchable dialogue approaches the final writer can pick from (describe the approach only, e.g. "answer with silence and a gesture" vs "give one clipped deflecting line"); never write the actual dialogue.',
    fallbackPrompt:
        'Guide dialogue cadence and interaction. Prefer purposeful speech when characters can plausibly speak; segment monologues naturally; preserve character voice and subtext. Do not draft dialogue.',
    refreshPolicy: 'turn',
    invalidationSignals: [
      'last_user_message_changed',
      'active_speaker_changed',
    ],
    temperature: 0.3,
    maxTokens: 1200,
    timeoutMs: 60000,
  ),
  _ControllerSpec(
    id: 'guard',
    name: 'Anti-Loop & Prose Guard',
    purpose:
        'Enforce anti-loop, anti-echo, banlists, anti-cliche, anti-slop, no-tells, and stable prose quality rules.',
    outputContract:
        'At chat time, output a compact guard checklist and forbidden items for this turn. No rewritten scene prose.',
    fallbackPrompt:
        'Check the last user message and recent assistant replies for repetition risks. Enforce anti-echo, anti-loop, banlists, forbidden cliches, and prose quality constraints. Produce a guard brief only.',
    refreshPolicy: 'turn',
    invalidationSignals: [
      'last_3_replies_changed',
      'last_user_message_changed',
    ],
    temperature: 0.2,
    maxTokens: 1400,
    timeoutMs: 60000,
  ),
  _ControllerSpec(
    id: 'world',
    name: 'World / NPC Controller',
    purpose:
        'Control living-world texture, NPC ecology, offscreen pressure, public-space activity, and background consequences without stealing focus.',
    outputContract:
        'At chat time, output world/NPC guidance only: active NPCs, off-focus thread, environmental pressure, and what not to add. No prose. You may add an optional "Options" list of 1-3 branchable world-texture approaches the final writer can pick from (describe the approach only, e.g. "let an offscreen sound intrude" vs "keep the world still and pressureless"); never write ready-made prose.',
    fallbackPrompt:
        'Guide living-world and NPC activity. NPCs should act only when the scene supports it and should affect the scene without stealing focus. Produce practical world-state guidance only.',
    refreshPolicy: 'scene',
    invalidationSignals: [
      'scene_changed',
      'location_changed',
      'active_cast_changed',
    ],
    temperature: 0.3,
    maxTokens: 1200,
    timeoutMs: 60000,
  ),
  _ControllerSpec(
    id: 'meta',
    name: 'Meta-Weaver / Lumia Policy',
    purpose:
        'Preserve Lumia/meta-weaver/OOC behavior as silent policy and OOC interface rules, not as a scene-writing agent.',
    outputContract:
        'At chat time, output only meta-policy constraints if needed. Never write in-scene prose. Lumia remains silent during normal RP unless explicitly addressed OOC.',
    fallbackPrompt:
        'Apply configured meta-weaver or OOC persona rules silently during normal RP when such a persona exists. Do not expose hidden reasoning or write meta-persona scene prose. If no meta/OOC persona is configured, this controller should remain inert and may be disabled by the user.',
    refreshPolicy: 'static',
    invalidationSignals: ['preset_changed'],
    temperature: 0.2,
    maxTokens: 1200,
    timeoutMs: 60000,
  ),
  _ControllerSpec(
    id: 'final',
    name: 'Main Responder',
    purpose:
        'Write the final visible RP response using the full prompt and the prior controller briefs.',
    outputContract:
        'At chat time, output only the final visible RP response. Obey all controller briefs and final formatting/content constraints.',
    fallbackPrompt:
        'Write the final RP response using the assembled chat prompt, character/scenario/persona instructions, memory, and prior Studio controller briefs. Obey user agency, character truth, dialogue, pacing, style, formatting, and guard constraints. Output only the final visible reply.',
    refreshPolicy: 'turn',
    invalidationSignals: ['last_user_message_changed'],
    temperature: 0.8,
    maxTokens: 8000,
    timeoutMs: 90000,
    isFinal: true,
  ),
];

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
    for (final spec in _controllerSpecs) {
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
    final spec = _specForAgent(agent);
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
    required _ControllerSpec spec,
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
    required _ControllerSpec spec,
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
    required _ControllerSpec spec,
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
    required _ControllerSpec spec,
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

  _ControllerSpec _specForAgent(StudioAgent agent) {
    final text = '${agent.id}\n${agent.name}'.toLowerCase();
    return _controllerSpecs.firstWhere(
      (spec) =>
          text.contains(spec.id) || text.contains(spec.name.toLowerCase()),
      orElse: () => agent.order >= _controllerSpecs.length - 1
          ? _controllerSpecs.last
          : _controllerSpecs[agent.order.clamp(0, _controllerSpecs.length - 1)],
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
    final validIds = _controllerSpecs.map((s) => s.id).toSet();
    final map = {for (final spec in _controllerSpecs) spec.id: <PresetBlock>[]};
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
      for (final spec in _controllerSpecs)
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
