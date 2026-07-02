import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/api_list_provider.dart';
import '../models/api_config.dart';
import '../models/pipeline_settings.dart';
import 'aux_retry_runner.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';

/// Resolved auxiliary API configuration for a non-streaming LLM call.
class AuxApiConfig {
  final String endpoint;
  final String apiKey;
  final String model;
  final String protocol;

  const AuxApiConfig({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.protocol,
  });
}

/// Shared helper for auxiliary (non-streaming) LLM calls.
///
/// Extracted from the duplicated pattern in `MemoryAgenticService`
/// (`_askLlmForSearchQuery`, `_askLlmForWrites`) and `PostCleanerService`
/// (`_askLlmForCleanedText`). All three had identical API-config resolution
/// + `transport.stream` + `Completer` + timeout logic.
///
/// Usage:
/// ```dart
/// final client = AuxLlmClient(ref);
/// final config = await client.resolveConfig(settings, errorLabel: 'write-loop');
/// final raw = await client.callOnce(
///   config: config,
///   prompt: '...',
///   maxTokens: 1000,
///   temperature: 0.2,
///   timeoutMs: settings.auxTimeoutMs,
///   cancelToken: cancelToken,
/// );
/// ```
class AuxLlmClient {
  final Ref _ref;

  AuxLlmClient(this._ref);

  /// Resolves the API config from [settings]: either the custom auxiliary
  /// endpoint or the active chat config. Throws if not configured.
  Future<AuxApiConfig> resolveConfig(
    PipelineSettings settings, {
    String errorLabel = 'aux',
  }) async {
    final isCustom = settings.auxSource == 'custom';
    if (isCustom) {
      if (settings.auxEndpoint.isEmpty || settings.auxModel.isEmpty) {
        debugPrint(
          '[Aux] custom config incomplete — endpoint='
          "'${settings.auxEndpoint}' model='${settings.auxModel}'",
        );
        throw Exception('Aux custom config incomplete for $errorLabel');
      }
      debugPrint(
        '[Aux] resolved custom for $errorLabel '
        'model=${settings.auxModel}',
      );
      return AuxApiConfig(
        endpoint: settings.auxEndpoint,
        apiKey: settings.auxApiKey,
        model: settings.auxModel,
        protocol: LlmProtocol.openai,
      );
    }

    await _ref.read(apiListProvider.future);
    final chatConfig = _ref.read(activeApiConfigProvider);
    if (chatConfig == null) {
      debugPrint('[Aux] no active chat API config for $errorLabel');
      throw Exception('No chat API config available for $errorLabel');
    }
    final model = settings.auxModel.isNotEmpty
        ? settings.auxModel
        : chatConfig.model;
    debugPrint(
      '[Aux] resolved chat-fallback for $errorLabel '
      'model=$model endpoint=${chatConfig.endpoint}',
    );
    return AuxApiConfig(
      endpoint: chatConfig.endpoint,
      apiKey: chatConfig.apiKey,
      model: model,
      protocol: chatConfig.protocol,
    );
  }

