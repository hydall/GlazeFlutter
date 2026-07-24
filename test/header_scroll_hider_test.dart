import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/shared/shell/header_scroll_hider.dart';

/// Builds a vertical [ScrollUpdateNotification] at [pixels] on a list that is
/// [maxExtent] tall, which is what [HeaderScrollHider.handle] reads.
ScrollUpdateNotification _scrollTo(double pixels, {double maxExtent = 5000}) {
  return ScrollUpdateNotification(
    metrics: FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: maxExtent,
      pixels: pixels,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    ),
    context: null,
  );
}

void main() {
  group('HeaderScrollHider', () {
    late HeaderScrollHider hider;
    late List<bool> emitted;
    void feed(double pixels) => hider.handle(_scrollTo(pixels), emitted.add);

    setUp(() {
      hider = HeaderScrollHider();
      emitted = <bool>[];
    });

    test('hides on downward scroll and reveals on upward scroll', () {
      feed(400);
      expect(emitted, [true]);
      expect(hider.hidden, isTrue);

      feed(200);
      expect(emitted, [true, false]);
      expect(hider.hidden, isFalse);
    });

    test('reset clears the hidden state so the next hide is not swallowed', () {
      feed(400);
      expect(hider.hidden, isTrue);

      hider.reset();
      expect(hider.hidden, isFalse);

      // Without the reset the hider would still believe the header is hidden
      // and emit nothing here, leaving it stuck visible.
      emitted.clear();
      feed(400); // re-baselines on the first notification after a reset
      feed(600);
      expect(emitted, [true]);
    });

    test('reset absorbs the jump to a different view scroll offset', () {
      hider.reset();

      // A tab switch lands the hider on a list already scrolled far down. The
      // difference is not a gesture, so it must not hide the header.
      feed(2000);
      expect(emitted, isEmpty);
      expect(hider.hidden, isFalse);

      // Scrolling further down from there is a real gesture and does hide it.
      feed(2100);
      expect(emitted, [true]);
    });

    test('ignores horizontal scrollables', () {
      hider.handle(
        ScrollUpdateNotification(
          metrics: const FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 5000,
            pixels: 400,
            viewportDimension: 800,
            axisDirection: AxisDirection.right,
            devicePixelRatio: 1,
          ),
          context: null,
        ),
        emitted.add,
      );
      expect(emitted, isEmpty);
    });
  });
}
