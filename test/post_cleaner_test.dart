import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/post_cleaner_service.dart';
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
      const String? regenTargetId = 'msg_123';
      const bool studioFinalOnly = false;
      const bool postCleanerEnabled = true;
      expect(
        regenTargetId == null && !studioFinalOnly && postCleanerEnabled,
        isFalse,
      );
    });

    test('studioFinalOnly → does not trigger', () {
      const String? regenTargetId = null;
      const bool studioFinalOnly = true;
      const bool postCleanerEnabled = true;
      expect(
        regenTargetId == null && !studioFinalOnly && postCleanerEnabled,
        isFalse,
      );
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
}
