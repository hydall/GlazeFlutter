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
  });

  MacroContext copyWith({
    Map<String, String>? sessionVars,
    Map<String, String>? globalVars,
  }) {
    return MacroContext(
      charName: charName,
      charDescription: charDescription,
      charScenario: charScenario,
      charPersonality: charPersonality,
      charMesExample: charMesExample,
      userName: userName,
      personaPrompt: personaPrompt,
      reasoningStart: reasoningStart,
      reasoningEnd: reasoningEnd,
      sessionVars: sessionVars ?? this.sessionVars,
      globalVars: globalVars ?? this.globalVars,
      charId: charId,
      sessionId: sessionId,
    );
  }
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

  result = result.replaceAllMapped(
    RegExp(r'\{\{char\}\}', caseSensitive: false),
    (_) => ctx.charName,
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{description\}\}', caseSensitive: false),
    (_) => ctx.charDescription ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{scenario\}\}', caseSensitive: false),
    (_) => ctx.charScenario ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{personality\}\}', caseSensitive: false),
    (_) => ctx.charPersonality ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{mesExamples\}\}', caseSensitive: false),
    (_) => ctx.charMesExample ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{user\}\}', caseSensitive: false),
    (_) => ctx.userName,
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{persona\}\}', caseSensitive: false),
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
    (_) => ctx.reasoningStart ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{reasoningSuffix\}\}', caseSensitive: false),
    (_) => ctx.reasoningEnd ?? '',
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{setvar::([\s\S]*?)::([\s\S]*?)\}\}', caseSensitive: false),
    (m) {
      final name = m.group(1)!.trim();
      final value = m.group(2)!.trim();
      sessionVars[name] = value;
      varsChanged = true;
      return '';
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{setglobalvar::([\s\S]*?)::([\s\S]*?)\}\}', caseSensitive: false),
    (m) {
      final name = m.group(1)!.trim();
      final value = m.group(2)!.trim();
      globalVars[name] = value;
      varsChanged = true;
      return '';
    },
  );

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
      final seed = '${ctx.charId}_${ctx.sessionId}_pick_${m.group(0)}';
      final hash = _simpleHash(seed);
      return parts[hash % parts.length];
    },
  );

  result = result.replaceAllMapped(
    RegExp(r'\{\{roll::(.*?)\}\}', caseSensitive: false),
    (m) {
      return _rollDice(m.group(1)!).toString();
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
    hash = ((hash << 5) - hash + input.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash;
}

int _rollDice(String spec) {
  final match = RegExp(r'(\d+)d(\d+)', caseSensitive: false).firstMatch(spec);
  if (match == null) return 0;
  final count = int.parse(match.group(1)!);
  final sides = int.parse(match.group(2)!);
  final random = Random();
  var total = 0;
  for (var i = 0; i < count; i++) {
    total += random.nextInt(sides) + 1;
  }
  return total;
}
