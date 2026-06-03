import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

typedef SseOnUpdate = void Function(String delta, String? reasoningDelta);
typedef SseOnComplete = void Function(String text, String? reasoning, {String? rawResponseJson});
typedef SseOnError = void Function(Object error);

class SseClient {
  final Dio _dio;

  SseClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ));

  static String normalizeEndpoint(String endpoint) {
    var normalized = endpoint.trim();
    if (normalized.isEmpty) return '';
    if (!normalized.startsWith(RegExp(r'https?://'))) {
      normalized = 'https://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String buildChatUrl(String endpoint) {
    final base = normalizeEndpoint(endpoint);
    if (base.isEmpty) return '';
    if (base.toLowerCase().endsWith('/chat/completions') ||
        base.toLowerCase().endsWith('/v1/chat/completions')) {
      return base;
    }
    if (base.endsWith('/v1')) {
      return '$base/chat/completions';
    }
    return '$base/v1/chat/completions';
  }

  Future<void> streamChatCompletion({
    required String endpoint,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
    required double temperature,
    required double topP,
    required bool stream,
    CancelToken? cancelToken,
    SseOnUpdate? onUpdate,
    SseOnComplete? onComplete,
    SseOnError? onError,
    bool requestReasoning = false,
    String? reasoningEffort,
    bool omitTemperature = false,
    bool omitTopP = false,
    bool omitReasoning = false,
    bool omitReasoningEffort = false,
    String? sessionId,
    String cacheControlTtl = 'off',
  }) async {
    if (apiKey.isEmpty) {
      onError?.call(Exception('API key is empty'));
      return;
    }
    final url = buildChatUrl(endpoint);

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': stream,
    };

    if (maxTokens > 0) {
      body['max_tokens'] = maxTokens;
    }
    if (!omitTemperature && temperature > 0) {
      body['temperature'] = temperature;
    }
    if (!omitTopP && topP > 0 && topP < 1) {
      body['top_p'] = topP;
    }
    if (!omitReasoning && requestReasoning &&
        !omitReasoningEffort &&
        reasoningEffort != null &&
        reasoningEffort != 'auto') {
      body['reasoning_effort'] = reasoningEffort;
    }

    if (cacheControlTtl == '5min' || cacheControlTtl == '1h') {
      body['cache_control'] = <String, dynamic>{
        'type': 'ephemeral',
        if (cacheControlTtl == '1h') 'ttl': '1h',
      };
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      body['session_id'] = sessionId;
    }



    try {
      if (stream) {
        await _streamResponse(url, apiKey, body, cancelToken, onUpdate, onComplete);
      } else {
        await _oneShotResponse(url, apiKey, body, cancelToken, onComplete);
      }
    } on DioException catch (e) {
      onError?.call(e);
    } catch (e) {
      onError?.call(e);
    }
  }

  Future<void> _streamResponse(
    String url,
    String apiKey,
    Map<String, dynamic> body,
    CancelToken? cancelToken,
    SseOnUpdate? onUpdate,
    SseOnComplete? onComplete,
  ) async {
    final response = await _dio.post<ResponseBody>(
      url,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
      data: body,
      cancelToken: cancelToken,
    );

    final responseBody = response.data;
    if (responseBody == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Empty stream response body',
      );
    }
    final responseStream = responseBody.stream;
    final completer = Completer<void>();
    StreamSubscription<List<int>>? subscription;
    var buffer = '';
    var fullText = '';
    var fullReasoning = '';
    var doneReceived = false;
    String? lastRawJsonPayload; // fallback: last complete SSE JSON payload before [DONE]

    subscription = (responseStream as Stream<List<int>>).listen(
      (chunk) {
        if (cancelToken?.isCancelled == true) {
          debugPrint('[SSE] cancel detected in listen callback, stopping stream');
          subscription?.cancel();
          if (!completer.isCompleted) completer.complete();
          return;
        }
        buffer += utf8.decode(chunk, allowMalformed: true);
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          if (cancelToken?.isCancelled == true) {
            debugPrint('[SSE] cancel detected while parsing lines, stopping immediately');
            buffer = '';
            subscription?.cancel();
            if (!completer.isCompleted) completer.complete();
            return;
          }
          final trimmed = line.trim();
          if (!trimmed.startsWith('data: ')) continue;
          final data = trimmed.substring(6).trim();
          if (data == '[DONE]') {
            if (cancelToken != null && cancelToken.isCancelled) {
              debugPrint('[SSE] cancel detected at [DONE], suppressing onComplete');
            } else {
              onComplete?.call(
                fullText,
                fullReasoning.isNotEmpty ? fullReasoning : null,
                rawResponseJson: _buildAggregatedRawResponse(
                  fullText: fullText,
                  fullReasoning: fullReasoning,
                  fallbackRawJsonPayload: lastRawJsonPayload,
                ),
              );
              doneReceived = true;
            }
            subscription?.cancel();
            if (!completer.isCompleted) completer.complete();
            return;
          }

          // Keep the last successfully parsed JSON payload (this is the "final response" chunk)
          lastRawJsonPayload = data;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choice = json['choices']?[0];
            final delta = choice?['delta'];

            final contentDelta = delta?['content'] as String? ?? '';
            final reasoningDelta = delta?['reasoning_content'] as String? ??
                delta?['reasoning'] as String?;

            if (contentDelta.isNotEmpty) {
              fullText += contentDelta;
            }
            if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
              fullReasoning += reasoningDelta;
            }

            if (contentDelta.isNotEmpty || reasoningDelta != null) {
              onUpdate?.call(contentDelta, reasoningDelta);
            }
          } catch (_) {}
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
      cancelOnError: true,
    );

    if (cancelToken != null) {
      unawaited(cancelToken.whenCancel.then((_) {
        debugPrint('[SSE] CancelToken fired — cancelling stream subscription');
        subscription?.cancel();
        if (!completer.isCompleted) completer.complete();
      }));
    }

    await completer.future;

    if (cancelToken != null && cancelToken.isCancelled) {
      debugPrint('[SSE] stream completed with cancel active; suppressing onComplete');
      return;
    }

    if (doneReceived) return;

    // Server dropped connection without [DONE] — treat as normal completion
    // if any text was accumulated (provider returned 200 but omitted [DONE]).
    if (fullText.isNotEmpty || fullReasoning.isNotEmpty) {
      onComplete?.call(
        fullText,
        fullReasoning.isNotEmpty ? fullReasoning : null,
        rawResponseJson: _buildAggregatedRawResponse(
          fullText: fullText,
          fullReasoning: fullReasoning,
          fallbackRawJsonPayload: lastRawJsonPayload,
        ),
      );
      return;
    }
    throw DioException(
      requestOptions: RequestOptions(path: url),
      message: 'Stream ended without [DONE] (server dropped connection)',
      type: DioExceptionType.connectionError,
    );
  }

  Future<void> _oneShotResponse(
    String url,
    String apiKey,
    Map<String, dynamic> body,
    CancelToken? cancelToken,
    SseOnComplete? onComplete,
  ) async {
    final response = await _dio.post<dynamic>(
      url,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
      data: body,
      cancelToken: cancelToken,
    );

    final raw = response.data;
    Map<String, dynamic>? data;

    String? rawResponseJson;
    if (raw is Map<String, dynamic>) {
      data = raw;
      try {
        rawResponseJson = jsonEncode(raw);
      } catch (_) {}
    } else if (raw is String && raw.trim().isNotEmpty) {
      final trimmed = raw.trim();
      rawResponseJson = trimmed; // keep original body for raw view
      // Try plain JSON first.
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
      // Fallback: provider ignored stream:false and sent SSE chunks.
      if (data == null && trimmed.contains('data:')) {
        final agg = _aggregateSseString(trimmed);
        onComplete?.call(agg.$1, agg.$2.isEmpty ? null : agg.$2, rawResponseJson: rawResponseJson);
        return;
      }
    }

    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected response body (${raw.runtimeType})',
      );
    }

    final choice = (data['choices'] is List && (data['choices'] as List).isNotEmpty)
        ? (data['choices'] as List).first
        : null;
    final message = choice is Map<String, dynamic> ? choice['message'] : null;
    final content = (message is Map<String, dynamic> ? message['content'] : null) as String? ?? '';
    final reasoningRaw = message is Map<String, dynamic>
        ? (message['reasoning_content'] ?? message['reasoning'])
        : null;
    final reasoning = reasoningRaw is String ? reasoningRaw : null;

    onComplete?.call(content, reasoning, rawResponseJson: rawResponseJson ?? jsonEncode(data));
  }

  /// Aggregate a fully-buffered SSE response (provider returned text/event-stream
  /// body despite stream:false). Returns (content, reasoning).
  (String, String) _aggregateSseString(String body) {
    var fullText = '';
    var fullReasoning = '';
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;
      final payload = trimmed.substring(6).trim();
      if (payload == '[DONE]') break;
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final choice = (json['choices'] is List && (json['choices'] as List).isNotEmpty)
            ? (json['choices'] as List).first
            : null;
        final delta = choice is Map<String, dynamic> ? choice['delta'] : null;
        final msg = choice is Map<String, dynamic> ? choice['message'] : null;
        final src = delta is Map<String, dynamic> ? delta : (msg is Map<String, dynamic> ? msg : null);
        if (src == null) continue;
        final c = src['content'];
        if (c is String) fullText += c;
        final r = src['reasoning_content'] ?? src['reasoning'];
        if (r is String) fullReasoning += r;
      } catch (_) {}
    }
    return (fullText, fullReasoning);
  }

  /// Builds a stable JSON payload for "Request Preview -> Response" from the
  /// streamed deltas, so UI shows the actual assistant text/reasoning instead
  /// of an arbitrary last SSE chunk.
  ///
  /// Strategy: use [fallbackRawJsonPayload] (the last SSE chunk before [DONE])
  /// as the base — it carries top-level metadata like `id`, `model`,
  /// `system_fingerprint`, `usage`, `finish_reason`, etc. We then replace only
  /// the `choices[0].message` content with the fully-aggregated text so that
  /// all provider metadata is preserved in the preview.
  String? _buildAggregatedRawResponse({
    required String fullText,
    required String fullReasoning,
    String? fallbackRawJsonPayload,
  }) {
    if (fullText.isEmpty && fullReasoning.isEmpty) {
      return fallbackRawJsonPayload;
    }

    final message = <String, dynamic>{'role': 'assistant', 'content': fullText};
    if (fullReasoning.isNotEmpty) {
      message['reasoning'] = fullReasoning;
    }

    // Try to enrich with metadata from the last SSE chunk.
    if (fallbackRawJsonPayload != null) {
      try {
        final base = jsonDecode(fallbackRawJsonPayload) as Map<String, dynamic>;

        // Rebuild choices: keep all fields from the last chunk's choice
        // (finish_reason, logprobs, etc.) but replace delta/message content.
        final rawChoices = base['choices'];
        List<dynamic> newChoices;
        if (rawChoices is List && rawChoices.isNotEmpty) {
          newChoices = rawChoices.asMap().entries.map((entry) {
            final choice = Map<String, dynamic>.from(
                entry.value is Map ? entry.value as Map<String, dynamic> : <String, dynamic>{});
            if (entry.key == 0) {
              // Replace delta with a proper message containing full text.
              choice.remove('delta');
              choice['message'] = message;
            }
            return choice;
          }).toList();
        } else {
          newChoices = [
            {'index': 0, 'message': message, 'finish_reason': 'stop'},
          ];
        }

        // Merge usage: prefer base usage, but also check if a separate
        // usage-only chunk was stored (some providers send usage in the
        // last delta before [DONE]).
        final merged = Map<String, dynamic>.from(base);
        merged['choices'] = newChoices;
        // Ensure object type is correct.
        merged['object'] = merged['object'] ?? 'chat.completion';

        return jsonEncode(merged);
      } catch (_) {
        // Parsing failed — fall through to minimal synthetic response.
      }
    }

    // Fallback: minimal synthetic response when no metadata is available.
    return jsonEncode({
      'object': 'chat.completion',
      'choices': [
        {'index': 0, 'message': message, 'finish_reason': 'stop'},
      ],
    });
  }

  Future<List<Map<String, dynamic>>> fetchModels({
    required String endpoint,
    required String apiKey,
  }) async {
    final base = normalizeEndpoint(endpoint);
    final url = '$base/models';

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(headers: {
          'Authorization': 'Bearer $apiKey',
        }),
      );
      final data = response.data?['data'] as List?;
      return data?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }
}
