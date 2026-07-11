import 'studio_config.dart';

const _continuityTask = '''<continuity_context>
Return at most 8 short, neutral facts needed to prevent a contradiction in the
next reply. Track only demonstrated scene state: presence, location, physical
constraints, already-made commitments, and consequences. Do not write prose,
dialogue, options, or a scene plan.</continuity_context>''';

const _sceneDirectorTask = '''<scene_direction>
Return at most 5 neutral operational points: immediate pressure, a concrete
consequence worth respecting, active character presence, and where to return
control to {{user}}. Do not draft dialogue, hooks, sample lines, locations, or
undeclared actions. Do not teleport the plot or invent a character's arrival,
relationship, knowledge, or next decision.</scene_direction>''';

const _directContract = '''<loom_direct_contract>
Write from the character and scene directly. Never write {{user}}'s words,
actions, thoughts, feelings, or decisions. Treat current character state as
scoped priority; do not generalize it to unrelated people or situations.
</loom_direct_contract>''';

const _assistedContract = '''<loom_assisted_contract>
The Continuity and Scene Direction blocks are compact reference data, not prose
to echo or instructions to inflate. Preserve their concrete constraints. Never
write {{user}}'s words, actions, thoughts, feelings, or decisions. Do not turn
suggested pressure into an undeclared action, arrival, relationship, or plot
teleport.</loom_assisted_contract>''';

/// Creates a local preset whose persisted blocks and controller toggles match
/// an execution topology. Runtime gating remains a second line of defence for
/// stale Studio agent rows; it does not own prompt content.
StudioPreset prepareStudioPresetForMode(
  StudioPreset source, {
  required String id,
  required String name,
  required StudioExecutionMode mode,
  required int updatedAt,
}) {
  const assistedTaskIds = {
    'continuity_task_universal',
    'narrative_task_universal',
  };
  final allowedAgents = switch (mode) {
    StudioExecutionMode.legacy => null,
    StudioExecutionMode.direct => const {'final'},
    StudioExecutionMode.assisted => const {'continuity', 'narrative', 'final'},
  };

  final agentEnabled = Map<String, bool>.from(source.agentEnabled);
  if (allowedAgents != null) {
    for (final specId in const {
      'continuity',
      'agency',
      'narrative',
      'dialogue',
      'guard',
      'world',
      'meta',
      'beauty',
      'final',
    }) {
      agentEnabled[specId] = allowedAgents.contains(specId);
    }
  }

  final blocks = <StudioPresetBlock>[];
  for (final block in source.blocks) {
    if (block.kind == 'tracker_instruction') {
      if (mode == StudioExecutionMode.direct) continue;
      if (mode == StudioExecutionMode.assisted &&
          !assistedTaskIds.contains(block.id)) {
        continue;
      }
    }
    if (mode != StudioExecutionMode.legacy && block.id == 'beauty_extractor') {
      blocks.add(block.copyWith(enabled: false));
    } else if (mode == StudioExecutionMode.assisted &&
        block.id == 'continuity_task_universal') {
      blocks.add(block.copyWith(content: _continuityTask));
    } else if (mode == StudioExecutionMode.assisted &&
        block.id == 'narrative_task_universal') {
      blocks.add(block.copyWith(content: _sceneDirectorTask));
    } else if (mode == StudioExecutionMode.direct &&
        block.id == 'final_response_shape_contract') {
      blocks.add(
        block.copyWith(content: '${block.content}\n\n$_directContract'),
      );
    } else if (mode == StudioExecutionMode.assisted &&
        block.id == 'final_response_shape_contract') {
      blocks.add(
        block.copyWith(content: '${block.content}\n\n$_assistedContract'),
      );
    } else {
      blocks.add(block);
    }
  }

  return source.copyWith(
    id: id,
    name: name,
    blocks: blocks,
    agentEnabled: agentEnabled,
    executionMode: mode,
    updatedAt: updatedAt,
  );
}
