import 'dart:math';

class MacroContext {
  final String charName;
  final String? charDescription;
  final String? charScenario;
  final String? charPersonality;
  final String? charMesExample;
  final String userName;
  final String? personaPrompt;
  final String? reasoningStart;
  final String? reasoningEnd;
  final Map<String, String> sessionVars;
  final Map<String, String> globalVars;
  final String charId;
  final String sessionId;
  final String? summaryContent;
  final String? lorebooksContent;
  final String? guidanceText;
  final String? macroName;
  /// Memory content to be appended when expanding {{summary}} in summary_macro mode.
  /// This allows <wrapper>{{summary}}</wrapper> to enclose both the summary and the injected memories.
  final String? summaryMemoryContent;

  const MacroContext({
    required this.charName,
    this.charDescription,
    this.charScenario,
    this.charPersonality,
    this.charMesExample,
    this.userName = 'User',
    this.personaPrompt,
    this.reasoningStart,
    this.reasoningEnd,
    this.sessionVars = const {},
    this.globalVars = const {},
    required this.charId,
    required this.sessionId,
    this.summaryContent,
    this.lorebooksContent,
    this.guidanceText,
    this.macroName,
    this.summaryMemoryContent,
  });

  MacroContext copyWith({
    Map<String, String>? sessionVars,
    Map<String, String>? globalVars,
    String? charScenario,
    String? charPersonality,
    String? charDescription,
    String? summaryContent,
    String? lorebooksContent,
    String? guidanceText,
    String? summaryMemoryContent,
  }) {
    return MacroContext(
      charName: charName,
      charDescription: charDescription ?? this.charDescription,
      charScenario: charScenario ?? this.charScenario,
      charPersonality: charPersonality ?? this.charPersonality,
      charMesExample: charMesExample,
      userName: userName,
      personaPrompt: personaPrompt,
      reasoningStart: reasoningStart,
      reasoningEnd: reasoningEnd,
      sessionVars: sessionVars ?? this.sessionVars,
      globalVars: globalVars ?? this.globalVars,
      charId: charId,
      sessionId: sessionId,
      summaryContent: summaryContent ?? this.summaryContent,
      lorebooksContent: lorebooksContent ?? this.lorebooksContent,
      guidanceText: guidanceText ?? this.guidanceText,
      macroName: macroName,
      summaryMemoryContent: summaryMemoryContent ?? this.summaryMemoryContent,
    );
  }

  Map<String, dynamic> toJson() => {
    'charName': charName,
    'charDescription': charDescription,
    'charScenario': charScenario,
    'charPersonality': charPersonality,
    'charMesExample': charMesExample,
    'userName': userName,
    'personaPrompt': personaPrompt,
    'reasoningStart': reasoningStart,
    'reasoningEnd': reasoningEnd,
    'sessionVars': sessionVars,
    'globalVars': globalVars,
    'charId': charId,
    'sessionId': sessionId,
    'summaryContent': summaryContent,
    'lorebooksContent': lorebooksContent,
    'guidanceText': guidanceText,
    'macroName': macroName,
    'summaryMemoryContent': summaryMemoryContent,
  };

  factory MacroContext.fromJson(Map<String, dynamic> json) => MacroContext(
    charName: json['charName'] as String,
    charDescription: json['charDescription'] as String?,
    charScenario: json['charScenario'] as String?,
    charPersonality: json['charPersonality'] as String?,
    charMesExample: json['charMesExample'] as String?,
    userName: json['userName'] as String? ?? 'User',
    personaPrompt: json['personaPrompt'] as String?,
    reasoningStart: json['reasoningStart'] as String?,
    reasoningEnd: json['reasoningEnd'] as String?,
    sessionVars: Map<String, String>.from(json['sessionVars'] as Map? ?? {}),
    globalVars: Map<String, String>.from(json['globalVars'] as Map? ?? {}),
    charId: json['charId'] as String,
    sessionId: json['sessionId'] as String,
    summaryContent: json['summaryContent'] as String?,
    lorebooksContent: json['lorebooksContent'] as String?,
    guidanceText: json['guidanceText'] as String?,
    macroName: json['macroName'] as String?,
    summaryMemoryContent: json['summaryMemoryContent'] as String?,
  );
}

