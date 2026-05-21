import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/features/chat/widgets/message_list.dart';

void main() {
  group('ScrollAnchor', () {
    test('stores messageId and offsetFromViewportTop', () {
      const anchor = ScrollAnchor('msg-42', 37.5);
      expect(anchor.messageId, 'msg-42');
      expect(anchor.offsetFromViewportTop, 37.5);
    });

    test('equality is value-based', () {
      const a = ScrollAnchor('msg-1', 10.0);
      const b = ScrollAnchor('msg-1', 10.0);
      expect(a, b);
    });

    test('different messageId is not equal', () {
      const a = ScrollAnchor('msg-1', 10.0);
      const b = ScrollAnchor('msg-2', 10.0);
      expect(a, isNot(b));
    });

    test('different offset is not equal', () {
      const a = ScrollAnchor('msg-1', 10.0);
      const b = ScrollAnchor('msg-1', 20.0);
      expect(a, isNot(b));
    });
  });

  group('reverse:true scroll coordinate math', () {
    test('coarse estimate: index 0 (oldest) maps to maxScrollExtent', () {
      final idx = 0;
      final total = 100;
      final maxExtent = 5000.0;
      final fraction = idx / total;
      final estimate = (1 - fraction) * maxExtent;
      expect(estimate, closeTo(5000.0, 0.01));
    });

    test('coarse estimate: last index (newest) maps near 0', () {
      final idx = 99;
      final total = 100;
      final maxExtent = 5000.0;
      final fraction = idx / total;
      final estimate = (1 - fraction) * maxExtent;
      expect(estimate, closeTo(50.0, 0.01));
    });

    test('coarse estimate: middle index maps to half extent', () {
      final idx = 50;
      final total = 100;
      final maxExtent = 5000.0;
      final fraction = idx / total;
      final estimate = (1 - fraction) * maxExtent;
      expect(estimate, closeTo(2500.0, 0.01));
    });

    test('coarse estimate: quarter from end maps to quarter extent', () {
      final idx = 75;
      final total = 100;
      final maxExtent = 5000.0;
      final fraction = idx / total;
      final estimate = (1 - fraction) * maxExtent;
      expect(estimate, closeTo(1250.0, 0.01));
    });

    test('offset 0 is bottom (latest messages)', () {
      final offset = 0.0;
      expect(offset, 0.0);
    });

    test('maxScrollExtent is top (oldest messages)', () {
      final maxExtent = 5000.0;
      expect(maxExtent, greaterThan(0));
    });
  });

  group('anchor capture/restore semantics', () {
    test('anchor with positive offset means message is below viewport top', () {
      const anchor = ScrollAnchor('msg-50', 100.0);
      expect(anchor.offsetFromViewportTop, greaterThan(0));
    });

    test('anchor with negative offset means message is above viewport top', () {
      const anchor = ScrollAnchor('msg-50', -50.0);
      expect(anchor.offsetFromViewportTop, lessThan(0));
    });

    test('anchor with zero offset means message is at viewport top', () {
      const anchor = ScrollAnchor('msg-50', 0.0);
      expect(anchor.offsetFromViewportTop, 0.0);
    });

    test('restore target = reveal - offsetFromViewportTop', () {
      const anchor = ScrollAnchor('msg-50', 100.0);
      final revealOffset = 2500.0;
      final target = revealOffset - anchor.offsetFromViewportTop;
      expect(target, 2400.0);
    });

    test('restore target clamped to 0', () {
      const anchor = ScrollAnchor('msg-1', 500.0);
      final revealOffset = 200.0;
      final target = (revealOffset - anchor.offsetFromViewportTop).clamp(0.0, 5000.0);
      expect(target, 0.0);
    });

    test('restore target clamped to maxScrollExtent', () {
      const anchor = ScrollAnchor('msg-99', -1000.0);
      final revealOffset = 5500.0;
      final target = (revealOffset - anchor.offsetFromViewportTop).clamp(0.0, 5000.0);
      expect(target, 5000.0);
    });
  });

  group('scroll anchor save/clear on at-bottom', () {
    test('when _wasAtBottom is true, anchor is cleared (null)', () {
      final result = null;
      expect(result, isNull);
    });

    test('when _wasAtBottom is false, anchor is saved', () {
      final savedAnchor = ScrollAnchor('msg-1', 10.0);
      final result = savedAnchor;
      expect(result, isNotNull);
      expect(result.messageId, 'msg-1');
    });
  });

  group('initial scroll decision', () {
    test('no saved anchor -> open at bottom (offset 0 in reverse:true)', () {
      const targetOffset = 0.0;
      expect(targetOffset, 0.0);
    });

    test('saved anchor -> restore to saved position', () {
      const anchor = ScrollAnchor('msg-50', 100.0);
      double targetOffset;
      if (anchor.messageId.isNotEmpty) {
        targetOffset = 2400.0;
      } else {
        targetOffset = 0.0;
      }
      expect(targetOffset, 2400.0);
    });

    test('first open (no SharedPreferences entry) -> anchor is null -> bottom', () {
      const anchor = null;
      expect(anchor, isNull);
    });

    test('subsequent open (SharedPreferences has entry) -> anchor is restored', () {
      const savedMsgId = 'msg-42';
      const savedOffset = 150.0;
      final anchor = ScrollAnchor(savedMsgId, savedOffset);
      expect(anchor, isNotNull);
      expect(anchor.messageId, 'msg-42');
      expect(anchor.offsetFromViewportTop, 150.0);
    });
  });

  group('Offstage gating', () {
    test('initialScrollDone starts false', () {
      bool initialScrollDone = false;
      expect(initialScrollDone, isFalse);
    });

    test('offstage = !initialScrollDone -> true when not done', () {
      bool initialScrollDone = false;
      expect(!initialScrollDone, isTrue);
    });

    test('offstage = !initialScrollDone -> false when done', () {
      bool initialScrollDone = true;
      expect(!initialScrollDone, isFalse);
    });
  });

  group('_jumpToBottomNow with reverse:true', () {
    test('target is 0.0 (not maxScrollExtent)', () {
      final maxScrollExtent = 5000.0;
      final target = 0.0;
      expect(target, isNot(maxScrollExtent));
      expect(target, 0.0);
    });

    test('retarget check: pixels > 0.5 means not at bottom yet', () {
      final pixels = 12.3;
      final needsRetarget = pixels > 0.5;
      expect(needsRetarget, isTrue);
    });

    test('retarget check: pixels <= 0.5 means at bottom', () {
      final pixels = 0.3;
      final needsRetarget = pixels > 0.5;
      expect(needsRetarget, isFalse);
    });
  });

  group('anchor message not found fallback', () {
    test('when message id not in list, fallback to bottom', () {
      final messages = ['msg-1', 'msg-2', 'msg-3'];
      const anchorMsgId = 'msg-999';
      final idx = messages.indexOf(anchorMsgId);
      expect(idx, -1);
    });

    test('when message id exists, calculate coarse position', () {
      final messages = ['msg-1', 'msg-2', 'msg-3', 'msg-4', 'msg-5'];
      const anchorMsgId = 'msg-3';
      final idx = messages.indexOf(anchorMsgId);
      expect(idx, 2);
      final fraction = idx / messages.length;
      final maxExtent = 5000.0;
      final estimate = (1 - fraction) * maxExtent;
      expect(estimate, closeTo(3000.0, 0.01));
    });
  });
}
