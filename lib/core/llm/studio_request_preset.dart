import '../models/studio_config.dart';

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

  StudioRequestPreset copyWith({
    String? id,
    String? name,
    String? intermediateInstruction,
    String? finalInstruction,
  }) {
    return StudioRequestPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      intermediateInstruction:
          intermediateInstruction ?? this.intermediateInstruction,
      finalInstruction: finalInstruction ?? this.finalInstruction,
    );
  }
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
  List<StudioPresetOverride> overrides = const [],
}) {
  final fallbackId = finalPreset
      ? defaultFinalStudioPresetId
      : defaultAgentStudioPresetId;
  final resolvedId = id.isNotEmpty ? id : fallbackId;
  final base = studioRequestPresets.firstWhere(
    (preset) => preset.id == resolvedId,
    orElse: () => studioRequestPresets.firstWhere((p) => p.id == fallbackId),
  );
  final override = overrides.where((p) => p.id == base.id).firstOrNull;
  if (override == null) return base;
  return base.copyWith(
    name: override.name.trim().isNotEmpty ? override.name.trim() : base.name,
    intermediateInstruction: override.intermediateInstruction.trim().isNotEmpty
        ? override.intermediateInstruction
        : base.intermediateInstruction,
    finalInstruction: override.finalInstruction.trim().isNotEmpty
        ? override.finalInstruction
        : base.finalInstruction,
  );
}

List<StudioRequestPreset> resolvedStudioRequestPresets(
  List<StudioPresetOverride> overrides,
) {
  return studioRequestPresets
      .map(
        (preset) => studioRequestPresetById(
          preset.id,
          finalPreset: preset.id == defaultFinalStudioPresetId,
          overrides: overrides,
        ),
      )
      .toList(growable: false);
}

StudioPresetOverride studioRequestPresetToOverride(StudioRequestPreset preset) {
  return StudioPresetOverride(
    id: preset.id,
    name: preset.name,
    intermediateInstruction: preset.intermediateInstruction,
    finalInstruction: preset.finalInstruction,
  );
}

StudioRequestPreset defaultStudioRequestPresetById(String id) {
  return studioRequestPresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => studioRequestPresets.first,
  );
}
