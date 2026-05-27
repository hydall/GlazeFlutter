import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';

import '../models/character.dart';
import '../models/persona.dart';
import '../models/preset.dart';
import '../models/chat_message.dart';
import '../models/api_config.dart';
import '../models/lorebook.dart';
import 'context_calculator.dart';
import 'glaze_matcher.dart';
import 'history_assembler.dart';
import 'lorebook_scanner.dart';
import 'prompt_builder.dart';
import 'prompt_inputs.dart';
import 'tokenizer.dart';

/// Long-lived isolate worker that runs buildPrompt off the main thread.
///
/// The isolate loads its own o200k_base tokenizer once at startup and
/// maintains a persistent token cache across requests.
class PromptWorker {
  static PromptWorker? _instance;

  final Isolate _isolate;
  final ReceivePort _commandPort;
  final ReceivePort _responsePort;
  final SendPort _sendPort;
  final Map<int, Completer<dynamic>> _pending = {};
  int _requestId = 0;

  PromptWorker._(this._isolate, this._commandPort, this._responsePort, this._sendPort);

  static Future<PromptWorker> ensureInitialized() async {
    if (_instance != null) return _instance!;
    _instance = await _create();
    return _instance!;
  }

  static Future<PromptWorker> _create() async {
    final dir = await getApplicationSupportDirectory();
    final appSupportPath = dir.path;

    final commandPort = ReceivePort();
    final responsePort = ReceivePort();

    final isolate = await Isolate.spawn(
      _isolateEntryPoint,
      [commandPort.sendPort, responsePort.sendPort, appSupportPath],
    );

    final sendPort = await commandPort.first as SendPort;

    final worker = PromptWorker._(isolate, commandPort, responsePort, sendPort);

    responsePort.listen((message) {
      if (message is List && message.length == 2) {
        final id = message[0] as int;
        final data = message[1];
        final completer = worker._pending.remove(id);
        if (completer != null) {
          if (data is Map && data.containsKey('error')) {
            completer.completeError(Exception(data['error'] as String));
          } else {
            completer.complete(data);
          }
        }
      }
    });

    await worker._send('init', null);
    debugPrint('[PromptWorker] Isolate ready with tokenizer loaded');

    return worker;
  }

  Future<dynamic> _send(String command, dynamic data) async {
    final id = _requestId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    _sendPort.send([id, command, data]);
    return completer.future;
  }

  Future<PromptResult> buildPrompt(PromptPayload payload) async {
    final json = jsonEncode(_serializePayload(payload));
    final response = await _send('buildPrompt', json) as String;
    return _deserializeResult(jsonDecode(response) as Map<String, dynamic>);
  }

  /// Builds a complete prompt from raw inputs. This runs memory injection,
  /// lorebook scanning, prompt assembly, and tokenization all in the isolate.
  Future<PromptResult> buildFromInputs(PromptInputs inputs) async {
    final json = jsonEncode(inputs.toJson());
    final response = await _send('buildFromInputs', json) as String;
    return _deserializeResult(jsonDecode(response) as Map<String, dynamic>);
  }

  void dispose() {
    _commandPort.close();
    _responsePort.close();
    _isolate.kill(priority: Isolate.immediate);
    _instance = null;
  }
}

// ---- Serialization (main thread side) ----

Map<String, dynamic> _serializePayload(PromptPayload p) => {
  'character': p.character.toJson(),
  'persona': p.persona?.toJson(),
  'preset': p.preset?.toJson(),
  'history': p.history.map((m) => m.toJson()).toList(),
  'apiConfig': p.apiConfig.toJson(),
  'sessionVars': p.sessionVars,
  'globalVars': p.globalVars,
  'summaryContent': p.summaryContent,
  'summaryPrefix': p.summaryPrefix,
  'memoryContent': p.memoryContent,
  'memoryMacroContent': p.memoryMacroContent,
  'memoryInjectionTarget': p.memoryInjectionTarget,
  'guidanceText': p.guidanceText,
  'lorebooks': p.lorebooks.map((l) => l.toJson()).toList(),
  'lorebookSettings': p.lorebookSettings.toJson(),
  'lorebookActivations': p.lorebookActivations.toJson(),
  'vectorEntries': p.vectorEntries.map((e) => e.toJson()).toList(),
  'authorsNote': p.authorsNote?.toJson(),
  'characterDepthPrompt': p.characterDepthPrompt,
  'characterDepthPromptDepth': p.characterDepthPromptDepth,
  'characterDepthPromptRole': p.characterDepthPromptRole,
  'memoryCoverage': p.memoryCoverage,
  'globalRegexes': p.globalRegexes.map((r) => r.toJson()).toList(),
  'preScannedEntries': p.preScannedEntries?.map((e) => e.toJson()).toList(),
  'triggeredMemories': p.triggeredMemories.map((t) => t.toJson()).toList(),
};

