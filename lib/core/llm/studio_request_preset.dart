import '../models/studio_config.dart';

class StudioRequestPreset {
  final String id;
  final String name;
  final List<StudioPresetBlock> blocks;

  const StudioRequestPreset({
    required this.id,
    required this.name,
    required this.blocks,
  });

  StudioRequestPreset copyWith({
    String? id,
    String? name,
    List<StudioPresetBlock>? blocks,
  }) {
    return StudioRequestPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      blocks: blocks ?? this.blocks,
    );
  }
}

const studioRequestPresets = <StudioRequestPreset>[
  StudioRequestPreset(
    id: 'norimyn_studio_agent',
    name: 'NoriMyn Studio Agent',
    blocks: [
      StudioPresetBlock(
        id: 'agent_instruction',
        title: 'Agent instruction',
        kind: 'agent_instruction',
        role: 'system',
        content:
            'You are an intermediate Studio agent. Analyze the current roleplay context and produce only a compact operational brief for later agents. Focus on continuity, character truth, scene pressure, risks, and concrete next-beat guidance. Do not write narrative prose, dialogue, or the final RP response.',
        order: 0,
      ),
      StudioPresetBlock(
        id: 'static_context',
        title: 'Character and persona context',
        kind: 'static_context',
        role: 'system',
        order: 1,
      ),
      StudioPresetBlock(
        id: 'chat_history',
        title: 'Chat history',
        kind: 'chat_history',
        role: 'user',
        order: 2,
      ),
      StudioPresetBlock(
        id: 'dynamic_context',
        title: 'Dynamic context',
        kind: 'dynamic_context',
        role: 'system',
        order: 3,
      ),
    ],
  ),
  StudioRequestPreset(
    id: 'norimyn_studio_final',
    name: 'NoriMyn Studio Final',
    blocks: [
      StudioPresetBlock(
        id: 'agent_instruction',
        title: 'Final agent instruction',
        kind: 'agent_instruction',
        role: 'system',
        content:
            'Write the assistant next reply in immersive fictional roleplay with the user. Generate the continuation directly without meta-commentary. Never write the user dialogue, actions, thoughts, feelings, intentions, or decisions. Each paragraph must advance action, exchange, perception, or consequence.',
        order: 0,
      ),
      StudioPresetBlock(
        id: 'previous_agents',
        title: 'Previous Studio agents',
        kind: 'previous_agents',
        role: 'system',
        order: 1,
      ),
      StudioPresetBlock(
        id: 'static_context',
        title: 'Character and persona context',
        kind: 'static_context',
        role: 'system',
        order: 2,
      ),
      StudioPresetBlock(
        id: 'chat_history',
        title: 'Chat history',
        kind: 'chat_history',
        role: 'user',
        order: 3,
      ),
      StudioPresetBlock(
        id: 'dynamic_context',
        title: 'Dynamic context',
        kind: 'dynamic_context',
        role: 'system',
        order: 4,
      ),
    ],
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
  final blocks = override.blocks.isNotEmpty
      ? override.blocks
      : _legacyOverrideBlocks(base, override);
  return base.copyWith(
    name: override.name.trim().isNotEmpty ? override.name.trim() : base.name,
    blocks: blocks,
  );
}

List<StudioPresetBlock> _legacyOverrideBlocks(
  StudioRequestPreset base,
  StudioPresetOverride override,
) {
  final instruction = base.id == defaultFinalStudioPresetId
      ? override.finalInstruction
      : override.intermediateInstruction;
  if (instruction.trim().isEmpty) return base.blocks;
  return base.blocks
      .map(
        (block) => block.kind == 'agent_instruction'
            ? block.copyWith(content: instruction)
            : block,
      )
      .toList(growable: false);
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
    blocks: preset.blocks,
  );
}

StudioRequestPreset defaultStudioRequestPresetById(String id) {
  return studioRequestPresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => studioRequestPresets.first,
  );
}
