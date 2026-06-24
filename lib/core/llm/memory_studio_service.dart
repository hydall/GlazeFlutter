import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../models/studio_config.dart';
import '../state/db_provider.dart';
import '../../features/settings/api_list_provider.dart';
import 'memory_studio_mode.dart';
import 'prompt_builder.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';

/// Session-bound Studio pipeline.
///
/// The Studio menu stores a user-editable [StudioConfig]. At generation time
/// this service runs enabled agents in order. Intermediate agents produce
/// compact briefs; the last enabled agent produces the actual RP response.
class MemoryStudioService {
  final Ref _ref;

  MemoryStudioService(this._ref);

  Future<StudioConfig?> getEnabledConfig(String sessionId) async {
    final config = await _ref.read(studioConfigRepoProvider).getBySessionId(
          sessionId,
        );
    if (config == null || !config.enabled) return null;
    final enabledAgents = config.agents.where((a) => a.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (enabledAgents.isEmpty) return null;
    return config.copyWith(agents: enabledAgents);
  }

  /// Run configured Studio agents. Returns the final response + agent briefs.
  Future<StudioPipelineResult> runPipeline({
    required StudioConfig config,
    required PromptResult promptResult,
    required ApiConfig apiConfig,
    required String sessionId,
    CancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const StudioPipelineResult(status: 'aborted', response: '');
    }

    try {
      final agents = config.agents.where((a) => a.enabled).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (agents.isEmpty) {
        return const StudioPipelineResult(status: 'disabled', response: '');
      }

      final briefs = <StudioStageBrief>[];
      for (var i = 0; i < agents.length; i++) {
        if (token.isCancelled) {
          return const StudioPipelineResult(status: 'aborted', response: '');
        }
        final agent = agents[i];
        final isFinal = i == agents.length - 1;
        final text = await _runAgent(
          agent: agent,
          promptResult: promptResult,
          apiConfig: apiConfig,
          priorBriefs: briefs,
          sessionId: sessionId,
          cancelToken: token,
          isFinalResponse: isFinal,
        );
        if (token.isCancelled) {
          return const StudioPipelineResult(status: 'aborted', response: '');
        }

        if (isFinal) {
          return StudioPipelineResult(
            status: 'ok',
            response: text,
            stageBriefs: briefs,
          );
        }

        briefs.add(
          StudioStageBrief(
            agentId: agent.id,
            agentName: agent.name,
            brief: text,
            disposition: MemoryStudioOutputDisposition.ephemeral,
          ),
        );
      }

      return const StudioPipelineResult(status: 'disabled', response: '');
    } on TimeoutException {
      return const StudioPipelineResult(status: 'timeout', response: '');
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      return StudioPipelineResult(status: 'error', response: '', error: '$e');
    }
  }

  Future<String> _runAgent({
    required StudioAgent agent,
    required PromptResult promptResult,
    required ApiConfig apiConfig,
    required List<StudioStageBrief> priorBriefs,
    required String sessionId,
    required CancelToken cancelToken,
    required bool isFinalResponse,
  }) async {
    final resolved = await _resolveAgentConfig(agent, apiConfig);
    if (resolved.endpoint.isEmpty || resolved.model.isEmpty) {
      throw Exception('Studio agent "${agent.name}" API is not configured');
    }

    final completer = Completer<String>();
    final transport = pickChatTransport(resolved.protocol);
    final messages = _buildAgentMessages(
      agent: agent,
      promptResult: promptResult,
      priorBriefs: priorBriefs,
      isFinalResponse: isFinalResponse,
    );

    unawaited(transport.stream(
      request: ChatTransportRequest(
        endpoint: resolved.endpoint,
        apiKey: resolved.apiKey,
        model: resolved.model,
        messages: messages,
        maxTokens: agent.maxTokens,
        temperature: agent.temperature,
        topP: resolved.topP,
        topK: resolved.topK,
        frequencyPenalty: resolved.frequencyPenalty,
        presencePenalty: resolved.presencePenalty,
        stream: false,
        requestReasoning: false,
        omitTemperature: resolved.omitTemperature,
        omitTopP: resolved.omitTopP,
        omitReasoning: true,
        omitReasoningEffort: true,
        sessionId: sessionId,
        cacheControlTtl: resolved.cacheControlTtl,
        cacheBreakpointMode: resolved.cacheBreakpointMode,
        sessionIdMode: resolved.sessionIdMode,
      ),
      cancelToken: cancelToken,
      onComplete: (text, _, {rawResponseJson}) {
        if (!completer.isCompleted) completer.complete(text.trim());
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    ));

    return completer.future.timeout(
      Duration(milliseconds: agent.timeoutMs.clamp(1000, 120000)),
    );
  }

  Future<_ResolvedAgentConfig> _resolveAgentConfig(
    StudioAgent agent,
    ApiConfig current,
  ) async {
    if (agent.modelSource == 'custom') {
      return _ResolvedAgentConfig(
        endpoint: agent.endpoint,
        apiKey: current.apiKey,
        model: agent.model,
        protocol: LlmProtocol.openai,
      );
    }

    await _ref.read(apiListProvider.future);
    final active = _ref.read(activeApiConfigProvider) ?? current;
    return _ResolvedAgentConfig.fromApiConfig(active);
  }

  List<Map<String, dynamic>> _buildAgentMessages({
    required StudioAgent agent,
    required PromptResult promptResult,
    required List<StudioStageBrief> priorBriefs,
    required bool isFinalResponse,
  }) {
    final baseMessages = promptResult.messages
        .where((m) => m.content.trim().isNotEmpty)
        .map((m) => m.toApiMap())
        .toList();
    final briefText = priorBriefs
        .map((b) => '${b.agentName}:\n${b.brief}')
        .join('\n\n---\n\n');

    final control = StringBuffer()
      ..writeln(agent.promptShard.trim())
      ..writeln()
      ..writeln(isFinalResponse
          ? 'You are the final responder. Produce only the in-character RP response.'
          : 'You are an intermediate Studio agent. Produce a compact brief for later agents. Do not write the final RP response.');
    if (briefText.isNotEmpty) {
      control
        ..writeln()
        ..writeln('Prior Studio briefs:')
        ..writeln(briefText);
    }

    return [
      {'role': _normalizeRole(agent.role), 'content': control.toString()},
      ...baseMessages,
    ];
  }

  String _normalizeRole(String role) {
    const allowed = {'system', 'user', 'assistant'};
    return allowed.contains(role) ? role : 'system';
  }
}

class _ResolvedAgentConfig {
  final String endpoint;
  final String apiKey;
  final String model;
  final String protocol;
  final double topP;
  final int topK;
  final double frequencyPenalty;
  final double presencePenalty;
  final bool omitTemperature;
  final bool omitTopP;
  final String cacheControlTtl;
  final String cacheBreakpointMode;
  final String sessionIdMode;

  const _ResolvedAgentConfig({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.protocol,
    this.topP = 1.0,
    this.topK = 0,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.omitTemperature = false,
    this.omitTopP = false,
    this.cacheControlTtl = 'off',
    this.cacheBreakpointMode = 'depth',
    this.sessionIdMode = 'openrouter',
  });

  factory _ResolvedAgentConfig.fromApiConfig(ApiConfig config) {
    return _ResolvedAgentConfig(
      endpoint: config.endpoint,
      apiKey: config.apiKey,
      model: config.model,
      protocol: config.protocol,
      topP: config.topP,
      topK: config.topK,
      frequencyPenalty: config.frequencyPenalty,
      presencePenalty: config.presencePenalty,
      omitTemperature: config.omitTemperature,
      omitTopP: config.omitTopP,
      cacheControlTtl: config.cacheControlTtl,
      cacheBreakpointMode: config.cacheBreakpointMode,
      sessionIdMode: config.sessionIdMode,
    );
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
  final String agentId;
  final String agentName;
  final String brief;
  final MemoryStudioOutputDisposition disposition;

  const StudioStageBrief({
    required this.agentId,
    required this.agentName,
    required this.brief,
    required this.disposition,
  });
}
