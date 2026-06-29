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

  Future<List<PromptShardBlock>> synthesizePromptShard({
    required StudioControllerSpec spec,
    required List<PresetBlock> blocks,
    ApiConfig? apiConfig,
    String builderPromptTemplate = '',
    String routingMode = 'verbatim',
    CancelToken? cancelToken,
    bool lumiaActive = false,
  }) async {
    if (blocks.isEmpty && !lumiaActive) {
      return [PromptShardBlock(content: spec.fallbackPrompt)];
    }

    // Stage 3: verbatim routing — emit one PromptShardBlock per preset block,
    // no LLM call. The preset is the source of truth; the agent sees its
    // assigned blocks дословно. See docs/PLAN_AGENTIC_STUDIO.md §11.
    if (routingMode == 'verbatim') {
      return _synthesizeRoutedShard(
        spec: spec,
        blocks: blocks,
        lumiaActive: lumiaActive,
      );
    }

    // Legacy: LLM-compiled shard (переваривание) — produces a single block.
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
      if (cleaned.isNotEmpty && !_isBuilderRefusal(cleaned)) {
        return [PromptShardBlock(content: cleaned)];
      }
      if (cleaned.isNotEmpty) {
        _log('controller build refusal name="${spec.name}"; using fallback');
      }
    } on TimeoutException {
      _log('controller build timeout name="${spec.name}"; using fallback');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      _log('controller build error name="${spec.name}" error=$e');
    }
    return [
      PromptShardBlock(
        content:
            '${spec.fallbackPrompt}\n\nSource blocks: ${sourceBlockNames(blocks)}',
      ),
    ];
  }

  /// Stage 3: Verbatim routing — produces one [PromptShardBlock] per assigned
  /// preset block дословно, without any LLM compilation.
  ///
  /// Each block preserves its `role`, `blockName`, and `blockId` from the
  /// preset, so `buildAgentMessages` can emit each as a SEPARATE API system
  /// message (cache-friendly, structured). Blocks are in preset order
  /// (priority = position in preset, §12). A conflict-resolution footer block
  /// is appended: "при конфликте следуй последнему блоку". Lumia suffixes
  /// (counting duty / compact contract) become their own blocks.
  ///
  /// This makes the preset the direct source of truth for the agent — no
  /// intermediary LLM distorts the user's instructions. See
  /// docs/PLAN_AGENTIC_STUDIO.md §11 + docs/plans/PLAN_STUDIO_SHARD_BLOCKS.md.
  List<PromptShardBlock> _synthesizeRoutedShard({
    required StudioControllerSpec spec,
    required List<PresetBlock> blocks,
    bool lumiaActive = false,
  }) {
    final shardBlocks = <PromptShardBlock>[];
    for (final block in blocks) {
      final content = block.content.trim();
      if (content.isEmpty) continue;
      shardBlocks.add(
        PromptShardBlock(
          role: block.role.isNotEmpty ? block.role : 'system',
          content: content,
          blockName: block.name.isNotEmpty ? block.name : block.id,
          blockId: block.id,
        ),
      );
    }

    // Conflict resolution footer (§12): a soft precedence hint. The preset's
    // own block order already implies priority (later = higher priority in
    // verbatim mode). This footer just makes the default explicit so the model
    // knows how to resolve contradictions when two blocks disagree. A preset
    // that wants a different precedence model (e.g. "character card wins") can
    // express it in its own blocks; this footer is a fallback, not an override.
    shardBlocks.add(
      const PromptShardBlock(
        content:
            '[Conflict resolution: if two blocks above contradict each other '
            'and neither explicitly claims precedence, follow the one that '
            'appears LAST.]',
        blockName: 'Conflict resolution',
      ),
    );

    // Meta-weaver architecture (plan §Part A/B): the Meta-Weaver counts turns
    // and emits a brief; the Main Responder writes the actual OOC reply guided
    // by a COMPACT contract, not the full meta block (which lives in the
    // Meta-Weaver's shard). Persona name, voice, length, format, and wrapper
    // all come from the user's meta block via the brief — not hardcoded here.
    if (lumiaActive) {
      if (spec.id == 'meta') {
        shardBlocks.add(
          const PromptShardBlock(
            content: _metaWeaverCountingDuty,
            blockName: 'Meta-weaver counting duty',
          ),
        );
      } else if (spec.id == 'final') {
        shardBlocks.add(
          const PromptShardBlock(
            content: _mainResponderMetaContract,
            blockName: 'Meta-weaver output contract',
          ),
        );
      }
    }

    return shardBlocks;
  }

  /// Appended to the Meta-Weaver's shard when a meta/OOC block is assigned to
  /// it. Emphasizes the counting duty: the Meta-Weaver must count assistant
  /// messages, apply the period rule from the block, and emit a brief — NOT
  /// the actual OOC reply (the Main Responder writes that). Persona name,
  /// voice, length, format, and wrapper are all defined by the user's meta
  /// block above — the controller does NOT hardcode any persona.
  /// See docs/plans/PLAN_STUDIO_PROMPT_FILTERING.md §Part A.
  static const _metaWeaverCountingDuty = '[Meta-weaver counting duty]\n'
      'You run EVERY turn. Count the assistant messages in the chat history you '
      'see. Read the period rule, persona name, voice, length, format, and '
      'wrapper from the assigned meta block above (e.g. period "Every 4 '
      'assistant responses", persona "Lumia" / "Sister" / "DM", voice "warm, '
      'maternal" / "playful" / "cold", wrapper "<lumiaooc>...</lumiaooc>" / '
      '"<oocnote>...</oocnote>", length "1-3 sentences"). The persona name and '
      'voice come entirely from the block — do NOT assume any specific name or '
      'voice. Decide one of:\n'
      '- `meta_ooc: due | topic: <X>` — the user explicitly addressed the meta-persona in OOC brackets (e.g. `((<persona>: ...))`, `[OOC: ...]`).\n'
      '- `meta_periodic_note: due | last_note: <N turns ago> | persona: <from block> | voice: <from block> | length: <from block> | wrapper: <from block>` — the period rule fired this turn. Relay the block\'s persona/voice/length/wrapper so the Main Responder writes the note in the user\'s chosen style.\n'
      '- `meta: silent` — neither condition met.\n'
      'Output ONLY the brief line above. Do NOT write the actual OOC reply — '
      'the Main Responder writes that, guided by your brief.';

  /// Appended to the Main Responder's shard when a meta/OOC block exists in
  /// the preset (routed to Meta-Weaver, not to the final responder). This is a
  /// COMPACT meta output contract: when to emit. Persona name, voice, length,
  /// format, and wrapper are NOT hardcoded here — they come from the meta
  /// block via the Meta-Weaver brief. The Main Responder reads only this
  /// contract + the brief, so the brief is the carrier of the user's meta
  /// persona. See docs/plans/PLAN_STUDIO_PROMPT_FILTERING.md §Part B.
  static const _mainResponderMetaContract = '[Meta-weaver output contract]\n'
      'A separate Meta-Weaver agent runs every turn and sends you a brief. '
      'When the brief says `meta_ooc: due` or `meta_periodic_note: due`, '
      'append a meta OOC note AFTER your narrative reply. The brief carries '
      'the persona name, voice, length, format, and wrapper from the user\'s '
      'meta block — follow them exactly. If the brief specifies a wrapper '
      '(e.g. `<lumiaooc>...</lumiaooc>`, `<oocnote>...</oocnote>`), use it. If '
      'it does not specify a wrapper, emit the note as plain text after the '
      'narrative. Never advance the plot or speak for the characters. When the '
      'brief says `meta: silent`, do NOT emit any meta OOC note — just write '
      'the narrative reply. The meta note is meta-commentary addressed to the '
      'user outside the roleplay; the POST-cleaner preserves it verbatim.';

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
- If assigned blocks contain meta-weaver/OOC behavior, convert it to silent final-model policy or OOC interface rules; do not make this controller write meta-persona scene prose.
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
- If assigned blocks contain meta-weaver/OOC behavior, preserve it as silent meta-policy/OOC interface rules. Do not make the controller write meta-persona scene prose.
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
    final guard = isFinal ? _finalResponderGuard : _intermediateBriefGuard;
    final stripped = <PromptShardBlock>[];
    for (final block in agent.promptShard) {
      final cleaned = ReasoningStripper.stripPromptShardReasoning(block.content);
      if (cleaned.trim().isEmpty) continue;
      stripped.add(block.copyWith(content: cleaned));
    }
    // Append the guard sentence to the last non-empty block. If no blocks
    // survived stripping, emit the guard as a single block so the contract
    // still reaches the model.
    if (stripped.isEmpty) {
      stripped.add(PromptShardBlock(content: guard, blockName: 'Guard'));
    } else {
      final last = stripped.removeLast();
      stripped.add(
        last.copyWith(content: _appendSentence(last.content, guard)),
      );
    }

    return agent.copyWith(
      promptShard: stripped,
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
      "When giving style guidance, you may include brief do/don't examples derived from the user's preset, but never draft or continue the current scene, and never write in-scene dialogue/actions as if it were the final reply.";

  static const _finalResponderGuard =
      'Generate the final visible reply. Do not output hidden reasoning blocks unless the user\'s preset explicitly requests visible reasoning in the reply.';
}