PromptResult _deserializeResult(Map<String, dynamic> json) {
  return PromptResult(
    messages: (json['messages'] as List).map((m) => PromptMessage.fromJson(m as Map<String, dynamic>)).toList(),
    breakdown: TokenBreakdown.fromJson(json['breakdown'] as Map<String, dynamic>),
    sessionVars: Map<String, String>.from(json['sessionVars'] as Map),
    globalVars: Map<String, String>.from(json['globalVars'] as Map),
    triggeredLorebooks: (json['triggeredLorebooks'] as List? ?? []).map((t) => TriggeredEntry.fromJson(t as Map<String, dynamic>)).toList(),
    triggeredMemories: (json['triggeredMemories'] as List? ?? []).map((t) => TriggeredEntry.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

// ---- Deserialization (isolate side) ----

PromptPayload _deserializePayload(Map<String, dynamic> json) {
  return PromptPayload(
    character: Character.fromJson(json['character'] as Map<String, dynamic>),
    persona: json['persona'] != null ? Persona.fromJson(json['persona'] as Map<String, dynamic>) : null,
    preset: json['preset'] != null ? Preset.fromJson(json['preset'] as Map<String, dynamic>) : null,
    history: (json['history'] as List).map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList(),
    apiConfig: ApiConfig.fromJson(json['apiConfig'] as Map<String, dynamic>),
    sessionVars: Map<String, String>.from(json['sessionVars'] as Map? ?? {}),
    globalVars: Map<String, String>.from(json['globalVars'] as Map? ?? {}),
    summaryContent: json['summaryContent'] as String?,
    summaryPrefix: json['summaryPrefix'] as String?,
    memoryContent: json['memoryContent'] as String?,
    memoryMacroContent: json['memoryMacroContent'] as String?,
    memoryInjectionTarget: json['memoryInjectionTarget'] as String? ?? 'summary_block',
    guidanceText: json['guidanceText'] as String?,
    lorebooks: (json['lorebooks'] as List).map((l) => Lorebook.fromJson(l as Map<String, dynamic>)).toList(),
    lorebookSettings: LorebookGlobalSettings.fromJson(json['lorebookSettings'] as Map<String, dynamic>),
    lorebookActivations: LorebookActivations.fromJson(json['lorebookActivations'] as Map<String, dynamic>),
    vectorEntries: (json['vectorEntries'] as List).map((e) => LorebookEntry.fromJson(e as Map<String, dynamic>)).toList(),
    authorsNote: json['authorsNote'] != null ? AuthorsNote.fromJson(json['authorsNote'] as Map<String, dynamic>) : null,
    characterDepthPrompt: json['characterDepthPrompt'] as String? ?? '',
    characterDepthPromptDepth: json['characterDepthPromptDepth'] as int? ?? 4,
    characterDepthPromptRole: json['characterDepthPromptRole'] as String? ?? 'system',
    memoryCoverage: Map<String, dynamic>.from(json['memoryCoverage'] as Map? ?? {}),
    globalRegexes: (json['globalRegexes'] as List).map((r) => PresetRegex.fromJson(r as Map<String, dynamic>)).toList(),
    preScannedEntries: json['preScannedEntries'] != null
        ? (json['preScannedEntries'] as List).map((e) => ScannedEntry.fromJson(e as Map<String, dynamic>)).toList()
        : null,
    triggeredMemories: (json['triggeredMemories'] as List? ?? []).map((t) => TriggeredEntry.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

Map<String, dynamic> _serializeResult(PromptResult r) => {
  'messages': r.messages.map((m) => m.toJson()).toList(),
  'breakdown': r.breakdown.toJson(),
  'sessionVars': r.sessionVars,
  'globalVars': r.globalVars,
  'triggeredLorebooks': r.triggeredLorebooks.map((t) => t.toJson()).toList(),
  'triggeredMemories': r.triggeredMemories.map((t) => t.toJson()).toList(),
};

// ---- Isolate entry point (top-level function) ----

void _isolateEntryPoint(List<dynamic> args) {
  final commandSendPort = args[0] as SendPort;
  final responseSendPort = args[1] as SendPort;
  final appSupportPath = args[2] as String;

  final commandPort = ReceivePort();
  commandSendPort.send(commandPort.sendPort);

  commandPort.listen((message) async {
    if (message is! List || message.length != 3) return;

    final id = message[0] as int;
    final command = message[1] as String;
    final data = message[2];

    try {
      switch (command) {
        case 'init':
          await preloadO200kBaseInIsolate(appSupportPath);
          responseSendPort.send([id, 'ok']);

        case 'buildPrompt':
          final payload = _deserializePayload(jsonDecode(data as String) as Map<String, dynamic>);
          final result = buildPrompt(payload);
          responseSendPort.send([id, jsonEncode(_serializeResult(result))]);

        case 'buildFromInputs':
          final inputs = PromptInputs.fromJson(jsonDecode(data as String) as Map<String, dynamic>);
          final result2 = _buildFromInputs(inputs);
          responseSendPort.send([id, jsonEncode(_serializeResult(result2))]);

        default:
          responseSendPort.send([id, {'error': 'Unknown command: $command'}]);
      }
    } catch (e, st) {
      responseSendPort.send([id, {'error': '$e\n$st'}]);
    }
  });
}

/// Builds a complete prompt from raw inputs in the isolate.
/// Performs memory keyword injection, lorebook scanning, and prompt assembly.
PromptResult _buildFromInputs(PromptInputs inputs) {
  // 1. Memory keyword injection (no vector search in isolate)
  String? memoryContent;
  String? memoryMacroContent;
  String memoryInjectionTarget = inputs.memoryInjectionTarget;
  List<TriggeredEntry> triggeredMemories = [];

  if (inputs.memoryEnabled && inputs.memoryEntries.isNotEmpty) {
    final historyText = inputs.history
        .where((m) => !m.isHidden && !m.isTyping)
        .map((m) => m.content)
        .join('\n');
    final scanText = historyText.toLowerCase();
    final keywordMatched = <String>{};

    for (final entry in inputs.memoryEntries) {
      if (entry.status != 'active' || entry.content.trim().isEmpty) continue;

      for (final key in entry.keys) {
        if (key.isEmpty) continue;
        if (inputs.memoryKeyMatchMode == 'glaze') {
          if (_glazeMatch(key, scanText)) keywordMatched.add(entry.id);
        } else if (inputs.memoryKeyMatchMode == 'both') {
          if (scanText.contains(key.toLowerCase()) || _glazeMatch(key, scanText)) {
            keywordMatched.add(entry.id);
          }
        } else {
          if (scanText.contains(key.toLowerCase())) keywordMatched.add(entry.id);
        }
      }
    }

    final scoredEntries = inputs.memoryEntries
        .where((e) => e.status == 'active' && e.content.trim().isNotEmpty)
        .map((entry) {
          var score = 0.0;
          if (keywordMatched.contains(entry.id)) score += 6;
          if (entry.messageIds.isNotEmpty) score += 2;
          score += entry.content.length > 20 ? 1 : 0;
          return (entry: entry, score: score);
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final topEntries = scoredEntries
        .where((item) => item.score > 0)
        .take(inputs.memoryMaxInjected)
        .map((item) => item.entry)
        .toList();

    if (topEntries.isNotEmpty) {
      final macroContent = topEntries.map((e) => e.content.trim()).join('\n\n');
      final contentParts = <String>[];
      if (inputs.summaryContent != null && inputs.summaryContent!.isNotEmpty) {
        contentParts.add('Summary excerpt:\n${inputs.summaryContent}');
      }
      contentParts.add('Memory context:');
      for (final entry in topEntries) {
        final title = entry.title.isNotEmpty ? entry.title : 'Memory';
        contentParts.add('- $title: ${entry.content.trim()}');
      }

      memoryContent = contentParts.join('\n\n');
      memoryMacroContent = macroContent;
      triggeredMemories = topEntries
          .map((e) => TriggeredEntry(
                id: e.id,
                name: e.title.isNotEmpty ? e.title : e.id,
                source: 'memory',
              ))
          .toList();
    }
  }

  // 2. Build payload
  final payload = PromptPayload(
    character: inputs.character,
    persona: inputs.persona,
    preset: inputs.preset,
    history: inputs.history,
    apiConfig: inputs.apiConfig,
    sessionVars: inputs.sessionVars,
    globalVars: inputs.globalVars,
    summaryContent: inputs.summaryContent,
    guidanceText: inputs.guidanceText,
    lorebooks: inputs.lorebooks,
    lorebookSettings: inputs.lorebookSettings,
    lorebookActivations: inputs.lorebookActivations,
    vectorEntries: inputs.vectorEntries,
    authorsNote: inputs.authorsNote,
    characterDepthPrompt: inputs.characterDepthPrompt,
    characterDepthPromptDepth: inputs.characterDepthPromptDepth,
    characterDepthPromptRole: inputs.characterDepthPromptRole,
    globalRegexes: inputs.globalRegexes,
    memoryContent: memoryContent,
    memoryMacroContent: memoryMacroContent,
    memoryInjectionTarget: memoryInjectionTarget,
    triggeredMemories: triggeredMemories,
  );

  // 3. Build prompt (lorebook scanning happens inside buildPrompt)
  return buildPrompt(payload);
}

bool _glazeMatch(String key, String text) {
  return glazeCheckMatch(key, text, false, WholeWordMode.glaze);
}
