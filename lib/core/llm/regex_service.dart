import '../models/preset.dart';
import '../models/character.dart';
import '../models/persona.dart';
import 'macro_engine.dart';

class RegexApplyContext {
  final Character? char;
  final Persona? persona;
  final Map<String, String> sessionVars;
  final Map<String, String> globalVars;
  final int? depth;
  final int totalMessages;

  const RegexApplyContext({
    this.char,
    this.persona,
    this.sessionVars = const {},
    this.globalVars = const {},
    this.depth,
    this.totalMessages = 0,
  });
}

String applyRegexes(
  String text,
  int placementFilter,
  int ephemeralityFilter,
  List<PresetRegex> scripts,
  RegexApplyContext ctx,
) {
  var result = text;

  for (final script in scripts) {
    if (script.disabled) continue;

    final sPlacement = script.placement;
    if (sPlacement.isNotEmpty && !sPlacement.contains(placementFilter)) continue;

    final sEphemerality = script.ephemerality;
    if (sEphemerality.isNotEmpty && !sEphemerality.contains(ephemeralityFilter)) continue;

    // ST-style context flags: markdownOnly vs promptOnly
    // Heuristic used in Glaze: placement 1/2 = history (often rendered as markdown),
    // placement 4 = system/prompt blocks. If a script declares one of the flags,
    // restrict application accordingly. Both false = apply to all contexts (current default).
    if (script.markdownOnly && ![1, 2].contains(placementFilter)) continue;
    if (script.promptOnly && placementFilter != 4) continue;

    if (ctx.depth != null) {
      final minD = script.minDepth;
      final maxD = script.maxDepth;
      if (minD != null && ctx.depth! < minD) continue;
      if (maxD != null && ctx.depth! > maxD) continue;
    }

    result = _applySingleScript(result, script, ctx);
  }

  return result;
}

String _applySingleScript(String text, PresetRegex script, RegexApplyContext ctx) {
  var processed = text;

  if (script.trimOut.isNotEmpty) {
    final tokens = script.trimOut.split('\n').where((t) => t.trim().isNotEmpty);
    for (final token in tokens) {
      processed = processed.replaceAll(token, '');
    }
  }

  var pattern = script.regex;
  var replacement = script.replacement;

  if (script.macroRules != '0' && ctx.char != null) {
    final macroCtx = MacroContext(
      charName: ctx.char!.name,
      userName: ctx.persona?.name ?? 'User',
      charId: ctx.char!.id,
      sessionId: '',
      macroName: ctx.char!.macroName,
    );

    if (script.macroRules == '1') {
      pattern = replaceMacros(pattern, macroCtx).text;
      replacement = replaceMacros(replacement, macroCtx).text;
    } else if (script.macroRules == '2') {
      pattern = pattern
          .replaceAllMapped(RegExp(r'{{user}}', caseSensitive: false), (_) => _escapeRegex(ctx.persona?.name ?? 'User'))
          .replaceAllMapped(RegExp(r'{{char}}', caseSensitive: false), (_) => _escapeRegex(ctx.char!.name));
      pattern = replaceMacros(pattern, macroCtx).text;
      replacement = replaceMacros(replacement, macroCtx).text;
    }
  }

  if (pattern.isEmpty) return processed;

  final parsed = _parseRegexPattern(pattern);
  try {
    final regex = RegExp(parsed.pattern, multiLine: parsed.multiLine, dotAll: parsed.dotAll, caseSensitive: parsed.caseSensitive);

    // Determine if we need custom replacement logic (backrefs or substituteRegex mode)
    final hasBackrefs = RegExp(r'(\\\d|\$\d)').hasMatch(replacement);
    final useSubst = script.substituteRegex != 0;

    if (hasBackrefs || useSubst) {
      processed = processed.replaceAllMapped(regex, (match) => _resolveReplacement(replacement, match));
    } else {
      processed = processed.replaceAll(regex, replacement);
    }
  } catch (_) {}

  return processed;
}

/// Resolves a replacement string that may contain backreferences ($1, \1, $2, \2, etc.)
/// against a Match (RegExpMatch in practice). Supports both $n (Dart/ST common) and \n (ST raw) forms.
String _resolveReplacement(String template, Match match) {
  // Replace $n and \n style backrefs. We scan from longest possible group index down
  // to avoid partial overlaps (e.g., $10 before $1).
  final groupCount = match.groupCount;
  var result = template;

  for (int i = groupCount; i >= 0; i--) {
    final captured = match.group(i) ?? '';
    // $n form
    result = result.replaceAll('\$${i}', captured);
    // \n form (raw backslash in the stored replacement string)
    result = result.replaceAll('\\$i', captured);
  }

  return result;
}

({String pattern, bool multiLine, bool dotAll, bool caseSensitive}) _parseRegexPattern(String raw) {
  if (raw.startsWith('/') && raw.length > 1) {
    final lastSlash = raw.lastIndexOf('/');
    if (lastSlash > 0) {
      final pattern = raw.substring(1, lastSlash);
      final flags = raw.substring(lastSlash + 1);
      return (
        pattern: pattern,
        multiLine: flags.contains('m'),
        dotAll: flags.contains('s'),
        caseSensitive: !flags.contains('i'),
      );
    }
  }
  return (pattern: raw, multiLine: false, dotAll: false, caseSensitive: true);
}

String _escapeRegex(String s) {
  return s.replaceAll(RegExp(r'[/\-\\^$*+?.()|[\]{}]'), r'\$&');
}
