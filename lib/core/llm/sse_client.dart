import 'dart:convert';

import 'package:dio/dio.dart';

typedef SseOnUpdate = void Function(String delta, String? reasoningDelta);
typedef SseOnComplete = void Function(String text, String? reasoning);
typedef SseOnError = void Function(Object error);

class SseClient {
  final Dio _dio;

  SseClient() : _dio = Dio();

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
  }) async {
    final url = endpoint.endsWith('/')
        ? '${endpoint}chat/completions'
        : '$endpoint/chat/completions';

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'top_p': topP,
      'stream': stream,
    };

    if (requestReasoning) {
      body['reasoning_effort'] = reasoningEffort ?? 'medium';
    }

    try {
      if (stream) {
        await _streamResponse(url, apiKey, body, cancelToken, onUpdate, onComplete);
      } else {
        await _oneShotResponse(url, apiKey, body, cancelToken, onComplete);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return;
      }
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

    onComplete?.call(fullText, fullReasoning.isNotEmpty ? fullReasoning : null);
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
    final url = endpoint.endsWith('/')
        ? '${endpoint}models'
        : '$endpoint/models';

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
