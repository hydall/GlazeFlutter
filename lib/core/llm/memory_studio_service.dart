import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory_book.dart';
import 'memory_selector.dart';
import 'memory_studio_mode.dart';
import 'prompt_block_router.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';
import '../state/memory_settings_provider.dart';
import '../../features/settings/api_list_provider.dart';

/// Studio Mode pipeline service (Phase 11).
///
/// Multi-stage / multi-agent RP pipeline. Explicit opt-in only.
/// Pipeline: memoryCurator → scenarioWriter → director → mainResponder
///
/// Each stage receives only the preset shards it needs + compact briefs
/// from earlier stages. The final responder is the only stage that produces
/// the actual RP response.
///
/// All intermediate activity is ephemeral (not persisted) by default.
/// Proposed writes require explicit user confirmation.
class MemoryStudioService {
  final Ref _ref;

  MemoryStudioService(this._ref);

  /// Run the Studio pipeline. Returns the final response + stage briefs.
  Future<StudioPipelineResult> runPipeline({
    required MemoryBookSettings settings,
    required String currentText,
    required List<MemoryEntry> memoryEntries,
    required MemorySelection memorySelection,
    required Set<String> visibleMessageIds,
    required List<PresetBlockInfo> presetBlocks,
    required String charName,
    required String charDescription,
    required String userName,
    required String personaPrompt,
    CancelToken? cancelToken,
  }) async {
    const policy = MemoryStudioPolicy(MemoryStudioSettings(
      experimentalEnabled: true,
    ));
    if (!policy.isAvailable) {
      return StudioPipelineResult(
        status: 'disabled',
        response: '',
      );
    }

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return StudioPipelineResult(status: 'aborted', response: '');
    }

