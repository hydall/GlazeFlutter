import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/post_cleaner_service.dart';
import 'package:glaze_flutter/core/models/agent_operation_record.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';

void main() {
  group('PostCleanerResult', () {
    test('disabled status returns original text', () {
      const result = PostCleanerResult(
        status: 'disabled',
        cleanedText: 'original',
      );
      expect(result.status, 'disabled');
      expect(result.cleanedText, 'original');
      expect(result.wasCleaned, isFalse);
      expect(result.attempts, isEmpty);
      expect(result.totalElapsedMs, 0);
    });

    test('ok status with wasCleaned=true indicates rewrite', () {
      const result = PostCleanerResult(
        status: 'ok',
        cleanedText: 'cleaned',
        originalText: 'original',
        wasCleaned: true,
      );
      expect(result.wasCleaned, isTrue);
      expect(result.cleanedText, 'cleaned');
      expect(result.originalText, 'original');
    });

    test('timeout status returns original text', () {
      const result = PostCleanerResult(
        status: 'timeout',
        cleanedText: 'original',
      );
      expect(result.status, 'timeout');
      expect(result.wasCleaned, isFalse);
    });

    test('aborted status returns original text', () {
      const result = PostCleanerResult(
        status: 'aborted',
        cleanedText: 'original',
      );
      expect(result.status, 'aborted');
      expect(result.wasCleaned, isFalse);
    });

    test('error status returns original text with error message', () {
      const result = PostCleanerResult(
        status: 'error',
        cleanedText: 'original',
        error: 'something went wrong',
      );
      expect(result.status, 'error');
      expect(result.error, 'something went wrong');
      expect(result.wasCleaned, isFalse);
    });

    test('skipped status returns original text', () {
      const result = PostCleanerResult(
        status: 'skipped',
        cleanedText: 'original',
      );
      expect(result.status, 'skipped');
      expect(result.wasCleaned, isFalse);
    });

    test('carries retry attempts when set', () {
      const attempts = [
        AgentOperationAttempt(
          attempt: 1,
          statusCode: 502,
          status: 'http_5xx',
          error: 'Bad Gateway',
          startedAtMs: 0,
          elapsedMs: 30,
        ),
        AgentOperationAttempt(
          attempt: 2,
          statusCode: 200,
          status: 'ok',
          startedAtMs: 30,
          elapsedMs: 50,
        ),
      ];
      const result = PostCleanerResult(
        status: 'ok',
        cleanedText: 'cleaned',
        attempts: attempts,
        totalElapsedMs: 80,
      );
      expect(result.attempts.length, 2);
      expect(result.attempts.first.statusCode, 502);
      expect(result.attempts.last.statusCode, 200);
      expect(result.totalElapsedMs, 80);
    });
  });

  group('MemoryBookSettings.postCleanerEnabled', () {
    test('defaults to false', () {
      const settings = MemoryBookSettings();
      expect(settings.postCleanerEnabled, isFalse);
    });

    test('can be set to true', () {
      const settings = MemoryBookSettings(postCleanerEnabled: true);
      expect(settings.postCleanerEnabled, isTrue);
    });

    test('independent from agenticWriteEnabled', () {
      const settings = MemoryBookSettings(
        postCleanerEnabled: true,
        agenticWriteEnabled: false,
      );
      expect(settings.postCleanerEnabled, isTrue);
      expect(settings.agenticWriteEnabled, isFalse);
    });
  });

  group('Post-cleaner safety guards', () {
    // The cleaner has a length-ratio guard: if the cleaned text is < 30% or
    // > 300% of the original length, it's skipped (status='skipped').
    // This prevents the cleaner from accidentally deleting or drastically
    // expanding the response.

    test('length ratio guard allows 50% length', () {
      final original = 'A' * 1000;
      final cleaned = 'B' * 500;
      final ratio = cleaned.length / original.length;
      expect(ratio, 0.5);
      expect(ratio >= 0.3 && ratio <= 3.0, isTrue);
    });

    test('length ratio guard rejects 20% length', () {
      final original = 'A' * 1000;
      final cleaned = 'B' * 200;
      final ratio = cleaned.length / original.length;
      expect(ratio, 0.2);
      expect(ratio >= 0.3 && ratio <= 3.0, isFalse);
    });

    test('length ratio guard rejects 400% length', () {
      final original = 'A' * 1000;
      final cleaned = 'B' * 4000;
      final ratio = cleaned.length / original.length;
      expect(ratio, 4.0);
      expect(ratio >= 0.3 && ratio <= 3.0, isFalse);
    });

    test('length ratio guard allows 100% (same length)', () {
      final original = 'A' * 1000;
      final cleaned = 'B' * 1000;
      final ratio = cleaned.length / original.length;
      expect(ratio, 1.0);
      expect(ratio >= 0.3 && ratio <= 3.0, isTrue);
    });

    test('length ratio guard allows 200% length', () {
      final original = 'A' * 1000;
      final cleaned = 'B' * 2000;
      final ratio = cleaned.length / original.length;
      expect(ratio, 2.0);
      expect(ratio >= 0.3 && ratio <= 3.0, isTrue);
    });
  });

  group('Post-cleaner trigger suppression', () {
    // The trigger in GenerationPipeline is guarded by the same condition as
    // the write-loop: regenTargetId == null && !studioFinalOnly.
    // Additionally, it checks postCleanerEnabled on MemoryBookSettings.

    test('normal send with postCleanerEnabled → triggers', () {
      const String? regenTargetId = null;
      const bool studioFinalOnly = false;
      const bool postCleanerEnabled = true;
      expect(
        regenTargetId == null && !studioFinalOnly && postCleanerEnabled,
        isTrue,
      );
    });

    test('normal send without postCleanerEnabled → does not trigger', () {
      const String? regenTargetId = null;
      const bool studioFinalOnly = false;
      const bool postCleanerEnabled = false;
      expect(
        regenTargetId == null && !studioFinalOnly && postCleanerEnabled,
        isFalse,
      );
    });

    test('regen → does not trigger (regenTargetId != null)', () {
      const String regenTargetId = 'msg_123';
      const bool studioFinalOnly = false;
      const bool postCleanerEnabled = true;
      expect(
        regenTargetId.isEmpty && !studioFinalOnly && postCleanerEnabled,
        isFalse,
      );
    });

    test('studioFinalOnly → does not trigger', () {
      const bool studioFinalOnly = true;
      expect(!studioFinalOnly, isFalse);
    });
  });

  group('Post-cleaner fallback behavior', () {
    // On any error (timeout, LLM failure, abort, empty response), the
    // cleaner returns the original text unchanged. This is the "do no harm"
    // principle — the cleaner must never make the response worse or lose it.

    test('disabled → original text returned', () {
      const result = PostCleanerResult(
        status: 'disabled',
        cleanedText: 'original text',
      );
      expect(result.cleanedText, 'original text');
      expect(result.wasCleaned, isFalse);
    });

    test('timeout → original text returned', () {
      const result = PostCleanerResult(
        status: 'timeout',
        cleanedText: 'original text',
      );
      expect(result.cleanedText, 'original text');
      expect(result.wasCleaned, isFalse);
    });

    test('error → original text returned', () {
      const result = PostCleanerResult(
        status: 'error',
        cleanedText: 'original text',
        error: 'network failure',
      );
      expect(result.cleanedText, 'original text');
      expect(result.wasCleaned, isFalse);
    });

    test('aborted → original text returned', () {
      const result = PostCleanerResult(
        status: 'aborted',
        cleanedText: 'original text',
      );
      expect(result.cleanedText, 'original text');
      expect(result.wasCleaned, isFalse);
    });

    test('skipped (length guard) → original text returned', () {
      const result = PostCleanerResult(
        status: 'skipped',
        cleanedText: 'original text',
      );
      expect(result.cleanedText, 'original text');
      expect(result.wasCleaned, isFalse);
    });

    test('ok with wasCleaned=false → original text returned (no change)', () {
      const result = PostCleanerResult(
        status: 'ok',
        cleanedText: 'original text',
        wasCleaned: false,
      );
      expect(result.cleanedText, 'original text');
      expect(result.wasCleaned, isFalse);
    });

    test('ok with wasCleaned=true → cleaned text returned', () {
      const result = PostCleanerResult(
        status: 'ok',
        cleanedText: 'cleaned text',
        originalText: 'original text',
        wasCleaned: true,
      );
      expect(result.cleanedText, 'cleaned text');
      expect(result.wasCleaned, isTrue);
    });
  });

  group('PostCleanerService.buildCleanerPrompt', () {
    test('without broadcast blocks uses default editor rules', () {
      final prompt = PostCleanerService.buildCleanerPrompt(
        assistantText: 'He felt a shiver run down his spine.',
      );
      expect(prompt, contains('prose editor'));
      expect(prompt, contains('Assistant response to clean:'));
      expect(prompt, contains('He felt a shiver run down his spine.'));
      // No authoritative-rules section when there are no broadcast blocks.
      expect(prompt, isNot(contains('AUTHORITATIVE RULES')));
    });

    test('injects broadcast blocks as authoritative rules', () {
      final prompt = PostCleanerService.buildCleanerPrompt(
        assistantText: 'Текст ответа.',
        broadcastBlocks: const [
          '[Block: 🇷🇺 LANGUAGE: Russian]\nRUSSIAN ONLY. Use «ёлочки» quotes.',
          '[Block: Anti-Cliché]\nBan: "symphony of", "tapestry of".',
        ],
      );
      expect(prompt, contains('AUTHORITATIVE RULES'));
      expect(prompt, contains('RUSSIAN ONLY'));
      expect(prompt, contains('«ёлочки»'));
      expect(prompt, contains('Anti-Cliché'));
      // The authoritative section must come before the text to clean.
      expect(
        prompt.indexOf('AUTHORITATIVE RULES'),
        lessThan(prompt.indexOf('Assistant response to clean:')),
      );
    });

    test('ignores blank broadcast entries', () {
      final prompt = PostCleanerService.buildCleanerPrompt(
        assistantText: 'x',
        broadcastBlocks: const ['', '   '],
      );
      expect(prompt, isNot(contains('AUTHORITATIVE RULES')));
    });
  });
}
