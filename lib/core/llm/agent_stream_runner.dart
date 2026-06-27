import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/studio_config.dart';
import 'agent_runner.dart' show AgentRunResult, ResolvedAgentConfig;
import 'reasoning_stripper.dart';
import 'transport/chat_transport.dart';
import 'transport/chat_transport_request.dart';

/// The streaming state machine for a single Studio agent run, extracted
/// from `AgentRunner._runAgentInner` (plan §7.1). Given an already-resolved
/// [ResolvedAgentConfig] + the agent's `messages`, it builds a
/// [ChatTransportRequest], drives the LLM transport stream, accumulates
/// the output + reasoning, enforces the per-agent idle/total timeout, and
/// forwards incremental updates to the caller's callbacks.
///
/// Pure aside from the injected [AgentTransportPicker] (so the transport
/// selection is overridable in tests). Does NOT know about `Ref`, API
/// config resolution, or per-agent failure wrapping — those stay in
/// [AgentRunner]. Behavior preserved verbatim.
class AgentStreamRunner {
  final AgentTransportPicker _pickTransport;

  AgentStreamRunner(this._pickTransport);

  /// Run one agent's LLM stream. Returns the final accumulated
  /// [AgentRunResult]. [isFinalResponse] = true → the generator; reasoning
  /// is forwarded to the UI. [isFinalResponse] = false → a tracker;
  /// reasoning is discarded.
  Future<AgentRunResult> run({
    required StudioAgent agent,
    required List<Map<String, dynamic>> messages,
    required ResolvedAgentConfig resolved,
    required String sessionId,
    required bool isFinalResponse,
    required CancelToken cancelToken,
    required int timeoutMs,
    int? maxTokensOverride,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
    void Function(String text)? onIntermediateUpdate,
  }) async {
    final completer = Completer<AgentRunResult>();
    final requestMessages =
        isFinalResponse &&
            (!resolved.requestReasoning || resolved.omitReasoning)
        ? ReasoningStripper.stripMessageReasoning(messages)
        : messages;
    final shouldStream = resolved.stream;
    final request = ChatTransportRequest(
      endpoint: resolved.endpoint,
      apiKey: resolved.apiKey,
      model: resolved.model,
      messages: requestMessages,
      maxTokens: maxTokensOverride ?? agent.maxTokens,
      temperature: agent.temperature,
      topP: resolved.topP,
      topK: resolved.topK,
      frequencyPenalty: resolved.frequencyPenalty,
      presencePenalty: resolved.presencePenalty,
      stream: shouldStream,
      requestReasoning: isFinalResponse ? resolved.requestReasoning : false,
      reasoningEffort: isFinalResponse ? resolved.reasoningEffort : null,
      omitTemperature: resolved.omitTemperature,
      omitTopP: resolved.omitTopP,
      omitReasoning: isFinalResponse ? resolved.omitReasoning : true,
      omitReasoningEffort: isFinalResponse
          ? resolved.omitReasoningEffort
          : true,
      sessionId: sessionId,
      cacheControlTtl: resolved.cacheControlTtl,
      cacheBreakpointMode: resolved.cacheBreakpointMode,
      sessionIdMode: resolved.sessionIdMode,
    );
    final transport = _pickTransport(resolved.protocol);
    final startedAt = DateTime.now();
    final output = StringBuffer();
    final reasoning = StringBuffer();
    Timer? idleTimer;
    CancelToken? agentCancelToken;
    // Once the model emits its first chunk (text OR reasoning), cancel the
    // idle timer entirely so a long (but progressing) generation is never
    // cut off mid-stream. The stream's own onComplete/onError (or the outer
    // pipeline cancelToken) is the only termination after that.
    var streamStarted = false;
    void completeWithAccumulated(String reason) {
      if (completer.isCompleted) return;
      final text = output.toString().trim();
      final reasoningText = isFinalResponse ? reasoning.toString().trim() : '';
      completer.complete(
        AgentRunResult(text: text, reasoning: reasoningText),
      );
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

    agentCancelToken = CancelToken();
    unawaited(
      cancelToken.whenCancel.then((_) {
        if (!(agentCancelToken?.isCancelled ?? true)) {
          agentCancelToken?.cancel('Studio pipeline cancelled');
        }
      }),
    );
    resetAgentTimer();

    unawaited(
      transport.stream(
        request: request,
        cancelToken: agentCancelToken,
        onUpdate: (delta, reasoningDelta) {
          if (delta.isNotEmpty) output.write(delta);
          if (isFinalResponse && delta.isNotEmpty) {
            onFinalResponseUpdate?.call(
              output.toString().trimLeft(),
              reasoning.isNotEmpty ? reasoning.toString() : null,
            );
          } else if (!isFinalResponse && delta.isNotEmpty) {
            onIntermediateUpdate?.call(output.toString().trimLeft());
          }
          if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
            reasoning.write(reasoningDelta);
            if (isFinalResponse) {
              onFinalResponseUpdate?.call(
                output.toString().trimLeft(),
                reasoning.toString(),
              );
            }
          }
          if (delta.isNotEmpty || reasoningDelta?.isNotEmpty == true) {
            // First chunk (text or reasoning): the model is producing
            // output. Cancel the idle timer for good so a long generation
            // is never cut off mid-stream. Only onComplete/onError or the
            // outer pipeline cancel terminates the run after this.
            if (!streamStarted) {
              streamStarted = true;
              idleTimer?.cancel();
            }
          }
        },
        onComplete: (text, finalReasoning, {rawResponseJson}) {
          idleTimer?.cancel();
          if (shouldStream && output.isEmpty && text.isNotEmpty) {
            output.write(text);
          }
          if (isFinalResponse) {
            final accumulated = output.toString().trimLeft();
            final reasoningText = reasoning.isNotEmpty
                ? reasoning.toString()
                : finalReasoning?.trim().isNotEmpty == true
                ? finalReasoning!.trim()
                : null;
            if (accumulated.isNotEmpty) {
              onFinalResponseUpdate?.call(accumulated, reasoningText);
            } else if (text.isNotEmpty) {
              onFinalResponseUpdate?.call(text.trimLeft(), reasoningText);
            }
          } else {
            final accumulated = output.toString().trimLeft();
            if (accumulated.isNotEmpty) {
              onIntermediateUpdate?.call(accumulated);
            } else if (text.isNotEmpty) {
              onIntermediateUpdate?.call(text.trimLeft());
            }
          }
          if (!completer.isCompleted) {
            final accumulated = output.toString().trim();
            final reasoningText = isFinalResponse
                ? reasoning.isNotEmpty
                      ? reasoning.toString().trim()
                      : finalReasoning?.trim() ?? ''
                : '';
            completer.complete(
              AgentRunResult(
                text: shouldStream && accumulated.isNotEmpty
                    ? accumulated
                    : text.trim(),
                reasoning: reasoningText,
                rawResponseJson: rawResponseJson,
              ),
            );
          }
        },
        onError: (error) {
          final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
          idleTimer?.cancel();
          if (shouldStream &&
              (agentCancelToken?.isCancelled ?? false) &&
              output.isNotEmpty) {
            completeWithAccumulated('cancel_with_streamed_text');
            return;
          }
          debugPrint(
            '[AgentRunner] agent error session=$sessionId '
            'name="${agent.name}" elapsedMs=$elapsed error=$error',
          );
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );

    return completer.future.whenComplete(() {
      idleTimer?.cancel();
    });
  }
}

/// Function signature for picking a chat transport by protocol. Extracted
/// so [AgentStreamRunner] can be tested without depending on
/// `pickChatTransport` directly.
typedef AgentTransportPicker = ChatTransport Function(String protocol);
