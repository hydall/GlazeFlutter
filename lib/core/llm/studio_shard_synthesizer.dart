import 'dart:async';

import 'package:dio/dio.dart';

import '../models/api_config.dart';
import '../models/preset.dart';
import '../models/studio_config.dart';
import 'reasoning_stripper.dart';
import 'studio_block_classifier.dart';
import 'studio_build_llm_client.dart';
import 'studio_controller_ontology.dart';

/// Synthesizes a Studio agent's build-time `promptShard` from its assigned
/// preset blocks, and normalizes the resulting agents (reasoning stripping +
/// guard sentences). Extracted from `StudioDecompositionService` (plan §3).
///
/// Two synthesis modes:
/// - `verbatim` (default): concatenate the assigned blocks дословно, no LLM.
/// - legacy LLM-compiled: ask the build model to compress the blocks into a
///   stable controller instruction (with fence/refusal cleanup + fallback).
///
/// Dependencies are injected: the [StudioBuildLlmClient] for the legacy path
/// and a [log] sink so the `[StudioBuild]` diagnostics are unchanged.
class StudioShardSynthesizer {
  final StudioBuildLlmClient _buildLlm;
  final void Function(String message) _log;

  StudioShardSynthesizer(this._buildLlm, this._log);

  Future<String> synthesizePromptShard({
    required StudioControllerSpec spec,
    required List<PresetBlock> blocks,
    ApiConfig? apiConfig,
    String builderPromptTemplate = '',
    String routingMode = 'verbatim',
    CancelToken? cancelToken,
    bool lumiaActive = false,
  }) async {
    if (blocks.isEmpty && !lumiaActive) return spec.fallbackPrompt;

    // Stage 3: verbatim routing — concatenate blocks directly, no LLM call.
    // The preset is the source of truth; the agent sees its assigned blocks
    // дословно. See docs/PLAN_AGENTIC_STUDIO.md §11.
    if (routingMode == 'verbatim') {
      return _synthesizeRoutedShard(
        spec: spec,
        blocks: blocks,
        lumiaActive: lumiaActive,
      );
    }

    // Legacy: LLM-compiled shard (переваривание).
    final prompt = _buildControllerPrompt(
      spec: spec,
      blocks: blocks,
      builderPromptTemplate: builderPromptTemplate,
    );
    try {
      final raw = await _buildLlm.call(
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
    return '${spec.fallbackPrompt}\n\nSource blocks: ${sourceBlockNames(blocks)}';
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
    bool lumiaActive = false,
  }) {
    final parts = <String>[];
    for (final block in blocks) {
      final name = block.name.isNotEmpty ? block.name : block.id;
      final content = block.content.trim();
      if (content.isEmpty) continue;
      parts.add('[Block: $name]\n$content');
    }
    if (parts.isEmpty && !lumiaActive) return spec.fallbackPrompt;

    final body = parts.join('\n\n---\n\n');
    // Conflict resolution footer (§12): when two blocks contradict, the one
    // later in the preset wins (higher priority = closer to the end).
    const conflictFooter =
        '\n\n---\n\n[Conflict resolution: if two blocks above contradict each '
        'other, follow the one that appears LAST.]';

    // Lumia architecture (plan §Part A/B): the Meta-Weaver counts turns and
    // emits a brief; the Main Responder writes the actual `<lumiaooc>` reply
    // guided by a COMPACT contract (format + voice), not the full
    // `<lumia_ghost>` block (which lives in Meta-Weaver's shard).
    final lumiaSuffix = lumiaActive
        ? (spec.id == 'meta'
            ? _metaWeaverCountingDuty
            : (spec.id == 'final' ? _mainResponderLumiaContract : ''))
        : '';

    return '$body$conflictFooter$lumiaSuffix';
  }

  /// Appended to the Meta-Weaver's shard when a `<lumia_ghost>` block is
  /// assigned to it. Emphasizes the counting duty: the Meta-Weaver must count
  /// assistant messages, apply the period rule from the block, and emit a
  /// brief — NOT the actual `<lumiaooc>` reply (the Main Responder writes
  /// that). See docs/plans/PLAN_STUDIO_PROMPT_FILTERING.md §Part A.
  static const _metaWeaverCountingDuty = '\n\n---\n\n[Lumia counting duty]\n'
      'You run EVERY turn. Count the assistant messages in the chat history you '
      'see. Read the period rule from the assigned `<lumia_ghost>` block above '
      '(e.g. "Every 4 assistant responses"). Decide one of:\n'
      '- `lumia_ooc: due | topic: <X>` — the user explicitly addressed Lumia in OOC brackets (e.g. `((Lumia: ...))`, `[OOC: ...]`).\n'
      '- `lumia_periodic_note: due | last_note: <N turns ago> | keep: 1-3 sentences, warm, maternal, useful, not scene-stealing` — the period rule fired this turn.\n'
      '- `lumia: silent` — neither condition met.\n'
      'Output ONLY the brief line above. Do NOT write the actual `<lumiaooc>` '
      'reply — the Main Responder writes that, guided by your brief.';

  /// Appended to the Main Responder's shard when a `<lumia_ghost>` block exists
  /// in the preset (routed to Meta-Weaver, not to the final responder). This is
  /// a COMPACT Lumia output contract: format + voice + emit-when-brief-says-due.
  /// The Main Responder never sees the full `<lumia_ghost>` block — only this
  /// contract + the Meta-Weaver's brief. See docs/plans/PLAN_STUDIO_PROMPT_FILTERING.md §Part B.
  static const _mainResponderLumiaContract = '\n\n---\n\n[Lumia output contract]\n'
      'A separate Meta-Weaver agent runs every turn and sends you a brief. '
      'When the brief says `lumia_ooc: due` or `lumia_periodic_note: due`, '
      'append a Lumia OOC note AFTER your narrative reply, wrapped EXACTLY '
      'like this:\n'
      '`<lumiaooc><font color="#9370DB"><i>Lumia: <your 1-3 sentence note here></i></font></lumiaooc>`\n'
      'Voice: warm, maternal, useful, not scene-stealing. Never advance the '
      'plot or speak for the characters. Keep it to 1-3 sentences. When the '
      'brief says `lumia: silent`, do NOT emit any `<lumiaooc>` block — just '
      'write the narrative reply. The `<lumiaooc>` block is meta-commentary '
      'addressed to the user outside the roleplay; the POST-cleaner preserves '
      'it verbatim.';

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
    final bucket = StudioBlockClassifier.bucketForBlock(block);
    if (bucket == 'meta') return 6000;
    if (bucket == 'final') return 3500;
    return 2500;
  }

