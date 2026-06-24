import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/api_config.dart';
import '../models/studio_config.dart';
import '../state/db_provider.dart';
import '../../features/settings/api_list_provider.dart';
import 'memory_studio_mode.dart';
import 'prompt_builder.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';

final studioRuntimeStateProvider = StateProvider<StudioRuntimeState>(
  (_) => const StudioRuntimeState.idle(),
);

class StudioRuntimeState {
  final String? sessionId;
  final String? agentId;
  final String? agentName;
  final int index;
  final int total;
  final bool canFinishAgent;

  const StudioRuntimeState({
    required this.sessionId,
    required this.agentId,
    required this.agentName,
    required this.index,
    required this.total,
    required this.canFinishAgent,
  });

  const StudioRuntimeState.idle()
    : sessionId = null,
      agentId = null,
      agentName = null,
      index = 0,
      total = 0,
      canFinishAgent = false;
}

/// Session-bound Studio pipeline.
///
/// The Studio menu stores a user-editable [StudioConfig]. At generation time
/// this service runs enabled agents in order. Intermediate agents produce
/// compact briefs; the last enabled agent produces the actual RP response.
class MemoryStudioService {
  final Ref _ref;
  Completer<void>? _finishCurrentAgent;

  MemoryStudioService(this._ref);

  void finishCurrentAgent() {
    final completer = _finishCurrentAgent;
    if (completer == null || completer.isCompleted) {
      _log('finish current agent ignored: no active agent');
      return;
    }
    _log('finish current agent requested');
    completer.complete();
  }

