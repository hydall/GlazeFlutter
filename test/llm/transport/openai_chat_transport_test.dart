import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/transport/chat_transport_request.dart';
import 'package:glaze_flutter/core/llm/transport/openai_chat_transport.dart';

ChatTransportRequest _req({
  String endpoint = 'https://api.openai.com',
  String sessionIdMode = 'openrouter',
  bool omitReasoning = false,
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
    omitReasoning: omitReasoning,
  );
}

void main() {
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

  group('reasoning', () {
    test(
      'omit reasoning sends explicit exclusion for compatible providers',
      () {
        final body = OpenAiChatTransport.buildBody(
          _req(endpoint: 'https://custom.example/v1', omitReasoning: true),
        );

        expect(body['reasoning'], {'exclude': true});
        expect(body.containsKey('reasoning_effort'), isFalse);
      },
    );
  });
}