    try {
      final pipeline = policy.defaultPipeline();
      final briefs = <StudioStageBrief>[];

      // Memory context for the pipeline
      final memoryContext = memorySelection.entries
          .map((e) => '--- ${e.title} ---\n${e.content}')
          .join('\n\n');

      // Stage 1: Memory Curator
      if (pipeline.any((p) => p.stage == StudioStage.memoryCurator)) {
        final curatorShards = PromptBlockRouter.filterForStage(
          StudioStage.memoryCurator,
          presetBlocks,
        );
        final curatorBrief = await _runStage(
          stage: StudioStage.memoryCurator,
          settings: settings,
          prompt: _buildCuratorPrompt(
            currentText: currentText,
            memoryContext: memoryContext,
            shards: curatorShards,
            charName: charName,
          ),
          cancelToken: token,
        );
        briefs.add(StudioStageBrief(
          stage: StudioStage.memoryCurator,
          brief: curatorBrief,
          disposition: MemoryStudioOutputDisposition.ephemeral,
        ));
      }

      // Stage 2: Scenario Writer
      if (pipeline.any((p) => p.stage == StudioStage.scenarioWriter)) {
        final scenarioShards = PromptBlockRouter.filterForStage(
          StudioStage.scenarioWriter,
          presetBlocks,
        );
        final curatorBrief = briefs
            .where((b) => b.stage == StudioStage.memoryCurator)
            .map((b) => b.brief)
            .join('\n');
        final scenarioBrief = await _runStage(
          stage: StudioStage.scenarioWriter,
          settings: settings,
          prompt: _buildScenarioPrompt(
            currentText: currentText,
            curatorBrief: curatorBrief,
            shards: scenarioShards,
            charName: charName,
          ),
          cancelToken: token,
        );
        briefs.add(StudioStageBrief(
          stage: StudioStage.scenarioWriter,
          brief: scenarioBrief,
          disposition: MemoryStudioOutputDisposition.ephemeral,
        ));
      }

      // Stage 3: Director
      if (pipeline.any((p) => p.stage == StudioStage.director)) {
        final directorShards = PromptBlockRouter.filterForStage(
          StudioStage.director,
          presetBlocks,
        );
        final priorBriefs = briefs.map((b) => '${b.stage.name}: ${b.brief}').join('\n');
        final directorBrief = await _runStage(
          stage: StudioStage.director,
          settings: settings,
          prompt: _buildDirectorPrompt(
            currentText: currentText,
            priorBriefs: priorBriefs,
            shards: directorShards,
            charName: charName,
          ),
          cancelToken: token,
        );
        briefs.add(StudioStageBrief(
          stage: StudioStage.director,
          brief: directorBrief,
          disposition: MemoryStudioOutputDisposition.ephemeral,
        ));
      }

      // Stage 4: Main Responder
      final responseShards = PromptBlockRouter.filterForStage(
        StudioStage.mainResponder,
        presetBlocks,
      );
      final allBriefs = briefs.map((b) => '${b.stage.name}: ${b.brief}').join('\n');
      final response = await _runStage(
        stage: StudioStage.mainResponder,
        settings: settings,
        prompt: _buildMainResponderPrompt(
          currentText: currentText,
          allBriefs: allBriefs,
          shards: responseShards,
          charName: charName,
          charDescription: charDescription,
          userName: userName,
          personaPrompt: personaPrompt,
        ),
        cancelToken: token,
        isFinalResponse: true,
      );

      return StudioPipelineResult(
        status: 'ok',
        response: response,
        stageBriefs: briefs,
      );
    } on TimeoutException {
      return StudioPipelineResult(
        status: 'timeout',
        response: '',
        stageBriefs: const [],
      );
    } catch (e) {
      if (token.isCancelled ||
          (e is DioException && CancelToken.isCancel(e))) {
        return StudioPipelineResult(status: 'aborted', response: '');
      }
      return StudioPipelineResult(
        status: 'error',
        response: '',
        error: '$e',
      );
    }
  }

  Future<String> _runStage({
    required StudioStage stage,
    required MemoryBookSettings settings,
    required String prompt,
    required CancelToken cancelToken,
    bool isFinalResponse = false,
  }) async {
    final isCustom = settings.sidecarSource == 'custom';
    String endpoint;
    String apiKey;
    String model;
    String protocol;

    if (isCustom) {
      endpoint = settings.sidecarEndpoint;
      apiKey = settings.sidecarApiKey;
      model = settings.sidecarModel;
      protocol = LlmProtocol.openai;
    } else {
      await _ref.read(apiListProvider.future);
      final chatConfig = _ref.read(activeApiConfigProvider);
      if (chatConfig == null) {
        throw Exception('No chat API config available for studio');
      }
      endpoint = chatConfig.endpoint ?? '';
      apiKey = chatConfig.apiKey ?? '';
      model = settings.sidecarModel.isNotEmpty
          ? settings.sidecarModel
          : (chatConfig.model ?? '');
      protocol = chatConfig.protocol;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Studio API not configured');
    }

    final completer = Completer<String>();
    final transport = pickChatTransport(protocol);

    transport.stream(
      request: ChatTransportRequest(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: isFinalResponse ? 2000 : 500,
        temperature: isFinalResponse ? 0.8 : 0.3,
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
    );

    return completer.future.timeout(
      Duration(milliseconds: settings.sidecarTimeoutMs * 3),
    );
  }

  String _buildCuratorPrompt({
    required String currentText,
    required String memoryContext,
    required List<PresetBlockShard> shards,
    required String charName,
  }) {
    final shardText = shards.isEmpty
        ? ''
        : '\n\nRelevant instructions:\n${shards.map((s) => s.content).join('\n')}';
    return '''You are a memory curator for an RP session with $charName.
Select and summarize the most relevant memories for the current scene.

User message: $currentText

Available memories:
$memoryContext$shardText

Provide a brief (2-3 sentence) summary of the most relevant memory context for this response. Focus on facts, promises, relationships, and unresolved threads.''';
  }

  String _buildScenarioPrompt({
    required String currentText,
    required String curatorBrief,
    required List<PresetBlockShard> shards,
    required String charName,
  }) {
    final shardText = shards.isEmpty
        ? ''
        : '\n\nRelevant instructions:\n${shards.map((s) => s.content).join('\n')}';
    return '''You are a scenario writer for an RP session with $charName.
Review the current scene and identify active arcs, obligations, and plot threads.

User message: $currentText

Memory curator's summary:
$curatorBrief$shardText

Provide a brief (2-3 sentence) summary of active arcs and what should happen next for continuity.''';
  }

  String _buildDirectorPrompt({
    required String currentText,
    required String priorBriefs,
    required List<PresetBlockShard> shards,
    required String charName,
  }) {
    final shardText = shards.isEmpty
        ? ''
        : '\n\nRelevant instructions:\n${shards.map((s) => s.content).join('\n')}';
    return '''You are a director for an RP session with $charName.
Plan the tone, pacing, and emotional continuity for the next response.

User message: $currentText

Stage briefs so far:
$priorBriefs$shardText

Provide a brief (2-3 sentence) direction for the response: tone, pacing, emotional beats, and continuity risks to avoid.''';
  }

  String _buildMainResponderPrompt({
    required String currentText,
    required String allBriefs,
    required List<PresetBlockShard> shards,
    required String charName,
    required String charDescription,
    required String userName,
    required String personaPrompt,
  }) {
    final shardText = shards.isEmpty
        ? ''
        : '\n\nRelevant instructions:\n${shards.map((s) => s.content).join('\n')}';
    return '''You are $charName responding to $userName in an RP session.

Character: $charName
Description: $charDescription
${personaPrompt.isNotEmpty ? "Persona ($userName): $personaPrompt" : ''}

Stage briefs:
$allBriefs$shardText

User message: $currentText

Write $charName's response. Stay in character. Follow the director's tone and pacing guidance. Maintain continuity with the memories and scenario briefs.''';
  }
}

class StudioPipelineResult {
  final String status;
  final String response;
  final List<StudioStageBrief> stageBriefs;
  final String? error;

  const StudioPipelineResult({
    required this.status,
    required this.response,
    this.stageBriefs = const [],
    this.error,
  });
}

class StudioStageBrief {
  final StudioStage stage;
  final String brief;
  final MemoryStudioOutputDisposition disposition;

  const StudioStageBrief({
    required this.stage,
    required this.brief,
    required this.disposition,
  });
}