  Future<StudioConfig?> getEnabledConfig(String sessionId) async {
    _log('load config session=$sessionId');
    final config = await _ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    if (config == null) {
      _log('config missing session=$sessionId');
      return null;
    }
    if (!config.enabled) {
      _log('config disabled session=$sessionId agents=${config.agents.length}');
      return null;
    }
    final enabledAgents = config.agents.where((a) => a.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (enabledAgents.isEmpty) {
      _log('config has no enabled agents session=$sessionId');
      return null;
    }
    _log(
      'config enabled session=$sessionId agents=${enabledAgents.length} '
      'runApi=${config.runApiConfigId.isEmpty ? '<active>' : config.runApiConfigId}',
    );
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
        _log('pipeline disabled: no enabled agents session=$sessionId');
        return const StudioPipelineResult(status: 'disabled', response: '');
      }

      _log(
        'pipeline start session=$sessionId agents=${agents.length} '
        'baseMessages=${promptResult.messages.length}',
      );

      final briefs = <StudioStageBrief>[];
      for (var i = 0; i < agents.length; i++) {
        if (token.isCancelled) {
          _log('pipeline aborted before agent index=$i session=$sessionId');
          return const StudioPipelineResult(status: 'aborted', response: '');
        }
        final agent = agents[i];
        final isFinal = i == agents.length - 1;
        _ref
            .read(studioRuntimeStateProvider.notifier)
            .state = StudioRuntimeState(
          sessionId: sessionId,
          agentId: agent.id,
          agentName: agent.name,
          index: i,
          total: agents.length,
          canFinishAgent: true,
        );
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
          _log(
            'pipeline aborted after agent="${agent.name}" session=$sessionId',
          );
          return const StudioPipelineResult(status: 'aborted', response: '');
        }

        if (isFinal) {
          _log(
            'pipeline complete session=$sessionId finalAgent="${agent.name}" '
            'chars=${text.length} briefs=${briefs.length}',
          );
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
        _log(
          'brief stored session=$sessionId agent="${agent.name}" '
          'chars=${text.length} briefs=${briefs.length}',
        );
      }

      _log('pipeline disabled: loop ended session=$sessionId');
      return const StudioPipelineResult(status: 'disabled', response: '');
    } on TimeoutException catch (e) {
      _log('pipeline timeout session=$sessionId error=${e.message}');
      return StudioPipelineResult(
        status: 'timeout',
        response: '',
        error: e.message?.isNotEmpty == true ? e.message : 'Studio timed out',
      );
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        _log('pipeline aborted by cancel session=$sessionId');
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      _log('pipeline error session=$sessionId error=$e');
      return StudioPipelineResult(status: 'error', response: '', error: '$e');
    } finally {
      _finishCurrentAgent = null;
      _ref.read(studioRuntimeStateProvider.notifier).state =
          const StudioRuntimeState.idle();
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
    final resolved = await _resolveAgentConfig(agent, apiConfig, sessionId);
    if (resolved.endpoint.isEmpty || resolved.model.isEmpty) {
      throw Exception('Studio agent "${agent.name}" API is not configured');
    }

    final completer = Completer<String>();
    final finishCompleter = Completer<void>();
    _finishCurrentAgent = finishCompleter;
    final transport = pickChatTransport(resolved.protocol);
    final messages = _buildAgentMessages(
      agent: agent,
      promptResult: promptResult,
      priorBriefs: priorBriefs,
      isFinalResponse: isFinalResponse,
    );
    final startedAt = DateTime.now();
    final timeoutMs = _effectiveTimeoutMs(agent, isFinalResponse);
    final shouldStream = resolved.stream;
    final output = StringBuffer();
    final reasoning = StringBuffer();
    Timer? idleTimer;
    CancelToken? agentCancelToken;
    var finishRequested = false;
    void completeWithAccumulated(String reason) {
      if (completer.isCompleted) return;
      final text = output.toString().trim();
      _log(
        'agent finish accumulated session=$sessionId name="${agent.name}" '
        'reason=$reason chars=${text.length}',
      );
      completer.complete(text);
    }

    void resetAgentTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(Duration(milliseconds: timeoutMs), () {
        if (shouldStream && (output.isNotEmpty || reasoning.isNotEmpty)) {
          completeWithAccumulated('idle_timeout');
          agentCancelToken?.cancel('Studio agent idle timeout');
        } else if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              'Studio agent "${agent.name}" timed out after ${timeoutMs}ms',
            ),
          );
        }
      });
    }

    final inputChars = messages.fold<int>(
      0,
      (sum, m) => sum + (m['content']?.toString().length ?? 0),
    );
    _log(
      'agent start session=$sessionId name="${agent.name}" '
      'final=$isFinalResponse source=${agent.modelSource} '
      'protocol=${resolved.protocol} model=${resolved.model} '
      'messages=${messages.length} inputChars=$inputChars '
      'stream=$shouldStream maxTokens=${agent.maxTokens} temp=${agent.temperature} '
      'timeoutMs=$timeoutMs persistedTimeoutMs=${agent.timeoutMs}',
    );

    agentCancelToken = CancelToken();
    unawaited(
      cancelToken.whenCancel.then((_) {
        if (!(agentCancelToken?.isCancelled ?? true)) {
          agentCancelToken?.cancel('Studio pipeline cancelled');
        }
      }),
    );
    unawaited(
      finishCompleter.future.then((_) {
        finishRequested = true;
        completeWithAccumulated('manual_finish');
        if (!(agentCancelToken?.isCancelled ?? true)) {
          agentCancelToken?.cancel('Studio agent manually finished');
        }
      }),
    );
    resetAgentTimer();

    unawaited(
      transport.stream(
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
          stream: shouldStream,
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
        cancelToken: agentCancelToken,
        onUpdate: (delta, reasoningDelta) {
          if (delta.isNotEmpty) output.write(delta);
          if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
            reasoning.write(reasoningDelta);
          }
          if (delta.isNotEmpty || reasoningDelta?.isNotEmpty == true) {
            resetAgentTimer();
          }
        },
        onComplete: (text, _, {rawResponseJson}) {
          final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
          idleTimer?.cancel();
          if (shouldStream && output.isEmpty && text.isNotEmpty) {
            output.write(text);
          }
          _log(
            'agent complete session=$sessionId name="${agent.name}" '
            'elapsedMs=$elapsed chars=${text.trim().length} '
            'rawJson=${rawResponseJson?.length ?? 0}',
          );
          if (!completer.isCompleted) {
            final accumulated = output.toString().trim();
            completer.complete(
              shouldStream && accumulated.isNotEmpty
                  ? accumulated
                  : text.trim(),
            );
          }
        },
        onError: (error) {
          final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
          idleTimer?.cancel();
          if (finishRequested && completer.isCompleted) return;
          if (shouldStream &&
              (agentCancelToken?.isCancelled ?? false) &&
              output.isNotEmpty) {
            completeWithAccumulated('cancel_with_streamed_text');
            return;
          }
          _log(
            'agent error session=$sessionId name="${agent.name}" '
            'elapsedMs=$elapsed error=$error',
          );
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );

    return completer.future.whenComplete(() {
      idleTimer?.cancel();
      if (identical(_finishCurrentAgent, finishCompleter)) {
        _finishCurrentAgent = null;
      }
    });
  }

  Future<_ResolvedAgentConfig> _resolveAgentConfig(
    StudioAgent agent,
    ApiConfig current,
    String sessionId,
  ) async {
    if (agent.modelSource == 'custom') {
      await _ref.read(apiListProvider.future);
      final apiConfigs =
          _ref.read(apiListProvider).value ?? const <ApiConfig>[];
      final selected = apiConfigs.where((c) => c.id == agent.model).firstOrNull;
      if (selected != null) return _ResolvedAgentConfig.fromApiConfig(selected);
      return _ResolvedAgentConfig(
        endpoint: agent.endpoint,
        apiKey: current.apiKey,
        model: agent.model,
        protocol: LlmProtocol.openai,
        stream: current.stream,
      );
    }

    await _ref.read(apiListProvider.future);
    final apiConfigs = _ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final configRunId = await _readRunApiConfigId(sessionId);
    final selected = configRunId.isNotEmpty
        ? apiConfigs.where((c) => c.id == configRunId).firstOrNull
        : null;
    final active = selected ?? _ref.read(activeApiConfigProvider) ?? current;
    return _ResolvedAgentConfig.fromApiConfig(active);
  }

  Future<String> _readRunApiConfigId(String sessionId) async {
    final config = await _ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    return config?.runApiConfigId ?? '';
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
      ..writeln(
        isFinalResponse
            ? 'You are the final responder. Produce only the in-character RP response.'
            : 'You are an intermediate Studio agent. Produce a compact brief for later agents. Do not write the final RP response.',
      );
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

  int _effectiveTimeoutMs(StudioAgent agent, bool isFinalResponse) {
    final fallback = isFinalResponse ? 90000 : 60000;
    if (agent.timeoutMs <= 4000) return fallback;
    return agent.timeoutMs.clamp(1000, 120000);
  }

  void _log(String message) {
    debugPrint('[Studio] $message');
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
  final bool stream;
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
    this.stream = false,
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
      stream: config.stream,
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
