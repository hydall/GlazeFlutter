import '../models/studio_config.dart';
import 'beauty_shard_instruction.dart';

/// One hard-coded Studio controller slot. The decomposition engine assigns
/// preset blocks to these stable slots and synthesizes one agent per slot.
class StudioControllerSpec {
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
  final int contextSize;

  const StudioControllerSpec({
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
    // Default tracker context size (trailing chat messages forwarded to this
    // agent). 0 = inherit the StudioAgent freezed default of 5.
    this.contextSize = 0,
  });
}

/// The fixed set of Studio controller slots + lookup helpers. Pure data
/// extracted from `StudioDecompositionService` (plan §3).
class StudioControllerOntology {
  StudioControllerOntology._();

  /// All controller slots, in pipeline order (the last one is the final
  /// generator). The decomposition engine builds one agent per spec.
  static const List<StudioControllerSpec> specs = <StudioControllerSpec>[
    StudioControllerSpec(
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
    StudioControllerSpec(
      id: 'agency',
      name: 'Agency & Character Controller',
      purpose:
          'Enforce user sovereignty, character autonomy, character psychology, subjective knowledge, and believable behavior.',
      outputContract:
          'At chat time, output actionable constraints for user agency and character behavior. No scene prose, no drafted actions, no dialogue. You may add an optional "Options" list of 1-3 branchable character-behavior approaches the final writer can pick from (describe the approach only, e.g. "let the character deflect" vs "let a crack of honesty show"); never write ready-made lines or actions.',
      fallbackPrompt:
          'Enforce user autonomy and character authenticity. Never write the user\'s dialogue, actions, thoughts, feelings, intentions, or decisions. Characters act only from established knowledge, psychology, history, physical limits, and current pressure. Produce constraints only, not prose.',
      refreshPolicy: 'turn',
      invalidationSignals: [
        'active_cast_changed',
        'relationship_state_changed',
      ],
      temperature: 0.3,
      maxTokens: 1400,
      timeoutMs: 60000,
    ),
    StudioControllerSpec(
      id: 'narrative',
      name: 'Narrative / Pacing / Style Controller',
      purpose:
          'Convert narrative mode, style, POV, pacing, sensory budget, tone, and genre rules into a controllable response contract. Classify the scene beat type and set a tempo (short / medium / long) — but DO NOT hardcode paragraph counts. The user\'s preset (dynamic or fixed-length) owns the actual numbers; your job is to tell the final writer what KIND of beat this is and roughly how dense it should feel, so the preset\'s length rules can apply correctly.',
      outputContract:
          'At chat time, output a brief with beat type, tempo (short / medium / long), POV/camera, style mode, sensory budget, dialogue/action balance, opening constraint, and stopping point. No scene prose. No hardcoded paragraph counts — those come from the user\'s preset.\n\nBEAT-TYPE RUBRIC — classify the user\'s last turn into exactly one of these, in priority order:\n'
          '1. ACTION — physical movement, travel, combat, pursuit, escape, riding/driving, object manipulation, a decision that is physically executed (mounting a bike, drawing a weapon, taking an object, putting on a helmet, entering a room). Even if accompanied by one or two lines of dialogue, the dominant content is physical. Tempo: medium-to-long (the physical beat needs room to land).\n'
          '2. CONVERSATIONAL — two or more characters exchange dialogue with little or no physical progression; the scene stays in one place and the turn is mostly speech/reaction/thought. Tempo: short-to-medium.\n'
          '3. ATMOSPHERIC / INTROSPECTIVE — slow description, mood, inner reflection, environmental scene-setting, time/scene transitions, sensory immersion. Tempo: medium-to-long.\n'
          '4. DYNAMIC / MIXED — the turn blends physical action with meaningful dialogue and reaction in comparable weight (e.g. character acts AND talks through the action, or a short exchange resolves into a physical decision). Tempo: medium.\n\n'
          'DO NOT collapse a turn that contains physical movement, travel, object handling, or executed decisions into "conversational" just because it also has dialogue. Dialogue inside an action beat does NOT make it conversational. When in doubt between action and conversational, prefer action.\n\n'
          'CRITICAL: do NOT invent paragraph numbers. State the beat type and a qualitative tempo (short / medium / long). The final writer\'s preset supplies the exact paragraph/word budget — your tempo hint helps the preset apply the right tier. If the preset is dynamic, the final writer maps your tempo to its own tiers. If the preset is fixed-length, the final writer just writes to that length with your beat-type guidance.\n\n'
          'Always state the chosen beat type, the tempo word, and a one-line note on why this tempo warrants it. You may add an optional "Options" list of 1-3 branchable structural/style approaches the final writer can pick from (describe the approach only, e.g. "open on a physical action" vs "open on a single line of dialogue"); never write ready-made prose.',
      fallbackPrompt:
          'Extract narrative mode, pacing, style, POV, tone, genre, and sensory budget into a concise response contract. Classify the user\'s last turn as ACTION (physical movement, travel, object handling, executed decision — even when dialogue is present), CONVERSATIONAL (mostly speech, no physical progression), ATMOSPHERIC (slow/reflective), or DYNAMIC/MIXED (action + dialogue comparable). Set a qualitative tempo: short, medium, or long. Do NOT invent paragraph counts — the user\'s preset owns the numbers. When in doubt between action and conversational, prefer action. Include dialogue/action balance and where the response should stop. Do not draft the reply.',
      refreshPolicy: 'turn',
      invalidationSignals: ['scene_changed', 'tone_changed', 'pacing_changed'],
      temperature: 0.3,
      maxTokens: 1600,
      timeoutMs: 60000,
    ),
    StudioControllerSpec(
      id: 'dialogue',
      name: 'Dialogue Controller',
      purpose:
          'Control dialogue cadence, speech texture, monologue segmentation, interaction balance, and when silence is appropriate. Your job is dialogue RATIO and TEXTURE — you do NOT decide beat type or paragraph budget (that is the Narrative Controller\'s lane). Provide a dialogue ratio that is compatible with the scene\'s actual beat: action beats can still be dialogue-heavy (characters talk while moving/riding/fighting); a high dialogue ratio does NOT downgrade an action beat into a short conversational one.',
      outputContract:
          'At chat time, output dialogue guidance only: who may plausibly speak, desired dialogue ratio (low / medium / high — relative to the beat, not absolute), speech constraints, and silence constraints. State the ratio as a proportion of the response that should be spoken lines vs physical action/narration, compatible with whatever beat type the Narrative Controller chose. No drafted lines. You may add an optional "Options" list of 1-3 branchable dialogue approaches the final writer can pick from (describe the approach only, e.g. "answer with silence and a gesture" vs "give one clipped deflecting line"); never write the actual dialogue.',
      fallbackPrompt:
          'Guide dialogue cadence and interaction. Prefer purposeful speech when characters can plausibly speak; segment monologues naturally; preserve character voice and subtext. Set a dialogue ratio compatible with the current beat (action beats can be dialogue-heavy; a high ratio does not make an action beat "conversational"). Do not draft dialogue.',
      refreshPolicy: 'turn',
      invalidationSignals: [
        'last_user_message_changed',
        'active_speaker_changed',
      ],
      temperature: 0.3,
      maxTokens: 1200,
      timeoutMs: 60000,
    ),
    StudioControllerSpec(
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
    StudioControllerSpec(
      id: 'world',
      name: 'World / NPC Controller',
      purpose:
          'Control living-world texture, NPC ecology, offscreen pressure, public-space activity, and background consequences without stealing focus.',
      outputContract:
          'At chat time, output world/NPC guidance only: active NPCs, off-focus thread, environmental pressure, and what not to add. No prose. You may add an optional "Options" list of 1-3 branchable world-texture approaches the final writer can pick from (describe the approach only, e.g. "let an offscreen sound intrude" vs "keep the world still and pressureless"); never write ready-made prose.',
      fallbackPrompt:
          'Guide living-world and NPC activity. NPCs should act only when the scene supports it and should affect the scene without stealing focus. Produce practical world-state guidance only.',
      refreshPolicy: 'turn',
      invalidationSignals: [
        'scene_changed',
        'location_changed',
        'active_cast_changed',
      ],
      temperature: 0.3,
      maxTokens: 1200,
      timeoutMs: 60000,
    ),
    StudioControllerSpec(
      id: 'meta',
      name: 'Meta-Weaver / OOC Policy',
      purpose:
          'Meta-weaver / OOC interface controller. Runs EVERY turn when the preset has a meta/OOC block assigned. Counts assistant messages in the history it sees, applies the period rule from the assigned meta block (e.g. "Every 4 assistant responses"), and decides whether the meta-persona should emit an OOC note this turn, respond to an explicit OOC address, or stay silent. The meta-persona\'s name, voice, length, and format are all defined by the user\'s preset block — the controller does NOT hardcode any persona.',
      outputContract:
          'At chat time, output a compact meta brief ONLY. Decide one of: '
          '`meta_ooc: due | topic: <X>` (user addressed the meta-persona OOC), '
          '`meta_periodic_note: due | last_note: <N turns ago> | voice: <from block> | length: <from block> | format: <from block>` (the Nth assistant turn fired the period rule — relay the voice/length/format/wrapper from the assigned meta block so the Main Responder writes in the user\'s chosen style), '
          'or `meta: silent` (neither condition met). Never write in-scene prose, never write the actual OOC reply — that is the Main Responder\'s job, guided by your brief.',
      fallbackPrompt:
          'You are the meta-weaver / OOC interface. Count the assistant messages in the history you see. Read the period rule, persona name, voice, length, format, and wrapper from your assigned meta block (e.g. period "Every 4 assistant responses", voice "warm, maternal", wrapper "<lumiaooc>...</lumiaooc>", length "1-3 sentences"). The persona name and voice come entirely from the block — do NOT assume any specific name or voice. If the count since the last meta note matches the period, output `meta_periodic_note: due` and relay the block\'s persona/voice/length/wrapper instructions so the Main Responder writes the note correctly. If the user explicitly addressed the meta-persona in OOC brackets (e.g. `((<persona>: ...))`, `[OOC: ...]`), output `meta_ooc: due` with the detected topic. Otherwise output `meta: silent`. Do NOT write the actual OOC reply — only the brief telling the Main Responder whether to emit one.',
      refreshPolicy: 'turn',
      invalidationSignals: [
        'last_user_message_changed',
        'assistant_turn_count_changed',
      ],
      temperature: 0.2,
      maxTokens: 1200,
      timeoutMs: 60000,
    ),
    StudioControllerSpec(
      id: 'beauty',
      name: 'Beauty Shard',
      purpose:
          'Track reusable visual styling state only: HTML/CSS palette, background, text/font colors, speaker colors, typography, gradients, and art-style labels. Skip concrete HTML widgets, trackers, infoblocks, and image-generation instructions.',
      outputContract:
          'At chat time, output a compact beauty-state brief only: current reusable style variables, constraints for preserving/updating them, and items to avoid. Do NOT write scene prose. Do NOT handle concrete UI artifacts (phone screens, taxi menus, terminals), trackers, infoblocks, topbars, or image-gen blocks.',
      fallbackPrompt: beautyShardTrackerFallbackPrompt,
      refreshPolicy: 'turn',
      invalidationSignals: ['last_user_message_changed', 'style_state_changed'],
      temperature: 0.2,
      maxTokens: 1200,
      timeoutMs: 60000,
    ),
    StudioControllerSpec(
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

  /// Map an existing agent back to its controller spec — by id/name match,
  /// falling back to pipeline-order position. Used by single-agent regen.
  static StudioControllerSpec specForAgent(StudioAgent agent) {
    final text = '${agent.id}\n${agent.name}'.toLowerCase();
    return specs.firstWhere(
      (spec) =>
          text.contains(spec.id) || text.contains(spec.name.toLowerCase()),
      orElse: () => agent.order >= specs.length - 1
          ? specs.last
          : specs[agent.order.clamp(0, specs.length - 1)],
    );
  }
}
