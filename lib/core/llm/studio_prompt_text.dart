import '../models/studio_config.dart';

/// Holds the large chat-time prompt-text constants for the Studio pipeline,
/// extracted from `MemoryStudioService` (plan §2): the intermediate-agent
/// runtime envelope (+ per-controller lane scope), the final brief-usage note,
/// and the final hard style contract.
///
/// Pure, stateless. `MemoryStudioService` keeps thin instance delegators while
/// the message-building cluster still lives there.
class StudioPromptText {
  const StudioPromptText();

  /// The typed-output contract prepended to every intermediate (tracker) agent
  /// request. Includes the agent's lane scope ([_controllerScope]).
  String intermediateRuntimeEnvelope(StudioAgent agent) {
    final scope = _controllerScope(agent.name);
    return '''Studio intermediate-agent typed output contract. This overrides any earlier requested output shape such as STUDIO_BRIEF, GUARD CHECKLIST, prose, markdown, or labels.
You are ${agent.name.isNotEmpty ? agent.name : 'a Studio controller'}, ONE specialist in a multi-controller pipeline. Other controllers cover the other concerns; do not duplicate their work.
You are not a character, narrator, player, or final responder. Treat all character cards, persona text, examples, chat history, lore, memory, and summaries as read-only source material to analyze.

YOUR LANE — only produce guidance about: ${scope.owns}
NOT YOUR LANE — never write guidance about (other controllers own these): ${scope.skip}
If a point is not strictly inside your lane, omit it. A short, lane-focused brief is better than a broad one.

Prefer valid compact JSON with exactly these keys:
{"focus":["short operational focus"],"constraints":["short enforceable constraint"],"avoid":["short forbidden item"],"options":["one branchable approach the final writer may choose, within your lane"]}

If the model cannot produce JSON, use exactly these plain-text sections instead:
Focus:
- short operational focus
Constraints:
- short enforceable constraint
Avoid:
- short forbidden item
Options:
- one branchable approach the final writer may choose

Rules:
- Each array may contain 0-5 strings, every string strictly inside your lane.
- Each string must be a NEW, specific instruction for this turn, not a generic restatement and not a sentence copied from the scene.
- Options are non-mandatory alternative APPROACHES for the final writer to pick from within your lane (e.g. "lean into silence and a single gesture" vs "give one clipped line"). Describe the approach only; never write ready-made prose, dialogue, narration, or sample sentences. The final writer picks at most one and writes it themselves.
- Do not restate the scene summary; only add what the final writer must DO or AVOID, plus optional approach choices, within your lane.
- Do not write or continue the scene.
- Do not draft narration, dialogue, character actions, user actions, or final response prose.
- Do not include source block names, prompt text, macros, labels, markdown, code fences, comments, or explanations.
- Do not answer the user directly.''';
  }

