import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';

import '../models/api_config.dart';
import '../models/preset.dart';
import '../models/studio_config.dart';
import '../utils/time_helpers.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';
import '../state/memory_settings_provider.dart';
import '../../features/settings/api_list_provider.dart';

/// LLM-powered preset decomposition service for Studio Mode.
///
/// Takes all enabled preset blocks and asks an LLM to decompose them into
/// agent tasks. Each agent gets:
/// - A name (e.g. "Memory Curator", "Director", "Main Responder")
/// - A role (system/user)
/// - A prompt shard (instructions extracted from the preset)
/// - A pipeline order
/// - The source block names it was derived from
///
/// The decomposition is cached per-session and only re-run when the preset
/// changes (detected via sourcePresetHash).
class StudioDecompositionService {
  final Ref _ref;

  StudioDecompositionService(this._ref);

  /// Decompose a preset into agent tasks.
  /// Returns a list of [StudioAgent]s ordered by pipeline execution order.
  Future<List<StudioAgent>> decompose({
    required Preset preset,
    required String sessionId,
    ApiConfig? apiConfig,
    CancelToken? cancelToken,
  }) async {
    final enabledBlocks = preset.blocks.where((b) => b.enabled).toList();
    if (enabledBlocks.isEmpty) return const [];
    final preservedMetaBlocks = _preservedMetaBlocks(enabledBlocks);
    final totalChars = enabledBlocks.fold<int>(
      0,
      (sum, b) => sum + b.content.length,
    );
    _log(
      'build start session=$sessionId preset="${preset.name}" '
      'blocks=${enabledBlocks.length} chars=$totalChars '
      'preservedMeta=${preservedMetaBlocks.length} '
      'model=${apiConfig?.model ?? '<active>'}',
    );

    // Build the blocks summary for the LLM
    final blocksSummary = enabledBlocks
        .asMap()
        .entries
        .map((entry) {
          final i = entry.key;
          final b = entry.value;
          final limit = _isPreservedMetaBlock(b) ? 6000 : 2500;
          final content = b.content.length > limit
              ? '${b.content.substring(0, limit)}...'
              : b.content;
          return 'Block $i: name="${b.name}" role="${b.role}" insertion="${b.insertionMode}"${b.depth != null ? ' depth=${b.depth}' : ''}\n$content';
        })
        .join('\n\n---\n\n');

    final prompt =
        '''You are a prompt engineering expert. Decompose the following RP preset blocks into a multi-agent pipeline.

Each agent will receive ONLY its assigned instructions plus compact memory context — never the full preset. The final agent produces the actual RP response.

Enabled preset blocks:
$blocksSummary

Create 3-6 agents. Respond with ONLY a JSON array (no markdown, no explanation):
[
  {
    "name": "Agent Name",
    "role": "system",
    "promptShard": "The instructions this agent should follow, extracted/compressed from the relevant preset blocks",
    "order": 0,
    "refreshPolicy": "turn",
    "invalidationSignals": ["scene_changed"],
    "sourceBlockNames": "block names this agent derives from"
  }
]

Rules:
- Agent with order 0 = memory/continuity curator (gets memory context)
- Last agent (highest order) = main responder (produces the RP response)
- Middle agents = directors, scenario writers, style enforcers
- Each agent's promptShard should be self-contained (2-5 sentences)
- Distribute preset blocks across agents — don't put everything on one agent
- System blocks (char_card, scenario, etc.) go to the main responder
- Jailbreak/content permission blocks go to the main responder
- CoT/quality control blocks (anti-loop, anti-echo, sensory) go to a director agent
- From CoT blocks, extract only enforceable quality/context policy. Never preserve hidden chain-of-thought instructions, <think> tags, or "plan internally then output after </think>" text.
- Genre/tone blocks go to a director or scenario agent
- Formatting blocks (HTML, comics, images) go to the main responder
- Variable blocks (setvar) go to the main responder
- Intermediate agents are fed into the final agent as context. They must produce compact operational briefs, not draft prose.
- Intermediate agents may include brief do/don't examples derived from the preset, but must never continue the current scene, write in-scene dialogue/actions, or produce the final RP response.
- Preserve named meta-agents, invisible directors, ghosts, companions, OOC interfaces, and operational checklists as explicit agent instructions. Do not collapse them to a one-line mention.
- If a block defines a named entity such as Lumia/Ghost in the Machine, one agent promptShard must retain its name, nature, silent-operation rules, OOC interface, and non-exposure rules.
- For every intermediate agent, assign refreshPolicy conservatively:
  - "static" = reusable until preset/profile/card/settings change; use for banlists, fixed formatting policy, stable style rules.
  - "scene" = reusable while location, active cast, scene goal, conflict, relationship state, and tone remain stable; use for scene-level directors.
  - "turn" = must rerun every user turn; use for continuity, recent history, anti-loop, user-message-sensitive checks, and the final responder.
- If uncertain, choose "turn". Include short invalidationSignals such as "preset_changed", "scene_changed", "active_cast_changed", "tone_changed", "last_3_replies_changed".''';

    final String? raw;
    try {
      raw = await _callLlm(
        prompt,
        apiConfig: apiConfig,
        cancelToken: cancelToken,
      );
    } on TimeoutException {
      _log('build timeout session=$sessionId; using fallback agents');
      return _fallbackAgents(enabledBlocks, preservedMetaBlocks, sessionId);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return const [];
      rethrow;
    }
    if (raw == null) {
      _log('build returned null session=$sessionId; using fallback agents');
      return _fallbackAgents(enabledBlocks, preservedMetaBlocks, sessionId);
    }
    _log('build raw complete session=$sessionId chars=${raw.length}');

    final decoded = _decodeAgentList(raw);
    if (decoded == null) {
      _log('build invalid JSON session=$sessionId; using fallback agents');
      return _fallbackAgents(enabledBlocks, preservedMetaBlocks, sessionId);
    }

    final now = currentTimestampSeconds();
    final agents = <StudioAgent>[];
    for (var i = 0; i < decoded.length; i++) {
      final rawItem = decoded[i];
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      agents.add(
        StudioAgent(
          id: 'agent_${sessionId}_${i}_$now',
          name: _stringField(item['name'], fallback: 'Agent $i'),
          role: _stringField(item['role'], fallback: 'system'),
          promptShard: _stringField(item['promptShard']),
          order: _intField(item['order'], fallback: i),
          enabled: true,
          sourceBlockNames: _stringField(item['sourceBlockNames']),
          modelSource: 'current',
          temperature: i == decoded.length - 1 ? 0.8 : 0.3,
          maxTokens: 8000,
          timeoutMs: i == decoded.length - 1 ? 90000 : 60000,
          refreshPolicy: i == decoded.length - 1
              ? 'turn'
              : _refreshPolicyField(item['refreshPolicy']),
          invalidationSignals: _stringListField(item['invalidationSignals']),
        ),
      );
    }

    if (agents.isEmpty) {
      _log('build decoded no agents session=$sessionId; using fallback agents');
      return _fallbackAgents(enabledBlocks, preservedMetaBlocks, sessionId);
    }

    agents.sort((a, b) => a.order.compareTo(b.order));
    final result = _normalizeStudioAgents(
      _applyPreservedMetaBlocks(agents, preservedMetaBlocks, sessionId, now),
    );
    _log('build complete session=$sessionId agents=${result.length}');
    return result;
  }

