import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/context_calculator.dart';
import 'package:glaze_flutter/core/llm/history_assembler.dart';

/// Regression tests for the completion-budget reservation in
/// [ContextCalculator]. The provider enforces
/// `prompt_tokens + max_tokens <= contextSize`; the transport layer sends
/// `max_tokens` with every request. If the prompt is allowed to fill the whole
/// context window the model has no room to answer and returns an empty
/// completion. [ContextCalculator.safeContext] must therefore reserve
/// [maxTokens] before allocating the history budget.
void main() {
  PromptMessage userTurn(String id, String content) => PromptMessage(
    role: 'user',
    content: content,
    isHistory: true,
    sourceMessageId: id,
  );

  group('ContextCalculator completion-budget reservation', () {
    test('safeContext reserves maxTokens for the response', () {
      final calc = ContextCalculator(contextSize: 150000, maxTokens: 15000);
      expect(calc.safeContext, 135000);
    });

    test('historyBudget leaves room for the completion', () {
      final calc = ContextCalculator(contextSize: 1000, maxTokens: 400);
      final breakdown = calc.calculate(
        staticBlocks: const [],
        historyMessages: [userTurn('m1', 'hello there')],
      );
      // contextSize - maxTokens = 600, no static blocks => 600 budget.
      expect(breakdown.historyBudget, 600);
    });

    test('large memory does not starve the completion budget', () {
      final calc = ContextCalculator(contextSize: 1000, maxTokens: 400);
      // Memory eats most of the *prompt* window, but the 400-token completion
      // reservation is still honoured: historyBudget = 600 - 550 = 50, not
      // 1000 - 550 = 450.
      final breakdown = calc.calculate(
        staticBlocks: const [],
        historyMessages: [userTurn('m1', 'short turn')],
        memoryTokens: 550,
      );
      expect(breakdown.historyBudget, 50);
    });

    test(
      'misconfigured maxTokens >= contextSize clamps safeContext to zero',
      () {
        final calc = ContextCalculator(contextSize: 4000, maxTokens: 8000);
        expect(calc.safeContext, 0);
        final breakdown = calc.calculate(
          staticBlocks: const [],
          historyMessages: [userTurn('m1', 'will be dropped')],
        );
        expect(breakdown.historyBudget, 0);
        // History is fully cut off, but the calculator does not throw.
        expect(breakdown.cutoffIndex, 1);
        expect(breakdown.trimmedHistory, isEmpty);
      },
    );
  });
}
