import '../models/preset.dart';

/// Verbatim block concatenator — produces a prompt shard by concatenating
/// assigned preset blocks дословно, without any LLM compilation.
///
/// Each block is emitted with a header `[Block: <name>]` followed by its
/// content. Blocks are in preset order (priority = position in preset).
/// A conflict-resolution footer is appended: "при конфликте следуй последнему
/// блоку".
///
/// This makes the preset the direct source of truth for the tracker — no
/// intermediary LLM distorts the user's instructions.
///
/// Split out of the deleted `studio_decomposition_service.dart` (Phase 2.2 of
/// docs/PLAN_AGENTIC_STUDIO.md). The `_ControllerSpec` coupling was generalized
/// into a plain [fallbackPrompt] parameter.
String synthesizeRoutedShard({
  required List<PresetBlock> blocks,
  String fallbackPrompt = '',
}) {
  final parts = <String>[];
  for (final block in blocks) {
    final name = block.name.isNotEmpty ? block.name : block.id;
    final content = block.content.trim();
    if (content.isEmpty) continue;
    parts.add('[Block: $name]\n$content');
  }
  if (parts.isEmpty) return fallbackPrompt;

  final body = parts.join('\n\n---\n\n');
  // Conflict resolution footer: when two blocks contradict, the one
  // later in the preset wins (higher priority = closer to the end).
  const conflictFooter =
      '\n\n---\n\n[Conflict resolution: if two blocks above contradict each '
      'other, follow the one that appears LAST.]';

  return '$body$conflictFooter';
}
