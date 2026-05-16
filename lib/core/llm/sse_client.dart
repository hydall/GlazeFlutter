import 'dart:convert';

import 'package:dio/dio.dart';

typedef SseOnUpdate = void Function(String delta, String? reasoningDelta);
typedef SseOnComplete = void Function(String text, String? reasoning);
typedef SseOnError = void Function(Object error);

class SseClient {
  final Dio _dio;

  SseClient() : _dio = Dio();

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
    required List<Map<String, String>> messages,
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
    final response = await _dio.post(
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

    final responseStream = response.data.stream;
    var buffer = '';
    var fullText = '';
    var fullReasoning = '';

    await for (final chunk in responseStream) {
      if (cancelToken != null && cancelToken.isCancelled) break;

      buffer += utf8.decode(chunk, allowMalformed: true);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data: ')) continue;
        final data = trimmed.substring(6).trim();
        if (data == '[DONE]') {
          // Normal completion — call onComplete and return.
          onComplete?.call(fullText, fullReasoning.isNotEmpty ? fullReasoning : null);
          return;
        }

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
    }

    // Stream ended without [DONE] — this means the connection was dropped
    // (server-side cancel, network error, 499, etc.) or the client cancelled.
    // Do NOT call onComplete here; the outer catch will invoke onError instead.
    // If the client cancelled cleanly, onError handles it via DioException.cancel.
    // If text accumulated, we throw so onError can decide what to save.
    if (cancelToken != null && cancelToken.isCancelled) return;
    // Server dropped connection without [DONE] — treat as normal completion
    // if any text was accumulated (provider returned 200 but omitted [DONE]).
    if (fullText.isNotEmpty || fullReasoning.isNotEmpty) {
      onComplete?.call(fullText, fullReasoning.isNotEmpty ? fullReasoning : null);
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
    final response = await _dio.post(
      url,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
      data: body,
      cancelToken: cancelToken,
    );

    final data = response.data as Map<String, dynamic>;
    final choice = data['choices']?[0];
    final message = choice?['message'];
    final content = message?['content'] as String? ?? '';
    final reasoning = message?['reasoning_content'] as String? ??
        message?['reasoning'] as String?;

    onComplete?.call(content, reasoning);
  }

  Future<List<Map<String, dynamic>>> fetchModels({
    required String endpoint,
    required String apiKey,
  }) async {
    final base = normalizeEndpoint(endpoint);
    final url = '$base/models';

    try {
      final response = await _dio.get(
        url,
        options: Options(headers: {
          'Authorization': 'Bearer $apiKey',
        }),
      );
      final data = response.data['data'] as List?;
      return data?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }
}