class MacroResult {
  final String text;
  final Map<String, String> sessionVars;
  final Map<String, String> globalVars;
  final bool varsChanged;

  const MacroResult({
    required this.text,
    required this.sessionVars,
    required this.globalVars,
    required this.varsChanged,
  });
}

MacroResult replaceMacros(String text, MacroContext ctx) {
  var result = text;
  final sessionVars = Map<String, String>.from(ctx.sessionVars);
  var pickCount = 0;
  final globalVars = Map<String, String>.from(ctx.globalVars);
  var varsChanged = false;
  final random = Random();

  result = result.replaceAllMapped(
    RegExp(r'\{\{\s*\/\/\s*\}\}[\s\S]*?\{\{\s*\/\/\/\s*\}\}'),
    (_) => '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{\/\/[^}]*\}\}'),
    (_) => '',
  );

  final resolvedCharName = ctx.macroName ?? ctx.charName;

  result = result.replaceAllMapped(
    RegExp(r'\{\{char\}\}', caseSensitive: false),
    (_) => resolvedCharName,
  );

  result = result.replaceAllMapped(
    RegExp(r'\{char\}', caseSensitive: false),
    (_) => resolvedCharName,
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{description\}\}', caseSensitive: false),
    (_) => ctx.charDescription ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{description\}', caseSensitive: false),
    (_) => ctx.charDescription ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{scenario\}\}', caseSensitive: false),
    (_) => ctx.charScenario ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{scenario\}', caseSensitive: false),
    (_) => ctx.charScenario ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{personality\}\}', caseSensitive: false),
    (_) => ctx.charPersonality ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{personality\}', caseSensitive: false),
    (_) => ctx.charPersonality ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{mesExamples\}\}', caseSensitive: false),
    (_) => ctx.charMesExample ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{mesExamples\}', caseSensitive: false),
    (_) => ctx.charMesExample ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{user\}\}', caseSensitive: false),
    (_) => ctx.userName,
  );

  result = result.replaceAllMapped(
    RegExp(r'\{user\}', caseSensitive: false),
    (_) => ctx.userName,
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{persona\}\}', caseSensitive: false),
    (_) => ctx.personaPrompt ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{persona\}', caseSensitive: false),
    (_) => ctx.personaPrompt ?? '',
  );

  if (result.contains('{{trim}}')) {
    result = result.replaceAllMapped(
      RegExp(r'\{\{trim\}\}', caseSensitive: false),
      (_) => '',
    );
    result = result.trim();
  }

  result = result.replaceAllMapped(
    RegExp(r'\{\{reasoningPrefix\}\}', caseSensitive: false),
    (_) => ctx.reasoningStart ?? '<think' '>',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{reasoningSuffix\}\}', caseSensitive: false),
    (_) => ctx.reasoningEnd ?? '</think' '>',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{summary\}\}', caseSensitive: false),
    (_) {
      final base = ctx.summaryContent ?? '';
      if (ctx.summaryMemoryContent != null && ctx.summaryMemoryContent!.isNotEmpty) {
        if (base.isEmpty) return ctx.summaryMemoryContent!;
        return '$base\n\n${ctx.summaryMemoryContent!}';
      }
      return base;
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{lorebooks\}\}', caseSensitive: false),
    (_) => ctx.lorebooksContent ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{guidance\}\}', caseSensitive: false),
    (_) => ctx.guidanceText ?? '',
  );

  result = _replaceSetVar(result, 'setvar', sessionVars, () => varsChanged = true);
  result = _replaceSetVar(result, 'setglobalvar', globalVars, () => varsChanged = true);

  result = result.replaceAllMapped(
    RegExp(r'\{\{getvar::([\s\S]*?)\}\}', caseSensitive: false),
    (m) {
      final name = m.group(1)!.trim();
      return sessionVars[name] ?? '';
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{getglobalvar::([\s\S]*?)\}\}', caseSensitive: false),
    (m) {
      final name = m.group(1)!.trim();
      return globalVars[name] ?? '';
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{(lumiaDef|lumiaOOC|lumiaOOCErotic|lumiaOOCEroticBleed|lumiaPersonality|loomRetrofits|loomStyle|loomSummary|loomUtils|sim_tracker|suggest)\}\}', caseSensitive: false),
    (m) {
      final name = m.group(1)!;
      final val = globalVars[name];
      return val ?? m.group(0)!;
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{random::(.*?)\}\}', caseSensitive: false),
    (m) {
      final parts = m.group(1)!.split('::');
      if (parts.isEmpty) return '';
      return parts[random.nextInt(parts.length)];
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{pick::(.*?)\}\}', caseSensitive: false),
    (m) {
      final parts = m.group(1)!.split('::');
      if (parts.isEmpty) return '';
      final version = int.tryParse(sessionVars['__pick_version'] ?? '0') ?? 0;
      final seed = '${ctx.charId}_${ctx.sessionId}_pick_${pickCount++}_v$version';
      final hash = _simpleHash(seed);
      return parts[hash % parts.length];
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{roll::(.*?)\}\}', caseSensitive: false),
    (m) {
      final result = _rollDice(m.group(1)!);
      return result != null ? result.toString() : m.group(1)!;
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{date\}\}', caseSensitive: false),
    (_) => DateTime.now().toLocal().toString().split(' ').first,
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{time\}\}', caseSensitive: false),
    (_) => DateTime.now().toLocal().toString().split(' ').last.split('.').first,
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{weekday\}\}', caseSensitive: false),
    (_) {
      final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[DateTime.now().weekday - 1];
    },
  );

  result = result.replaceAll('\\{', '{').replaceAll('\\}', '}');

  return MacroResult(
    text: result,
    sessionVars: sessionVars,
    globalVars: globalVars,
    varsChanged: varsChanged,
  );
}