  /// Resolves the MemoryBook generation model. Used by manual MemoryBook draft
  /// generation and the agentic write-loop so both memory-writing paths share
  /// one visible model setting.
  Future<AuxApiConfig> resolveConfigForMemoryGeneration(
    PipelineSettings settings, {
    String errorLabel = 'memory generation',
  }) async {
    final isCustom = settings.generationSource == 'custom';
    if (isCustom) {
      if (settings.generationEndpoint.isEmpty ||
          settings.generationModel.isEmpty) {
        debugPrint(
          '[Aux] memory custom config incomplete — endpoint='
          "'${settings.generationEndpoint}' model='${settings.generationModel}'",
        );
        throw Exception('Memory generation config incomplete for $errorLabel');
      }
      debugPrint(
        '[Aux] resolved memory custom for $errorLabel '
        'model=${settings.generationModel}',
      );
      return AuxApiConfig(
        endpoint: settings.generationEndpoint,
        apiKey: settings.generationApiKey,
        model: settings.generationModel,
        protocol: LlmProtocol.openai,
      );
    }

    await _ref.read(apiListProvider.future);
    final chatConfig = _ref.read(activeApiConfigProvider);
    if (chatConfig == null) {
      debugPrint('[Aux] no active chat API config for $errorLabel');
      throw Exception('No chat API config available for $errorLabel');
    }
    final model = settings.generationModel.isNotEmpty
        ? settings.generationModel
        : chatConfig.model;
    debugPrint(
      '[Aux] resolved memory chat-fallback for $errorLabel '
      'model=$model endpoint=${chatConfig.endpoint}',
    );
    return AuxApiConfig(
      endpoint: chatConfig.endpoint,
      apiKey: chatConfig.apiKey,
      model: model,
      protocol: chatConfig.protocol,
    );
  }

  /// Resolves the API config for the POST-cleaner, preferring
  /// `postCleaner*` fields and falling back to `aux*` when the
  /// cleaner-specific fields are empty/zero.
  Future<AuxApiConfig> resolveConfigForCleaner(
    PipelineSettings settings, {
    String errorLabel = 'post-cleaner',
  }) async {
    final source = settings.postCleanerSource == 'inherit'
        ? settings.auxSource
        : settings.postCleanerSource;
    final model = settings.postCleanerModel.isNotEmpty
        ? settings.postCleanerModel
        : settings.auxModel;
    final endpoint = settings.postCleanerEndpoint.isNotEmpty
        ? settings.postCleanerEndpoint
        : settings.auxEndpoint;
    final apiKey = settings.postCleanerApiKey.isNotEmpty
        ? settings.postCleanerApiKey
        : settings.auxApiKey;

    if (source == 'custom') {
      if (endpoint.isEmpty || model.isEmpty) {
        debugPrint(
          '[Aux] cleaner custom config incomplete — endpoint='
          "'$endpoint' model='$model'",
        );
        throw Exception('Aux custom config incomplete for $errorLabel');
      }
      debugPrint('[Aux] resolved custom for $errorLabel model=$model');
      return AuxApiConfig(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        protocol: LlmProtocol.openai,
      );
    }

    await _ref.read(apiListProvider.future);
    final chatConfig = _ref.read(activeApiConfigProvider);
    if (chatConfig == null) {
      debugPrint('[Aux] no active chat API config for $errorLabel');
      throw Exception('No chat API config available for $errorLabel');
    }
    final effectiveModel = model.isNotEmpty ? model : chatConfig.model;
    debugPrint(
      '[Aux] resolved chat-fallback for $errorLabel '
      'model=$effectiveModel endpoint=${chatConfig.endpoint}',
    );
    return AuxApiConfig(
      endpoint: chatConfig.endpoint,
      apiKey: chatConfig.apiKey,
      model: effectiveModel,
      protocol: chatConfig.protocol,
    );
  }

  /// Resolves the API config for the POST-cleaner CHARACTER AUDIT pass
  /// (Fix 2). Inherits endpoint / key / source / protocol from the cleaner
  /// config, but the [PipelineSettings.postCleanerAuditModel] field overrides
  /// the model when non-empty. Falls back to the cleaner-resolved model when
  /// the audit model is empty.
  ///
  /// Reuses [resolveConfigForCleaner] for the endpoint/key/source/protocol
  /// resolution, then swaps in the audit model. This keeps the two resolvers
  /// in lockstep for every source branch (inherit → aux, custom, current).
  Future<AuxApiConfig> resolveConfigForAudit(
    PipelineSettings settings, {
    String errorLabel = 'post-cleaner-audit',
  }) async {
    final cleaner = await resolveConfigForCleaner(
      settings,
      errorLabel: errorLabel,
    );
    final auditModel = settings.postCleanerAuditModel.isNotEmpty
        ? settings.postCleanerAuditModel
        : cleaner.model;
    if (auditModel != cleaner.model) {
      debugPrint(
        '[Aux] audit model override for $errorLabel '
        'model=$auditModel (cleaner=${cleaner.model})',
      );
    }
    return AuxApiConfig(
      endpoint: cleaner.endpoint,
      apiKey: cleaner.apiKey,
      model: auditModel,
      protocol: cleaner.protocol,
    );
  }