  String _truncate(String text, int limit) {
    if (text.length <= limit) return text;
    return '${text.substring(0, limit)}...';
  }

  /// Comma-joined, de-duplicated list of the assigned block names. Used both
  /// for the fallback shard footer and the agent's `sourceBlockNames`.
  String sourceBlockNames(List<PresetBlock> blocks) {
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

  /// Normalize a built agent list: sort by order, strip reasoning directives
  /// from each shard, and append the appropriate guard sentence (final vs
  /// intermediate).
  List<StudioAgent> normalizeStudioAgents(List<StudioAgent> agents) {
    if (agents.isEmpty) return agents;
    final ordered = agents.toList()..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < ordered.length; i++)
        normalizeStudioAgent(ordered[i], isFinal: i == ordered.length - 1),
    ];
  }

  StudioAgent normalizeStudioAgent(
    StudioAgent agent, {
    required bool isFinal,
  }) {
    var prompt = ReasoningStripper.stripPromptShardReasoning(agent.promptShard);
    prompt = isFinal
        ? _appendSentence(prompt, _finalResponderGuard)
        : _appendSentence(prompt, _intermediateBriefGuard);

    return agent.copyWith(
      promptShard: prompt,
      sourceBlockNames: _stripReasoningSourceNames(agent.sourceBlockNames),
    );
  }

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
}