  List<dynamic>? _decodeAgentList(String raw) {
    final candidates = <String>{raw.trim(), ..._jsonPayloadCandidates(raw)};

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['agents'] is List) {
          return decoded['agents'] as List<dynamic>;
        }
      } on FormatException {
        // Try the next candidate. Some providers wrap JSON in prose/markdown.
      }
    }
    return null;
  }

  Iterable<String> _jsonPayloadCandidates(String raw) sync* {
    final trimmed = raw.trim();
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (fenced != null) yield fenced.group(1)!.trim();

    final arrayStart = trimmed.indexOf('[');
    final arrayEnd = trimmed.lastIndexOf(']');
    if (arrayStart >= 0 && arrayEnd > arrayStart) {
      yield trimmed.substring(arrayStart, arrayEnd + 1).trim();
    }

    final objectStart = trimmed.indexOf('{');
    final objectEnd = trimmed.lastIndexOf('}');
    if (objectStart >= 0 && objectEnd > objectStart) {
      yield trimmed.substring(objectStart, objectEnd + 1).trim();
    }
  }

  String _stringField(dynamic value, {String fallback = ''}) {
    if (value is String) return value.trim();
    if (value is Iterable) {
      return value
          .map((v) => v.toString().trim())
          .where((v) => v.isNotEmpty)
          .join(', ');
    }
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  int _intField(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  String _refreshPolicyField(dynamic value) {
    final text = _stringField(value).toLowerCase();
    return switch (text) {
      'static' || 'scene' || 'turn' => text,
      _ => 'turn',
    };
  }

  List<String> _stringListField(dynamic value) {
    if (value is Iterable) {
      return value
          .map((v) => v.toString().trim())
          .where((v) => v.isNotEmpty)
          .toList(growable: false);
    }
    final text = _stringField(value);
    if (text.isEmpty) return const [];
    return text
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList(growable: false);
  }

  List<StudioAgent> _fallbackAgents(
    List<PresetBlock> enabledBlocks,
    List<({String name, String role, String content})> preservedMetaBlocks,
    String sessionId,
  ) {
    final now = currentTimestampSeconds();
    final systemBlocks = enabledBlocks
        .where((b) => b.role.toLowerCase() == 'system')
        .map((b) => b.name)
        .where((name) => name.trim().isNotEmpty)
        .join(', ');
    final otherBlocks = enabledBlocks
        .where((b) => b.role.toLowerCase() != 'system')
        .map((b) => b.name)
        .where((name) => name.trim().isNotEmpty)
        .join(', ');
    final agents = <StudioAgent>[
      StudioAgent(
        id: 'agent_${sessionId}_fallback_memory_$now',
        name: 'Memory Curator',
        role: 'system',
        promptShard:
            'Review memory context and recent chat. Produce a concise continuity brief with facts, unresolved threads, emotional state, and constraints relevant to the next reply.',
        order: 0,
        enabled: true,
        modelSource: 'current',
        temperature: 0.3,
        maxTokens: 8000,
        timeoutMs: 60000,
        sourceBlockNames: otherBlocks,
        refreshPolicy: 'turn',
        invalidationSignals: const ['last_user_message_changed'],
      ),
      StudioAgent(
        id: 'agent_${sessionId}_fallback_director_$now',
        name: 'Scene Director',
        role: 'system',
        promptShard:
            'Extract and enforce tone, genre, pacing, formatting, safety-permission, anti-loop, and quality-control instructions from the preset. Produce only actionable guidance for the final responder.',
        order: 1,
        enabled: true,
        modelSource: 'current',
        temperature: 0.3,
        maxTokens: 8000,
        timeoutMs: 60000,
        sourceBlockNames: enabledBlocks.map((b) => b.name).join(', '),
        refreshPolicy: 'scene',
        invalidationSignals: const ['scene_changed', 'tone_changed'],
      ),
      StudioAgent(
        id: 'agent_${sessionId}_fallback_responder_$now',
        name: 'Main Responder',
        role: 'system',
        promptShard:
            'Write the final RP response using the full assembled chat prompt, character/scenario instructions, memory brief, and prior Studio agent briefs. Preserve character voice, formatting requirements, and narrative constraints.',
        order: 2,
        enabled: true,
        modelSource: 'current',
        temperature: 0.8,
        maxTokens: 8000,
        timeoutMs: 90000,
        sourceBlockNames: systemBlocks,
        refreshPolicy: 'turn',
      ),
    ];

    return _normalizeStudioAgents(
      _applyPreservedMetaBlocks(agents, preservedMetaBlocks, sessionId, now),
    );
  }

  List<({String name, String role, String content})> _preservedMetaBlocks(
    List<PresetBlock> blocks,
  ) {
    return blocks
        .where(_isPreservedMetaBlock)
        .map(
          (b) => (
            name: b.name.trim().isNotEmpty ? b.name.trim() : 'Meta Policy',
            role: b.role,
            content: b.content.trim(),
          ),
        )
        .where((b) => b.content.isNotEmpty)
        .toList(growable: false);
  }

  bool _isPreservedMetaBlock(PresetBlock block) {
    final haystack = '${block.name}\n${block.content}'.toLowerCase();
    const markers = [
      'lumia',
      'ghost in the machine',
      'meta-weaver',
      'silent operation',
      'ooc interface',
      'invisible meta',
    ];
    return markers.any((marker) => haystack.contains(marker));
  }

  List<StudioAgent> _applyPreservedMetaBlocks(
    List<StudioAgent> agents,
    List<({String name, String role, String content})> preservedBlocks,
    String sessionId,
    int now,
  ) {
    if (preservedBlocks.isEmpty) return agents;
    final updated = agents.toList(growable: true);

    for (var i = 0; i < preservedBlocks.length; i++) {
      final block = preservedBlocks[i];
      final marker = _identityMarker(block.name, block.content);
      final preservedText =
          'Preserved named meta-policy block: ${block.name}\n${block.content}';
      final targetIndex = updated.indexWhere((a) {
        final text = '${a.name}\n${a.promptShard}'.toLowerCase();
        return text.contains(marker);
      });

      if (targetIndex >= 0) {
        final target = updated[targetIndex];
        if (!target.promptShard.toLowerCase().contains(
          block.content.toLowerCase(),
        )) {
          updated[targetIndex] = target.copyWith(
            promptShard: '${target.promptShard.trim()}\n\n$preservedText',
            sourceBlockNames: _appendSourceName(
              target.sourceBlockNames,
              block.name,
            ),
          );
        }
        continue;
      }

      final insertIndex = updated.isEmpty ? 0 : updated.length - 1;
      updated.insert(
        insertIndex,
        StudioAgent(
          id: 'agent_${sessionId}_preserved_${i}_$now',
          name: block.name,
          role: block.role.isNotEmpty ? block.role : 'system',
          promptShard: preservedText,
          enabled: true,
          modelSource: 'current',
          temperature: 0.3,
          maxTokens: 8000,
          sourceBlockNames: block.name,
        ),
      );
    }

    return [
      for (var i = 0; i < updated.length; i++) updated[i].copyWith(order: i),
    ];
  }

  List<StudioAgent> _normalizeStudioAgents(List<StudioAgent> agents) {
    if (agents.isEmpty) return agents;
    final ordered = agents.toList()..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < ordered.length; i++)
        _normalizeStudioAgent(ordered[i], isFinal: i == ordered.length - 1),
    ];
  }

  StudioAgent _normalizeStudioAgent(
    StudioAgent agent, {
    required bool isFinal,
  }) {
    var prompt = _stripPromptLevelReasoning(agent.promptShard);
    prompt = isFinal
        ? _appendSentence(prompt, _finalResponderGuard)
        : _appendSentence(prompt, _intermediateBriefGuard);

    return agent.copyWith(
      promptShard: prompt,
      sourceBlockNames: _stripReasoningSourceNames(agent.sourceBlockNames),
    );
  }

  String _stripPromptLevelReasoning(String text) {
    var result = text;
    final patterns = <RegExp>[
      RegExp(
        r'\s*Plan internally[^.]*<think>[\s\S]*?(?:after\s*</think>|</think>)[^.]*\. ?',
        caseSensitive: false,
      ),
      RegExp(
        r'\s*Think internally[^.]*<think>[\s\S]*?(?:after\s*</think>|</think>)[^.]*\. ?',
        caseSensitive: false,
      ),
      RegExp(
        r'\s*Use\s+<think>[\s\S]*?</think>\s*(?:for|to)[^.]*\. ?',
        caseSensitive: false,
      ),
      RegExp(
        r'\s*## Language Rule\s*- The hidden <think>[\s\S]*?(?:usually Russian\.|$)',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      result = result.replaceAll(pattern, ' ');
    }
    return result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  String _stripReasoningSourceNames(String text) {
    return text
        .replaceAll(RegExp(r',?\s*Block \d+ \(CoT Gemini think template\)'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  String _appendSentence(String text, String sentence) {
    if (text.toLowerCase().contains(sentence.toLowerCase())) return text;
    if (text.trim().isEmpty) return sentence;
    return '${text.trim()} $sentence';
  }

  static const _intermediateBriefGuard =
      "When giving style guidance, you may include brief do/don't examples derived from the user's preset, but never draft or continue the current scene, never write in-scene dialogue/actions as if it were the final reply, and never output hidden reasoning.";

  static const _finalResponderGuard =
      'Do not output or request hidden reasoning blocks; generate only the final visible reply.';

  String _identityMarker(String name, String content) {
    final text = '$name\n$content'.toLowerCase();
    if (text.contains('lumia')) return 'lumia';
    if (text.contains('ghost in the machine')) return 'ghost in the machine';
    if (text.contains('meta-weaver')) return 'meta-weaver';
    return name
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .firstWhere((w) => w.length > 3, orElse: () => name.toLowerCase());
  }

  String _appendSourceName(String existing, String name) {
    if (existing.toLowerCase().contains(name.toLowerCase())) return existing;
    if (existing.trim().isEmpty) return name;
    return '$existing, $name';
  }

  /// Compute a hash of enabled blocks to detect preset changes.
  static String computePresetHash(List<PresetBlock> blocks) {
    final input = blocks
        .map((b) {
          return jsonEncode({
            'id': b.id,
            'name': b.name,
            'enabled': b.enabled,
            'role': b.role,
            'insertionMode': b.insertionMode,
            'depth': b.depth,
            'content': b.content,
          });
        })
        .join('\n');
    return sha1.convert(utf8.encode(input)).toString();
  }

  Future<String?> _callLlm(
    String prompt, {
    ApiConfig? apiConfig,
    CancelToken? cancelToken,
  }) async {
    final settings = _ref.read(memoryGlobalSettingsProvider);
    final isCustom = settings.sidecarSource == 'custom';
    String endpoint;
    String apiKey;
    String model;
    String protocol;

    if (apiConfig != null) {
      endpoint = apiConfig.endpoint;
      apiKey = apiConfig.apiKey;
      model = apiConfig.model;
      protocol = apiConfig.protocol;
    } else if (isCustom) {
      endpoint = settings.sidecarEndpoint;
      apiKey = settings.sidecarApiKey;
      model = settings.sidecarModel;
      protocol = LlmProtocol.openai;
    } else {
      await _ref.read(apiListProvider.future);
      final chatConfig = _ref.read(activeApiConfigProvider);
      if (chatConfig == null) {
        throw Exception(
          'No chat API config available for studio decomposition',
        );
      }
      endpoint = chatConfig.endpoint;
      apiKey = chatConfig.apiKey;
      model = settings.sidecarModel.isNotEmpty
          ? settings.sidecarModel
          : chatConfig.model;
      protocol = chatConfig.protocol;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Studio decomposition API not configured');
    }

    final completer = Completer<String>();
    final transport = pickChatTransport(protocol);

    unawaited(
      transport.stream(
        request: ChatTransportRequest(
          endpoint: endpoint,
          apiKey: apiKey,
          model: model,
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          maxTokens: 4000,
          temperature: 0.3,
          topP: 1.0,
          stream: false,
        ),
        cancelToken: cancelToken,
        onComplete: (text, _, {rawResponseJson}) {
          if (!completer.isCompleted) completer.complete(text);
        },
        onError: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );

    return completer.future.timeout(const Duration(seconds: 90));
  }

  void _log(String message) {
    debugPrint('[StudioBuild] $message');
  }
}
