import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/transport/anthropic_chat_transport.dart';
import 'package:glaze_flutter/core/llm/transport/chat_transport_request.dart';

ChatTransportRequest _req({
  String model = 'claude-3-5-sonnet',
  List<Map<String, dynamic>>? messages,
  int maxTokens = 4000,
  double temperature = 0.7,
  double topP = 0.9,
  bool stream = true,
  bool requestReasoning = false,
  String? reasoningEffort,
  String cacheControlTtl = 'off',
}) {
  return ChatTransportRequest(
    endpoint: 'https://api.anthropic.com',
    apiKey: 'sk-ant-test',
    model: model,
    messages: messages ??
        [
          {'role': 'system', 'content': 'you are helpful'},
          {'role': 'user', 'content': 'hi'},
        ],
    maxTokens: maxTokens,
    temperature: temperature,
    topP: topP,
    stream: stream,
    requestReasoning: requestReasoning,
    reasoningEffort: reasoningEffort,
    cacheControlTtl: cacheControlTtl,
  );
}

void main() {
  group('buildMessagesUrl', () {
    test('default endpoint → /v1/messages', () {
      expect(
        AnthropicChatTransport.buildMessagesUrl('https://api.anthropic.com'),
        'https://api.anthropic.com/v1/messages',
      );
    });

    test('endpoint with /v1 suffix preserved', () {
      expect(
        AnthropicChatTransport.buildMessagesUrl('https://proxy.example/v1'),
        'https://proxy.example/v1/messages',
      );
    });

    test('endpoint with full /v1/messages preserved verbatim', () {
      expect(
        AnthropicChatTransport.buildMessagesUrl(
          'https://proxy.example/v1/messages',
        ),
        'https://proxy.example/v1/messages',
      );
    });

    test('empty endpoint falls back to anthropic default', () {
      expect(
        AnthropicChatTransport.buildMessagesUrl(''),
        'https://api.anthropic.com/v1/messages',
      );
    });

    test('schemeless endpoint gets https prefix', () {
      expect(
        AnthropicChatTransport.buildMessagesUrl('proxy.example.com'),
        'https://proxy.example.com/v1/messages',
      );
    });
  });

  group('buildRequest — body shape', () {
    test('extracts system parts, sets headers', () {
      final built = AnthropicChatTransport.buildRequest(_req());
      expect(built.body['model'], 'claude-3-5-sonnet');
      expect(built.body['system'], isA<List<dynamic>>());
      final sys = built.body['system'] as List;
      expect(sys, hasLength(1));
      expect(sys[0], {'type': 'text', 'text': 'you are helpful'});

      expect(built.headers['x-api-key'], 'sk-ant-test');
      expect(built.headers['anthropic-version'], '2023-06-01');
      expect(built.headers.containsKey('anthropic-beta'), isFalse);
    });

    test('omits system when no leading system messages', () {
      final built = AnthropicChatTransport.buildRequest(
        _req(messages: [
          {'role': 'user', 'content': 'hi'},
        ]),
      );
      expect(built.body.containsKey('system'), isFalse);
    });

    test('temperature/top_p preserved by default', () {
      final built = AnthropicChatTransport.buildRequest(_req());
      expect(built.body['temperature'], 0.7);
      expect(built.body['top_p'], 0.9);
    });

    test('detects prefill from trailing assistant turn', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        messages: [
          {'role': 'system', 'content': 'sys'},
          {'role': 'user', 'content': 'q'},
          {'role': 'assistant', 'content': 'Continuing:  '},
        ],
      ));
      expect(built.prefill, 'Continuing:');
      // Trailing assistant message stays in messages array.
      final lastMsg =
          (built.body['messages'] as List).last as Map<String, dynamic>;
      expect(lastMsg['role'], 'assistant');
    });
  });

  group('buildRequest — thinking', () {
    test('traditional thinking adds enabled+budget, drops sampling', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        model: 'claude-3-7-sonnet',
        requestReasoning: true,
        reasoningEffort: 'medium',
        maxTokens: 10000,
      ));
      expect(built.body['thinking'], isA<Map<dynamic, dynamic>>());
      final thinking = built.body['thinking'] as Map;
      expect(thinking['type'], 'enabled');
      expect(thinking['budget_tokens'], 2500); // 25% of 10000
      // Sampling controls dropped.
      expect(built.body.containsKey('temperature'), isFalse);
      expect(built.body.containsKey('top_p'), isFalse);
    });

    test('thinking with small max_tokens bumps it up for response budget', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        model: 'claude-3-7-sonnet',
        requestReasoning: true,
        reasoningEffort: 'medium',
        maxTokens: 500, // below 1024 minimum response budget
      ));
      expect(built.body['max_tokens'], 1524); // 500 + 1024
    });

    test('adaptive thinking for Opus 4.7+: type=adaptive, effort=string', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        model: 'claude-opus-4-7',
        requestReasoning: true,
        reasoningEffort: 'medium',
      ));
      final thinking = built.body['thinking'] as Map;
      expect(thinking['type'], 'adaptive');
      final output = built.body['output_config'] as Map;
      expect(output['effort'], 'medium');
    });

    test('thinking drops trailing assistant turn (prefill disabled)', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        model: 'claude-3-7-sonnet',
        requestReasoning: true,
        reasoningEffort: 'medium',
        messages: [
          {'role': 'system', 'content': 'sys'},
          {'role': 'user', 'content': 'q'},
          {'role': 'assistant', 'content': 'prefill text  '},
        ],
      ));
      expect(built.prefill, isNull);
      final messages = built.body['messages'] as List;
      expect(messages.last['role'], 'user');
    });

    test('no thinking when requestReasoning is false', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        model: 'claude-3-7-sonnet',
        requestReasoning: false,
        reasoningEffort: 'high',
      ));
      expect(built.body.containsKey('thinking'), isFalse);
    });
  });

  group('buildRequest — cache control', () {
    test('5min ttl adds ephemeral marker on last system part + beta header', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        cacheControlTtl: '5min',
      ));
      final sys = built.body['system'] as List;
      expect(sys.last['cache_control'], {'type': 'ephemeral', 'ttl': '5m'});
      expect(built.headers['anthropic-beta'],
          contains('prompt-caching-2024-07-31'));
    });

    test('1h ttl', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        cacheControlTtl: '1h',
      ));
      final sys = built.body['system'] as List;
      expect(sys.last['cache_control'], {'type': 'ephemeral', 'ttl': '1h'});
    });

    test('off ttl → no caching', () {
      final built = AnthropicChatTransport.buildRequest(_req(
        cacheControlTtl: 'off',
      ));
      final sys = built.body['system'] as List;
      expect(sys.last.containsKey('cache_control'), isFalse);
      expect(built.headers.containsKey('anthropic-beta'), isFalse);
    });
  });

  group('applyCacheAtDepth helper', () {
    test('marks at depth=2 skipping trailing assistant prefill', () {
      // Walking back from end:
      //   [4] assistant (prefill, skipped)
      //   [3] user      → depth=0
      //   [2] assistant → depth=1
      //   [1] user      → depth=2 ✓ mark
      //   [0] user      → same role, no flip
      final r = AnthropicChatTransport.applyCacheAtDepthForTest(
        [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'u0'},
            ],
          },
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'u1'},
            ],
          },
          {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'a'},
            ],
          },
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'u3'},
            ],
          },
          {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': ''},
            ],
          },
        ],
        2,
        '5m',
      );
      final marked = r[1]['content'] as List;
      expect(marked.last['cache_control'], {'type': 'ephemeral', 'ttl': '5m'});
    });
  });
}
