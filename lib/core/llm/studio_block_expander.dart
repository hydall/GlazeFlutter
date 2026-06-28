import '../models/preset.dart';
import 'macro_engine.dart';

/// Pure block-transform specialist extracted from `StudioDecompositionService`
/// (plan §3): expands `{{setvar}}`/`{{getvar}}`/`{{trim}}` macros across preset
/// blocks at BUILD time, threading the variable store forward in block order.
///
/// Has no `Ref` and no state. Behavior is preserved verbatim from the original
/// `StudioDecompositionService.expandBlocksForRouting`; a static delegator is
/// kept on the service because tests reference
/// `StudioDecompositionService.expandBlocksForRouting`.
class StudioBlockExpander {
  StudioBlockExpander._();

  /// Expands `{{setvar}}`/`{{getvar}}`/`{{trim}}` macros across all blocks in
  /// preset order, threading the variable store forward (matching
  /// `prompt_builder.dart` block-order semantics).
  ///
  /// This resolves the setvar→getvar pipeline at BUILD time so that rule
  /// values reach their destination blocks even when the CoT dispatcher
  /// (which previously read all variables via getvar) is dropped as a
  /// reasoning block. Other macros (`{{char}}`, `{{user}}`, …) are left
  /// untouched for chat-time expansion.
  ///
  /// **setvar-only blocks** (pure `{{setvar::…}}` — content is empty after
  /// expansion but variables were set) are surfaced: their rule-like variable
  /// values (`*_rules`, `*_target`, or multi-line/long text) become the
  /// block's content, so the rules reach an agent instead of vanishing.
  /// Technical flags (`*_mode`, `*_min`, `*_max` — short single-word/number
  /// values) are discarded.
  ///
  /// Returns a new list of [PresetBlock]s with expanded content, in the same
  /// order. Blocks whose expanded content is still empty (no setvar, no
  /// getvar, no text) are dropped.
  static List<PresetBlock> expandBlocksForRouting(List<PresetBlock> blocks) {
    var sessionVars = <String, String>{};
    var globalVars = <String, String>{};
    final result = <PresetBlock>[];

    for (final block in blocks) {
      final beforeVars = Map<String, String>.from(sessionVars);

      final expanded = expandVariableMacros(
        block.content,
        sessionVars: sessionVars,
        globalVars: globalVars,
      );
      sessionVars = expanded.sessionVars;
      globalVars = expanded.globalVars;

      var content = expanded.text.trim();

      // setvar-only block: surface rule-like variable values as content.
      if (content.isEmpty) {
        final newEntries = expanded.sessionVars.entries.where((e) {
          final beforeVal = beforeVars[e.key];
          if (beforeVal != null &&
              beforeVal == e.value &&
              !_wasSetByThisBlock(e.key, block.content)) {
            return false;
          }
          return _isRuleVariable(e.key, e.value);
        });
        final surfaced = newEntries
            .map((e) => e.value.trim())
            .where((v) => v.isNotEmpty)
            .join('\n\n');
        content = surfaced;
      }

      if (content.isEmpty) continue;
      result.add(block.copyWith(content: content));
    }
    return result;
  }

  /// True if [blockContent] contains a `{{setvar::name::…}}` for [name].
  /// Used to confirm a variable was set by THIS block (not just inherited).
  static bool _wasSetByThisBlock(String name, String blockContent) {
    final tag = '{{setvar::$name::';
    return blockContent.contains(tag);
  }

  /// True if a variable name + value look like a rule payload (vs a technical
  /// flag). Rule-like names end with `_rules`, `_rule`, or `_target`. Values
  /// that are multi-line or long (50+ chars) are also treated as rules.
  static bool _isRuleVariable(String name, String value) {
    final lower = name.toLowerCase();
    if (lower.endsWith('_rules') ||
        lower.endsWith('_rule') ||
        lower.endsWith('_target')) {
      return true;
    }
    if (value.contains('\n') || value.length > 50) return true;
    return false;
  }
}
