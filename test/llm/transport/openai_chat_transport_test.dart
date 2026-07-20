import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/transport/chat_transport_request.dart';
import 'package:glaze_flutter/core/llm/transport/openai_chat_transport.dart';

ChatTransportRequest _req({
  String endpoint = 'https://api.openai.com',
  String sessionIdMode = 'openrouter',
  int? receiveTimeoutMs,
}) {
  return ChatTransportRequest(
    endpoint: endpoint,
    apiKey: 'sk-test',
    model: 'gpt-test',
    messages: const [
      {'role': 'user', 'content': 'hi'},
    ],
    maxTokens: 100,
    temperature: 0.7,
    topP: 0.9,
    sessionId: 'sess-1',
    sessionIdMode: sessionIdMode,
    receiveTimeoutMs: receiveTimeoutMs,
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? options;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    return ResponseBody.fromBytes(
      utf8.encode('{"choices":[{"message":{"content":"ok"}}]}'),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('per-request zero disables the default receive timeout', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 120)))
      ..httpClientAdapter = adapter;
    final transport = OpenAiChatTransport(dio: dio);

    await transport.stream(
      request: _req(receiveTimeoutMs: 0),
      onComplete: (_, _, {rawResponseJson}) {},
    );

    expect(adapter.options?.receiveTimeout, Duration.zero);
  });

  group('session_id', () {
    test('openrouter mode only sends session_id to OpenRouter', () {
      final openRouter = OpenAiChatTransport.buildBody(
        _req(endpoint: 'https://openrouter.ai/api/v1'),
      );
      final openAi = OpenAiChatTransport.buildBody(_req());

      expect(openRouter['session_id'], 'sess-1');
      expect(openAi.containsKey('session_id'), isFalse);
    });

    test('always mode sends session_id to any endpoint', () {
      final body = OpenAiChatTransport.buildBody(_req(sessionIdMode: 'always'));

      expect(body['session_id'], 'sess-1');
    });

    test('off mode never sends session_id', () {
      final body = OpenAiChatTransport.buildBody(
        _req(endpoint: 'https://openrouter.ai/api/v1', sessionIdMode: 'off'),
      );

      expect(body.containsKey('session_id'), isFalse);
    });
  });
}