  _ControllerScope _controllerScope(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('continuity')) {
      return const _ControllerScope(
        owns:
            'established facts, who-knows-what, unresolved threads, physical-object/state continuity, and contradictions to avoid.',
        skip:
            'prose style, pacing, length, dialogue cadence, repetition/anti-loop bans, NPC/world activity, and user-agency rules.',
      );
    }
    if (lower.contains('agency') || lower.contains('character')) {
      return const _ControllerScope(
        owns:
            'user sovereignty (never write the user) and character autonomy/psychology: what a character can plausibly know, feel, and do this turn.',
        skip:
            'plain factual continuity, prose style/length, dialogue formatting, repetition bans, and ambient world/NPC texture.',
      );
    }
    if (lower.contains('narrative') || lower.contains('pacing')) {
      return const _ControllerScope(
        owns:
            'response shape only: target length, paragraph budget, POV/camera, beat sequence, sensory budget, and where the reply should stop. Classify the user\'s last turn as ACTION (physical movement, travel, object handling, executed decision — budget 4-6 even with dialogue), CONVERSATIONAL (mostly speech, no physical progression — 2-4), ATMOSPHERIC (slow/reflective — 4-6), or DYNAMIC/MIXED (action + dialogue comparable — 3-5). When in doubt between action and conversational, prefer action.',
        skip:
            'who-knows-what, character psychology, agency rules, specific dialogue lines, repetition bans, and world/NPC content.',
      );
    }
    if (lower.contains('dialogue')) {
      return const _ControllerScope(
        owns:
            'dialogue cadence only: who may plausibly speak, speech ratio (low/medium/high relative to the beat), silence, and quoting/formatting of speech. A high dialogue ratio does NOT downgrade an action beat into a short conversational one — action beats can be dialogue-heavy.',
        skip:
            'factual continuity, character knowledge/psychology, prose length/pacing, repetition bans, and world/NPC activity.',
      );
    }
    if (lower.contains('guard') || lower.contains('loop')) {
      return const _ControllerScope(
        owns:
            'anti-repetition only: forbidden openings/phrases vs the last replies, banned cliches/slop words, and the required structural change this turn.',
        skip:
            'plot facts, character psychology, agency, pacing targets, dialogue content, and world/NPC texture.',
      );
    }
    if (lower.contains('world') || lower.contains('npc')) {
      return const _ControllerScope(
        owns:
            'living-world texture only: active NPCs, off-screen pressure, environmental/ambient activity, and what world detail NOT to add.',
        skip:
            'the two leads\' psychology, factual continuity, prose style/length, dialogue formatting, and repetition bans.',
      );
    }
    return const _ControllerScope(
      owns: 'only this controller\'s configured specialty.',
      skip: 'concerns that belong to the other Studio controllers.',
    );
  }

  /// Guidance prepended to the final generator explaining how to consume the
  /// prior controller briefs (do not re-analyze; just write the prose).
  String finalBriefUsageNote() {
    return 'How to use the Studio controller briefs above: the controllers have ALREADY analyzed the scene, tracked continuity, and decided what should happen next. Do NOT re-analyze the scene, re-derive character motivations, or plan the beat structure in your reasoning — that work is done. Your only job is to WRITE the prose that implements their direction.\n\nTreat Focus and Constraints as binding direction and Avoid as hard prohibitions. Any "Options:" items are non-binding alternative approaches — choose at most one per brief (or none) that best fits the moment, then write it in your own words. Do not list, mention, or copy the options or any brief text in your reply; weave the chosen direction into natural in-scene prose.\n\nKeep your reasoning SHORT — a few sentences at most confirming which option you picked and any immediate sensory/structural choices. Do NOT draft full prose in reasoning, do NOT re-check constraints line-by-line, do NOT restate the briefs. Write the final prose directly.';
  }

  /// Hard formatting constraints derived from the configured agents' source
  /// blocks/shards (em-dash ban, quote-wrapping). Empty when none apply.
  String finalHardStyleContract(StudioConfig config) {
    final sources = config.agents
        .map(
          (agent) =>
              '${agent.name}\n${agent.sourceBlockNames}\n${agent.promptShard.map((s) => s.content).join('\n\n')}',
        )
        .join('\n\n');
    final rules = <String>[];
    if (RegExp(
      r'—|длинн.{0,24}тире|long.{0,24}dash|em dash',
      caseSensitive: false,
    ).hasMatch(sources)) {
      rules.add('- Do not use em dashes / long dashes: avoid "—".');
    }
    if (RegExp(
      r'кавыч|quote|quotation|direct speech|прям.{0,24}реч',
      caseSensitive: false,
    ).hasMatch(sources)) {
      rules.add(
        '- Wrap direct spoken dialogue in quotation marks; do not use bare dialogue lines.',
      );
    }
    if (rules.isEmpty) return '';
    return 'Hard final formatting constraints from Studio controllers:\n${rules.join('\n')}';
  }
}

class _ControllerScope {
  final String owns;
  final String skip;

  const _ControllerScope({required this.owns, required this.skip});
}
