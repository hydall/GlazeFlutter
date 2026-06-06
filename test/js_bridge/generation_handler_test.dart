import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/features/extensions/services/js_bridge/handlers/generation_handler.dart';
import 'package:glaze_flutter/features/extensions/services/js_bridge/js_bridge_context.dart';

void main() {
  group('GenerationHandler', () {
    test('generateText validates preset before delegating', () async {
      final handler = GenerationHandler();
      final bridge = JsBridgeContext(
        params: {
          'prompt': 'Hello',
          'options': {'preset': 'tiny'},
        },
        context: const {},
        permissionCheck: (_) => true,
        generateText: (_, _, _) => throw StateError('must not delegate'),
      );

      expect(() => handler.generateText(bridge), throwsA(isA<ArgumentError>()));
    });

    test('generateText delegates prompt, options, and context', () async {
      final handler = GenerationHandler();
      final bridge = JsBridgeContext(
        params: {
          'prompt': 'Write one line',
          'options': {'preset': 'small'},
        },
        context: {'sessionId': 's1'},
        permissionCheck: (_) => true,
        generateText: (prompt, options, context) async {
          expect(prompt, 'Write one line');
          expect(options['preset'], 'small');
          expect(context['sessionId'], 's1');
          return 'ok';
        },
      );

      await expectLater(handler.generateText(bridge), completion('ok'));
    });

    test(
      'triggerGeneration resolves character id from context first',
      () async {
        final handler = GenerationHandler();
        final bridge = JsBridgeContext(
          params: {'mode': 'auto'},
          context: {'characterId': 'explicit'},
          currentCharacterId: () => 'fallback',
          permissionCheck: (_) => true,
          triggerGeneration: (charId, params) {
            return {'charId': charId, 'mode': params['mode']};
          },
        );

        expect(handler.triggerGeneration(bridge), {
          'charId': 'explicit',
          'mode': 'auto',
        });
      },
    );

    test('default-denies when permission check is missing', () {
      final handler = GenerationHandler();
      final bridge = JsBridgeContext(
        params: {'prompt': 'Hello'},
        context: const {},
        generateText: (_, _, _) async => 'must not run',
      );

      expect(() => handler.generateText(bridge), throwsA(isA<StateError>()));
    });
  });
}