int _simpleHash(String input) {
  var hash = 0;
  for (var i = 0; i < input.length; i++) {
    hash = ((hash << 5) - hash + input.codeUnitAt(i));
    hash = (hash | 0).toSigned(32);
  }
  return hash.abs();
}

int? _rollDice(String spec) {
  final match = RegExp(r'(\d+)d(\d+)', caseSensitive: false).firstMatch(spec);
  if (match == null) return null;
  final count = int.parse(match.group(1)!);
  final sides = int.parse(match.group(2)!);
  final random = Random();
  var total = 0;
  for (var i = 0; i < count; i++) {
    total += random.nextInt(sides) + 1;
  }
  return total;
}

String _replaceSetVar(String text, String keyword, Map<String, String> vars, void Function() markChanged) {
  final tag = '{{$keyword::';
  final buf = StringBuffer();
  int i = 0;
  while (i < text.length) {
    final idx = text.indexOf(tag, i);
    if (idx < 0) {
      buf.write(text.substring(i));
      break;
    }
    buf.write(text.substring(i, idx));
    final afterTag = idx + tag.length;
    final secondDblColon = text.indexOf('::', afterTag);
    if (secondDblColon < 0) {
      buf.write(text.substring(idx));
      break;
    }
    final name = text.substring(afterTag, secondDblColon).trim();
    final valueStart = secondDblColon + 2;
    var depth = 1;
    var pos = valueStart;
    while (pos < text.length && depth > 0) {
      if (pos + 1 < text.length && text[pos] == '{' && text[pos + 1] == '{') {
        depth++;
        pos += 2;
      } else if (pos + 1 < text.length && text[pos] == '}' && text[pos + 1] == '}') {
        depth--;
        if (depth == 0) break;
        pos += 2;
      } else {
        pos++;
      }
    }
    if (depth != 0) {
      buf.write(text.substring(idx));
      break;
    }
    final value = text.substring(valueStart, pos).trim();
    vars[name] = value;
    markChanged();
    i = pos + 2;
  }
  return buf.toString();
}