  /// Resolves the API config for the memory consolidation LLM (Phase G5).
  ///
  /// `source='custom'` → use `consolidationEndpoint/ApiKey/Model`.
  /// `source='current'` → read the active chat API config and use its
  /// endpoint/key/protocol. `consolidationModel` overrides the model when
  /// non-empty (same pattern as [resolveConfigForCleaner]).
  Future<AuxApiConfig> resolveConfigForConsolidation(
    PipelineSettings settings, {
    String errorLabel = 'consolidation',
  }) async {
    if (settings.consolidationSource == 'custom') {
      if (settings.consolidationEndpoint.isEmpty ||
          settings.consolidationModel.isEmpty) {
        debugPrint(
          '[Aux] consolidation custom config incomplete — '
          "endpoint='${settings.consolidationEndpoint}' "
          "model='${settings.consolidationModel}'",
        );
        throw Exception('Aux custom config incomplete for $errorLabel');
      }
      debugPrint(
        '[Aux] resolved custom for $errorLabel '
        'model=${settings.consolidationModel}',
      );
      return AuxApiConfig(
        endpoint: settings.consolidationEndpoint,
        apiKey: settings.consolidationApiKey,
        model: settings.consolidationModel,
        protocol: LlmProtocol.openai,
      );
    }

    await _ref.read(apiListProvider.future);
    final chatConfig = _ref.read(activeApiConfigProvider);
    if (chatConfig == null) {
      debugPrint('[Aux] no active chat API config for $errorLabel');
      throw Exception('No chat API config available for $errorLabel');
    }
    final model = settings.consolidationModel.isNotEmpty
        ? settings.consolidationModel
        : chatConfig.model;
    debugPrint(
      '[Aux] resolved chat-fallback for $errorLabel '
      'model=$model endpoint=${chatConfig.endpoint}',
    );
    return AuxApiConfig(
      endpoint: chatConfig.endpoint,
      apiKey: chatConfig.apiKey,
      model: model,
      protocol: chatConfig.protocol,
    );
  }

  int resolveCleanerTimeout(PipelineSettings settings) {
    return settings.postCleanerTimeoutMs > 0
        ? settings.postCleanerTimeoutMs
        : settings.auxTimeoutMs;
  }

  /// Resolves one of Studio's saved API-config slots for an auxiliary call.
  ///
  /// Studio Ledger is part of the Studio sidecar set, so when Studio is enabled
  /// it should use the cheap slot alongside the pre-gen trackers instead of the
  /// legacy aux/ledger model fields. Empty or missing slot ids fall back to the
  /// active chat config, matching Studio agent slot behavior.
  Future<AuxApiConfig> resolveStudioSlotConfig(
    String apiConfigId, {
    String errorLabel = 'studio-slot',
    String modelOverride = '',
  }) async {
    await _ref.read(apiListProvider.future);
    final apiConfigs = _ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final activeConfig = _ref.read(activeApiConfigProvider);
    final selected = apiConfigId.isNotEmpty
        ? apiConfigs.where((c) => c.id == apiConfigId).firstOrNull
        : null;
    final config = selected ?? activeConfig;
    if (config == null) {
      debugPrint('[Aux] no Studio API config available for $errorLabel');
      throw Exception('No Studio API config available for $errorLabel');
    }
    final model = modelOverride.isNotEmpty ? modelOverride : config.model;
    debugPrint(
      '[Aux] resolved Studio slot for $errorLabel '
      'model=$model endpoint=${config.endpoint}',
    );
    return AuxApiConfig(
      endpoint: config.endpoint,
      apiKey: config.apiKey,
      model: model,
      protocol: config.protocol,
    );
  }

