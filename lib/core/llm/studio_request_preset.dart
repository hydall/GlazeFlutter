class StudioRequestPreset {
  final String id;
  final String name;
  final String intermediateInstruction;
  final String finalInstruction;

  const StudioRequestPreset({
    required this.id,
    required this.name,
    required this.intermediateInstruction,
    required this.finalInstruction,
  });
}

const studioRequestPresets = <StudioRequestPreset>[
  StudioRequestPreset(
    id: 'norimyn_studio_agent',
    name: 'NoriMyn Studio Agent',
    intermediateInstruction:
        'You are an intermediate Studio agent. Analyze the current roleplay context and produce only a compact operational brief for later agents. Focus on continuity, character truth, scene pressure, risks, and concrete next-beat guidance. Do not write narrative prose, dialogue, or the final RP response.',
    finalInstruction:
        'You are the final Studio responder. Use the Studio agent briefs and the resolved roleplay context to write the assistant next reply directly. Stay in character, preserve user autonomy, avoid echoing the user, and output only the final in-character response.',
  ),
  StudioRequestPreset(
    id: 'norimyn_studio_final',
    name: 'NoriMyn Studio Final',
    intermediateInstruction:
        'You are an intermediate Studio agent. The chat history is context for analysis, not a request for you to answer directly. Return a concise brief with factual continuity, active characters, unresolved threads, and practical response constraints.',
    finalInstruction:
        'Write the assistant next reply in immersive fictional roleplay with the user. Generate the continuation directly without meta-commentary. Never write the user dialogue, actions, thoughts, feelings, intentions, or decisions. Each paragraph must advance action, exchange, perception, or consequence.',
  ),
];

const defaultAgentStudioPresetId = 'norimyn_studio_agent';
const defaultFinalStudioPresetId = 'norimyn_studio_final';

StudioRequestPreset studioRequestPresetById(
  String id, {
  required bool finalPreset,
}) {
  final fallbackId = finalPreset
      ? defaultFinalStudioPresetId
      : defaultAgentStudioPresetId;
  return studioRequestPresets.firstWhere(
    (preset) => preset.id == (id.isNotEmpty ? id : fallbackId),
    orElse: () => studioRequestPresets.firstWhere((p) => p.id == fallbackId),
  );
}
