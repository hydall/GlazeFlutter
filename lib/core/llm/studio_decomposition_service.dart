import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
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
- Genre/tone blocks go to a director or scenario agent
- Formatting blocks (HTML, comics, images) go to the main responder
- Variable blocks (setvar) go to the main responder
- Preserve named meta-agents, invisible directors, ghosts, companions, OOC interfaces, and operational checklists as explicit agent instructions. Do not collapse them to a one-line mention.
- If a block defines a named entity such as Lumia/Ghost in the Machine, one agent promptShard must retain its name, nature, silent-operation rules, OOC interface, and non-exposure rules.''';

    final raw = await _callLlm(
      prompt,
      apiConfig: apiConfig,
      cancelToken: cancelToken,
    );
    if (raw == null) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    final now = currentTimestampSeconds();
    final agents = <StudioAgent>[];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i] as Map<String, dynamic>;
      agents.add(
        StudioAgent(
          id: 'agent_${sessionId}_${i}_$now',
          name: (item['name'] as String?) ?? 'Agent $i',
          role: (item['role'] as String?) ?? 'system',
          promptShard: (item['promptShard'] as String?) ?? '',
          order: (item['order'] as int?) ?? i,
          enabled: true,
          sourceBlockNames: (item['sourceBlockNames'] as String?) ?? '',
          modelSource: 'current',
          temperature: i == decoded.length - 1 ? 0.8 : 0.3,
          maxTokens: i == decoded.length - 1 ? 2000 : 500,
        ),
      );
    }

    agents.sort((a, b) => a.order.compareTo(b.order));
    return _applyPreservedMetaBlocks(
      agents,
      preservedMetaBlocks,
      sessionId,
      now,
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
          maxTokens: 800,
          sourceBlockNames: block.name,
        ),
      );
    }

    return [
      for (var i = 0; i < updated.length; i++) updated[i].copyWith(order: i),
    ];
  }

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
          maxTokens: 2000,
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

    return completer.future.timeout(const Duration(seconds: 30));
  }
}