  /// Resolves the ledger LLM timeout from settings.
  int resolveLedgerTimeout(PipelineSettings settings) {
    final configured = settings.studioLedgerTimeoutMs;
    if (configured <= 0) return settings.auxTimeoutMs;
    // Early UI builds edited this value as seconds while the field name stores
    // milliseconds. Treat small persisted values as seconds to avoid accidental
    // sub-second Ledger timeouts (for example, 180 should mean 180s).
    return configured < 1000 ? configured * 1000 : configured;
  }

  /// Makes a single non-streaming LLM call and returns the raw text response.
  ///
  /// Retries on 5xx server errors (502/503/500) and timeouts using a 3-attempt
  /// backoff (1s/2s/4s) via [AuxRetryRunner]. Throws [TimeoutException] if
  /// all attempts time out. Throws [DioException] (cancel) if [cancelToken] is
  /// cancelled.
  ///
  /// Prefer [callOnceWithLog] when the caller wants the per-attempt log for
  /// the agentic operations UI.
  Future<String> callOnce({
    required AuxApiConfig config,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int timeoutMs,
    CancelToken? cancelToken,
  }) async {
    final outcome = await callOnceWithLog(
      config: config,
      prompt: prompt,
      maxTokens: maxTokens,
      temperature: temperature,
      timeoutMs: timeoutMs,
      cancelToken: cancelToken,
    );
    if (outcome.isOk && outcome.text != null) return outcome.text!;
    throw _descriptiveError(outcome);
  }

  /// Same as [callOnce] but returns a [AuxCallOutcome] with the per-attempt
  /// log so callers can record it in the agentic operations log.
  Future<AuxCallOutcome> callOnceWithLog({
    required AuxApiConfig config,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int timeoutMs,
    CancelToken? cancelToken,
    bool omitReasoning = false,
    bool omitReasoningEffort = true,
    bool requestReasoning = false,
  }) async {
    if (config.endpoint.isEmpty || config.model.isEmpty) {
      throw Exception('Aux API not configured');
    }
    final runner = const AuxRetryRunner();
    return runner.run(
      cancelToken: cancelToken,
      attempt: (i) => _callOnce(
        config: config,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        timeoutMs: timeoutMs,
        cancelToken: cancelToken,
        omitReasoning: omitReasoning,
        omitReasoningEffort: omitReasoningEffort,
        requestReasoning: requestReasoning,
      ),
    );
  }

  /// Streaming variant of [callOnceWithLog]. Makes a streaming LLM call
  /// (`stream: true`) and invokes [onChunk] with the accumulated text on
  /// every delta. Returns the same [AuxCallOutcome] (final text = last
  /// accumulation).
  ///
  /// On retry, the accumulator resets and [onChunk] is called with the new
  /// attempt's accumulated text (starting from `''`). Callers that render the
  /// chunks into a chat bubble should reset their view on the first chunk of
  /// each new attempt — a simple way is to overwrite with the incoming
  /// accumulated text (which starts at `''` on a fresh attempt).
  ///
  /// Used by the POST-cleaner to stream its rewrite into the chat bubble
  /// instead of replacing the text in one shot. Reranker / agentic-write /
  /// auditor keep using [callOnceWithLog] (non-streaming) because they need
  /// the full structured response before acting.
  Future<AuxCallOutcome> callStreamWithLog({
    required AuxApiConfig config,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int timeoutMs,
    CancelToken? cancelToken,
    void Function(String accumulatedText)? onChunk,
    bool omitReasoning = false,
    bool omitReasoningEffort = true,
    bool requestReasoning = false,
  }) async {
    if (config.endpoint.isEmpty || config.model.isEmpty) {
      throw Exception('Aux API not configured');
    }
    final runner = const AuxRetryRunner();
    return runner.run(
      cancelToken: cancelToken,
      attempt: (i) => _callStream(
        config: config,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        timeoutMs: timeoutMs,
        cancelToken: cancelToken,
        onChunk: onChunk,
        omitReasoning: omitReasoning,
        omitReasoningEffort: omitReasoningEffort,
        requestReasoning: requestReasoning,
      ),
    );
  }

