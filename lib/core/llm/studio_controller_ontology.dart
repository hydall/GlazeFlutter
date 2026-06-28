import '../models/studio_config.dart';

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
    // agent). 0 = inherit the StudioAgent freezed default of 5. The
    // Meta-Weaver overrides this to 15 so it can count Lumia periods up to
    // ~10. See docs/plans/PLAN_STUDIO_PROMPT_FILTERING.md §Part A.
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
      refreshPolicy: 'scene',
      invalidationSignals: ['active_cast_changed', 'relationship_state_changed'],
      temperature: 0.3,
      maxTokens: 1400,
      timeoutMs: 60000,
    ),
    StudioControllerSpec(
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
    StudioControllerSpec(
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
    StudioControllerSpec(
      id: 'meta',
      name: 'Meta-Weaver / Lumia Policy',
      purpose:
          'Lumia/meta-weaver/OOC interface. Runs EVERY turn. Counts assistant messages in the history it sees, applies the period rule from the assigned `<lumia_ghost>` block (e.g. "Every 4 assistant responses"), and decides whether Lumia should emit an OOC note this turn, respond to an explicit OOC address, or stay silent.',
      outputContract:
          'At chat time, output a compact Lumia brief ONLY. Decide one of: '
          '`lumia_ooc: due | topic: <X>` (user addressed Lumia OOC), '
          '`lumia_periodic_note: due | last_note: <N turns ago> | keep: 1-3 sentences, warm, maternal, useful, not scene-stealing` (the Nth assistant turn fired the period rule), '
          'or `lumia: silent` (neither condition met). Never write in-scene prose, never write the actual `<lumiaooc>` reply — that is the Main Responder\'s job, guided by your brief.',
      fallbackPrompt:
          'You are the Lumia/meta-weaver. Count the assistant messages in the history you see. Read the period rule from your assigned `<lumia_ghost>` block (e.g. "Every 4 assistant responses"). If the count since the last Lumia note matches the period, output `lumia_periodic_note: due` with guidance to keep it 1-3 sentences, warm, maternal, useful, and not scene-stealing. If the user explicitly addressed Lumia in OOC brackets (e.g. `((Lumia: ...))`, `[OOC: ...]`), output `lumia_ooc: due` with the detected topic. Otherwise output `lumia: silent`. Do NOT write the actual Lumia OOC reply — only the brief telling the Main Responder whether to emit one.',
      refreshPolicy: 'turn',
      invalidationSignals: ['last_user_message_changed', 'assistant_turn_count_changed'],
      temperature: 0.2,
      maxTokens: 1200,
      timeoutMs: 60000,
      contextSize: 15,
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
