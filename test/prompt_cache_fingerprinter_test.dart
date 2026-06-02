import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/prompt_cache_fingerprinter.dart';

void main() {
  group('fingerprintMessages', () {
    test('identical messages hash identically', () {
      final a = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'A'},
        {'role': 'user', 'content': 'B'},
      ];
      final b = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'A'},
        {'role': 'user', 'content': 'B'},
      ];
      expect(fingerprintMessages(a), fingerprintMessages(b));
    });

    test('role-only change breaks hash', () {
      final a = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'A'},
      ];
      final b = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'A'},
      ];
      expect(fingerprintMessages(a).first, isNot(fingerprintMessages(b).first));
    });

    test('cache_control block does not change the fingerprint of the message', () {
      final a = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'hello'},
      ];
      final b = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': 'hello',
              'cache_control': {'type': 'ephemeral'},
            },
          ],
        },
      ];
      expect(fingerprintMessages(a).first, fingerprintMessages(b).first);
    });
  });

  group('findLastCommonPrefixIndex', () {
    test('cold start returns -1 (prev empty)', () {
      final curr = ['a', 'b', 'c'];
      expect(
        findLastCommonPrefixIndex(previous: const [], current: curr),
        -1,
      );
    });

    test('full match returns last index', () {
      final prev = ['a', 'b', 'c'];
      final curr = ['a', 'b', 'c', 'd'];
      expect(
        findLastCommonPrefixIndex(previous: prev, current: curr),
        2,
      );
    });

    test('diverging at index 1 returns 0', () {
      final prev = ['a', 'b', 'c'];
      final curr = ['a', 'X', 'c'];
      expect(
        findLastCommonPrefixIndex(previous: prev, current: curr),
        0,
      );
    });

    test('no common prefix returns -1', () {
      final prev = ['a', 'b', 'c'];
      final curr = ['x', 'y'];
      expect(
        findLastCommonPrefixIndex(previous: prev, current: curr),
        -1,
      );
    });
  });

  group('withExplicitCacheBreakpoint', () {
    test('converts string content to content block with cache_control', () {
      final m = {'role': 'user', 'content': 'hello'};
      final out = withExplicitCacheBreakpoint(m, ttl: '5min');
      expect(out['content'], isA<List<dynamic>>());
      final block = (out['content'] as List<dynamic>).first as Map<String, dynamic>;
      expect(block['type'], 'text');
      expect(block['text'], 'hello');
      expect(block['cache_control'], {'type': 'ephemeral'});
    });

    test('1h ttl sets ttl field on cache_control', () {
      final m = {'role': 'user', 'content': 'hello'};
      final out = withExplicitCacheBreakpoint(m, ttl: '1h');
      expect(out['content'], isA<List<dynamic>>());
      final block = (out['content'] as List<dynamic>).first as Map<String, dynamic>;
      expect(block['cache_control'], {'type': 'ephemeral', 'ttl': '1h'});
    });

    test('empty content is left unchanged', () {
      final m = {'role': 'user', 'content': ''};
      final out = withExplicitCacheBreakpoint(m, ttl: '5min');
      expect(out['content'], '');
    });

    test('already-structured content is left unchanged', () {
      final structured = [
        {'type': 'text', 'text': 'hi'},
      ];
      final m = {'role': 'user', 'content': structured};
      final out = withExplicitCacheBreakpoint(m, ttl: '5min');
      expect(out['content'], structured);
    });

    test('already-structured content with cache_control is left unchanged', () {
      final structured = [
        {'type': 'text', 'text': 'hi', 'cache_control': {'type': 'ephemeral'}},
      ];
      final m = {'role': 'user', 'content': structured};
      final out = withExplicitCacheBreakpoint(m, ttl: '5min');
      expect(out['content'], structured);
    });
  });

  group('end-to-end: simulating the loomledger regex bug', () {
    test('breakpoint lands on the last stable message before the regex-shifted tail', () {
      // Two consecutive requests. In request 2, the regex has re-applied
      // to the *previous* assistant messages (ledger removed) and a new
      // user/assistant pair is appended.
      final req1 = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'PRESET'},
        {'role': 'user', 'content': 'U1'},
        {'role': 'assistant', 'content': 'A1(with loomledger)'},
        {'role': 'user', 'content': 'U2'},
        {'role': 'assistant', 'content': 'A2(with loomledger)'},
        {'role': 'user', 'content': 'U3'},
        {'role': 'assistant', 'content': 'A3(with loomledger)'},
      ];
      final req2 = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'PRESET'},
        {'role': 'user', 'content': 'U1'},
        {'role': 'assistant', 'content': 'A1(no ledger)'}, // regex shifted
        {'role': 'user', 'content': 'U2'},
        {'role': 'assistant', 'content': 'A2(with loomledger)'},
        {'role': 'user', 'content': 'U3'},
        {'role': 'assistant', 'content': 'A3(with loomledger)'},
        {'role': 'user', 'content': 'U4'},
        {'role': 'assistant', 'content': 'A4(with loomledger)'},
      ];

      final prev = fingerprintMessages(req1);
      final curr = fingerprintMessages(req2);
      final last = findLastCommonPrefixIndex(previous: prev, current: curr);

      // Expected: only the system prompt + U1 (index 0..1) are byte-identical.
      // A1 just lost its loomledger (regex shifted), so any further index has
      // diverged. Optimal breakpoint is index 1 (the last U1), with everything
      // from A1 onwards recomputed.
      expect(last, 1);

      final out = [...req2];
      out[last] = withExplicitCacheBreakpoint(out[last], ttl: '5min');
      final block = (out[last]['content'] as List<dynamic>).first as Map<String, dynamic>;
      expect(block['cache_control'], {'type': 'ephemeral'});
    });
  });
}