  /// Builds a descriptive exception from a non-ok [AuxCallOutcome] so the
  /// caller's `catch` block can fall back to the original text with a useful
  /// error message.
  Object _descriptiveError(AuxCallOutcome outcome) {
    if (outcome.attempts.isEmpty) return Exception('Aux call failed');
    final last = outcome.attempts.last;
    if (last.status == 'timeout') {
      return TimeoutException('Aux timed out after retries');
    }
    if (last.statusCode != 0) {
      return DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: last.statusCode,
        ),
        type: DioExceptionType.badResponse,
        message: last.error ?? 'HTTP ${last.statusCode}',
      );
    }
    return Exception(last.error ?? 'Aux call failed');
  }

  Future<String> _callOnce({
    required AuxApiConfig config,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int timeoutMs,
    CancelToken? cancelToken,
    bool omitReasoning = false,
    bool omitReasoningEffort = true,
    bool requestReasoning = false,
  }) async {
    final completer = Completer<String>();
    final transport = pickChatTransport(config.protocol);

    unawaited(
      transport.stream(
        request: ChatTransportRequest(
          endpoint: config.endpoint,
          apiKey: config.apiKey,
          model: config.model,
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          maxTokens: maxTokens,
          temperature: temperature,
          topP: 1.0,
          stream: false,
          requestReasoning: requestReasoning,
          omitReasoning: omitReasoning,
          omitReasoningEffort: omitReasoningEffort,
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

    return completer.future.timeout(Duration(milliseconds: timeoutMs));
  }

  /// Streaming variant of [_callOnce]. Calls `transport.stream` with
  /// `stream: true` and forwards accumulated text to [onChunk] on every
  /// delta. Completes with the final accumulated text.
  Future<String> _callStream({
    required AuxApiConfig config,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int timeoutMs,
    CancelToken? cancelToken,
    void Function(String accumulatedText)? onChunk,
    bool omitReasoning = false,
    bool omitReasoningEffort = true,
    bool requestReasoning = false,
  }) async {
    final completer = Completer<String>();
    final transport = pickChatTransport(config.protocol);
    final accumulated = StringBuffer();

    unawaited(
      transport.stream(
        request: ChatTransportRequest(
          endpoint: config.endpoint,
          apiKey: config.apiKey,
          model: config.model,
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          maxTokens: maxTokens,
          temperature: temperature,
          topP: 1.0,
          stream: true,
          requestReasoning: requestReasoning,
          omitReasoning: omitReasoning,
          omitReasoningEffort: omitReasoningEffort,
        ),
        cancelToken: cancelToken,
        onUpdate: (delta, _) {
          if (delta.isEmpty) return;
          accumulated.write(delta);
          final text = accumulated.toString();
          if (onChunk != null && !completer.isCompleted) {
            try {
              onChunk(text);
            } catch (_) {
              // Callback errors must not abort the stream.
            }
          }
        },
        onComplete: (text, _, {rawResponseJson}) {
          // Prefer the transport's aggregated text (it may have post-processing
          // like trimming or final newline normalization). Fall back to our
          // own accumulation if the transport returned empty.
          final finalText = text.isNotEmpty ? text : accumulated.toString();
          if (!completer.isCompleted) {
            if (onChunk != null && finalText != accumulated.toString()) {
              try {
                onChunk(finalText);
              } catch (_) {}
            }
            completer.complete(finalText);
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      ),
    );

    return completer.future.timeout(Duration(milliseconds: timeoutMs));
  }
}
