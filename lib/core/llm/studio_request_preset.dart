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
            'You are an intermediate Studio agent. Analyze the current roleplay context and produce only a compact operational brief for later agents. Focus on continuity, character truth, scene pressure, and risks. Do not write narrative prose, dialogue, or the final RP response.',
        order: 0,
      ),
      StudioPresetBlock(
        id: 'user_persona',
        title: 'User Persona',
        kind: 'user_persona',
        role: 'system',
        order: 1,
      ),
      StudioPresetBlock(
        id: 'char_card',
        title: 'Character Description',
        kind: 'char_card',
        role: 'system',
        order: 2,
      ),
      StudioPresetBlock(
        id: 'scenario',
        title: 'Scenario',
        kind: 'scenario',
        role: 'system',
        order: 3,
      ),
      StudioPresetBlock(
        id: 'char_personality',
        title: 'Character Personality',
        kind: 'char_personality',
        role: 'system',
        order: 4,
      ),
      StudioPresetBlock(
        id: 'example_dialogue',
        title: 'Chat Examples',
        kind: 'example_dialogue',
        role: 'system',
        order: 5,
      ),
      StudioPresetBlock(
        id: 'authors_note',
        title: "Author's Note",
        kind: 'authors_note',
        role: 'system',
        order: 6,
      ),
      StudioPresetBlock(
        id: 'static_context',
        title: 'Other preset system blocks',
        kind: 'static_context',
        role: 'system',
        order: 7,
      ),
      StudioPresetBlock(
        id: 'chat_history',
        title: 'Chat History',
        kind: 'chat_history',
        role: 'user',
        order: 8,
      ),
      StudioPresetBlock(
        id: 'worldInfoBefore',
        title: 'World Info Before',
        kind: 'worldInfoBefore',
        role: 'system',
        order: 9,
      ),
      StudioPresetBlock(
        id: 'worldInfoAfter',
        title: 'World Info After',
        kind: 'worldInfoAfter',
        role: 'system',
        order: 10,
      ),
      StudioPresetBlock(
        id: 'memory',
        title: 'Memory',
        kind: 'memory',
        role: 'system',
        order: 11,
      ),
      StudioPresetBlock(
        id: 'summary',
        title: 'Summary',
        kind: 'summary',
        role: 'system',
        order: 12,
      ),
      StudioPresetBlock(
        id: 'guided_generation',
        title: 'Guided Generation',
        kind: 'guided_generation',
        role: 'system',
        order: 13,
      ),
      StudioPresetBlock(
        id: 'dynamic_context',
        title: 'Other dynamic blocks',
        kind: 'dynamic_context',
        role: 'system',
        order: 14,
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
            'Write the assistant next reply in immersive fictional roleplay with the user. Generate the continuation directly without meta-commentary.',
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
        id: 'user_persona',
        title: 'User Persona',
        kind: 'user_persona',
        role: 'system',
        order: 2,
      ),
      StudioPresetBlock(
        id: 'char_card',
        title: 'Character Description',
        kind: 'char_card',
        role: 'system',
        order: 3,
      ),
      StudioPresetBlock(
        id: 'scenario',
        title: 'Scenario',
        kind: 'scenario',
        role: 'system',
        order: 4,
      ),
      StudioPresetBlock(
        id: 'char_personality',
        title: 'Character Personality',
        kind: 'char_personality',
        role: 'system',
        order: 5,
      ),
      StudioPresetBlock(
        id: 'example_dialogue',
        title: 'Chat Examples',
        kind: 'example_dialogue',
        role: 'system',
        order: 6,
      ),
      StudioPresetBlock(
        id: 'authors_note',
        title: "Author's Note",
        kind: 'authors_note',
        role: 'system',
        order: 7,
      ),
      StudioPresetBlock(
        id: 'static_context',
        title: 'Other preset system blocks',
        kind: 'static_context',
        role: 'system',
        order: 8,
      ),
      StudioPresetBlock(
        id: 'chat_history',
        title: 'Chat History',
        kind: 'chat_history',
        role: 'user',
        order: 9,
      ),
      StudioPresetBlock(
        id: 'worldInfoBefore',
        title: 'World Info Before',
        kind: 'worldInfoBefore',
        role: 'system',
        order: 10,
      ),
      StudioPresetBlock(
        id: 'worldInfoAfter',
        title: 'World Info After',
        kind: 'worldInfoAfter',
        role: 'system',
        order: 11,
      ),
      StudioPresetBlock(
        id: 'memory',
        title: 'Memory',
        kind: 'memory',
        role: 'system',
        order: 12,
      ),
      StudioPresetBlock(
        id: 'summary',
        title: 'Summary',
        kind: 'summary',
        role: 'system',
        order: 13,
      ),
      StudioPresetBlock(
        id: 'guided_generation',
        title: 'Guided Generation',
        kind: 'guided_generation',
        role: 'system',
        order: 14,
      ),
      StudioPresetBlock(
        id: 'dynamic_context',
        title: 'Other dynamic blocks',
        kind: 'dynamic_context',
        role: 'system',
        order: 15,
      ),
    ],
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
  final resolvedId = id.isNotEmpty ? id : fallbackId;
  return studioRequestPresets.firstWhere(
    (preset) => preset.id == resolvedId,
    orElse: () => studioRequestPresets.firstWhere((p) => p.id == fallbackId),
  );
}

StudioRequestPreset defaultStudioRequestPresetById(String id) {
  return studioRequestPresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => studioRequestPresets.first,
  );
}
