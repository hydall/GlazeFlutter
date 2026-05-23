// Tests that guard WebView JS/CSS assets against regressions introduced by
// upstream UI rewrites (e.g. hydall/GlazeFlutter PRs).
//
// These are intentionally static-analysis tests — they read the source files
// as strings and assert that critical CSS rules / JS patterns are present.
// This catches the class of bug where a CSS property is silently removed
// during a large refactor.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _asset(String name) =>
    File('assets/chat_webview/$name').readAsStringSync();

void main() {
  late String rendererJs;
  late String bridgeJs;
  late String indexHtml;
  late String stylessCss;

  setUpAll(() {
    rendererJs = _asset('renderer.js');
    bridgeJs = _asset('bridge.js');
    indexHtml = _asset('index.html');
    stylessCss = _asset('styles.css');
  });

  // ─── details/summary arrow ────────────────────────────────────────────────
  group('details/summary arrow (SHADOW_STYLE in renderer.js)', () {
    test('::-webkit-details-marker is hidden', () {
      expect(rendererJs, contains('::-webkit-details-marker { display: none !important; }'));
    });

    test('::marker is hidden', () {
      expect(rendererJs, contains('::marker { display: none !important;'));
    });

    test('::before is disabled (arrow injected as real DOM span instead)', () {
      // display:flex on <summary> is ignored in some Android WebView versions.
      // The arrow is injected as a real .glaze-arrow <span> by _fixDetailsSummaryArrows()
      // so it always participates in flex layout correctly.
      final beforeBlock = _extractSummaryBeforeBlock(rendererJs);
      expect(
        beforeBlock,
        contains('display: none !important'),
        reason: '::before must be hidden — real DOM .glaze-arrow span is used instead',
      );
    });

    test('.glaze-arrow span is styled', () {
      expect(rendererJs, contains('.glaze-arrow {'),
          reason: 'Real DOM arrow span must have CSS styles');
      expect(rendererJs, contains('transition: transform 0.2s'),
          reason: '.glaze-arrow must have rotation transition');
    });

    test('.glaze-arrow-open rotates 90deg when details is open', () {
      expect(rendererJs, contains('.glaze-arrow.glaze-arrow-open { transform: rotate(90deg); }'));
    });

    test('_fixDetailsSummaryArrows injects .glaze-arrow into every summary', () {
      expect(rendererJs, contains('_fixDetailsSummaryArrows'));
      expect(rendererJs, contains("arrow.className = 'glaze-arrow'"));
    });

    test('_writeShadowContent calls _fixDetailsSummaryArrows after innerHTML', () {
      // Must be called AFTER root.innerHTML so it sees the inserted <details>.
      final writeBlock = _extractWriteShadowContent(rendererJs);
      final innerIdx = writeBlock.indexOf('root.innerHTML');
      final fixIdx   = writeBlock.indexOf('_fixDetailsSummaryArrows');
      expect(innerIdx, isNot(-1), reason: 'root.innerHTML must be present');
      expect(fixIdx,   isNot(-1), reason: '_fixDetailsSummaryArrows must be called');
      expect(fixIdx > innerIdx, isTrue,
          reason: '_fixDetailsSummaryArrows must be called AFTER root.innerHTML = formatted');
    });
  });

  // ─── edit textarea scroll speed ───────────────────────────────────────────
  group('edit textarea wheel scroll (bridge.js)', () {
    test('wheel listener on textarea uses preventDefault (not passive)', () {
      // passive:true prevents preventDefault — the scroll speed multiplier
      // requires preventDefault so we can set scrollTop manually.
      final wheelSection = _extractTextareaWheelListener(bridgeJs);
      expect(
        wheelSection,
        contains('preventDefault'),
        reason: 'textarea wheel listener must call preventDefault to control scroll speed',
      );
      expect(
        wheelSection,
        isNot(contains("{ passive: true }")),
        reason:
            'passive:true prevents preventDefault; listener must be passive:false '
            'or omit the option to allow manual scrollTop control',
      );
    });

    test('wheel listener applies 0.3 multiplier for pixel-mode scroll (deltaMode 0)', () {
      final wheelSection = _extractTextareaWheelListener(bridgeJs);
      expect(
        wheelSection,
        contains('deltaMode === 0'),
        reason: 'must handle deltaMode 0 (pixel scroll from trackpad/mouse)',
      );
      expect(
        wheelSection,
        contains('deltaY * 0.3'),
        reason: '0.3 multiplier slows down fast trackpad/mouse scroll in the textarea',
      );
    });

    test('wheel listener applies line multiplier for line-mode scroll (deltaMode 1)', () {
      final wheelSection = _extractTextareaWheelListener(bridgeJs);
      expect(
        wheelSection,
        contains('deltaMode === 1'),
      );
      expect(
        wheelSection,
        contains('deltaY * 16'),
        reason: '16px per line is the correct line-mode multiplier for the textarea',
      );
    });

    test('wheel listener calls stopPropagation to prevent chat container from also scrolling', () {
      final wheelSection = _extractTextareaWheelListener(bridgeJs);
      expect(
        wheelSection,
        contains('stopPropagation'),
      );
    });
  });

  // ─── main chat container scroll speed ────────────────────────────────────
  group('chat container wheel scroll (index.html)', () {
    test('chat container wheel listener is registered', () {
      expect(indexHtml, contains("container.addEventListener('wheel'"));
    });

    test('pixel-mode scroll uses 0.3 multiplier', () {
      expect(
        indexHtml,
        contains('deltaY * 0.3'),
        reason: 'Chat container scroll must use 0.3 multiplier for pixel-mode events',
      );
    });

    test('line-mode scroll uses 16px multiplier', () {
      expect(
        indexHtml,
        contains('deltaY * 16'),
        reason: 'Chat container scroll must use 16px-per-line for line-mode events',
      );
    });

    test('wheel listener is not passive (requires preventDefault)', () {
      // The chat container listener calls preventDefault to suppress native scroll
      // and replace it with the manually-scaled scrollTop assignment.
      expect(
        indexHtml,
        contains('passive: false'),
        reason: 'Chat container wheel listener must be passive:false to allow preventDefault',
      );
    });
  });

  // ─── edit textarea CSS (styles.css) ───────────────────────────────────────
  group('edit textarea CSS (styles.css)', () {
    test('overscroll-behavior:contain prevents scroll bleed to parent', () {
      expect(
        stylessCss,
        contains('overscroll-behavior: contain'),
        reason:
            'Without overscroll-behavior:contain, reaching the end of the textarea '
            'causes the parent chat container to scroll',
      );
    });
  });
}

// ─── helpers ──────────────────────────────────────────────────────────────────

/// Extracts the SHADOW_STYLE template literal from renderer.js.
/// Returns everything between `const SHADOW_STYLE = \`` and the closing backtick.
String _extractShadowStyle(String src) {
  final start = src.indexOf('const SHADOW_STYLE = `');
  if (start == -1) return '';
  final contentStart = src.indexOf('`', start) + 1;
  final end = src.indexOf('`', contentStart);
  if (end == -1) return '';
  return src.substring(contentStart, end);
}

/// Extracts the summary::before CSS block from SHADOW_STYLE in renderer.js.
String _extractSummaryBeforeBlock(String src) {
  final marker = 'summary::before {';
  final idx = src.indexOf(marker);
  if (idx == -1) return '';
  final end = src.indexOf('}', idx);
  if (end == -1) return src.substring(idx);
  return src.substring(idx, end + 1);
}

/// Extracts the _writeShadowContent method body from renderer.js.
/// Looks for the definition (not a call), i.e. the line that starts with the name.
String _extractWriteShadowContent(String src) {
  // Match the method definition: starts at column 2 with _writeShadowContent
  final marker = '  _writeShadowContent(';
  int idx = src.indexOf(marker);
  // Skip to the next occurrence if this is a call inside another method
  while (idx != -1) {
    // It's a definition if it's followed by a parameter list then `{`
    final lineEnd = src.indexOf('\n', idx);
    final line = lineEnd != -1 ? src.substring(idx, lineEnd) : src.substring(idx);
    if (line.contains(') {') || line.endsWith('{')) break;
    idx = src.indexOf(marker, idx + 1);
  }
  if (idx == -1) return '';
  int depth = 0;
  int start = src.indexOf('{', idx);
  if (start == -1) return '';
  for (int i = start; i < src.length; i++) {
    if (src[i] == '{') depth++;
    else if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return src.substring(start);
}

/// Extracts the textarea wheel event listener block from bridge.js.
/// Returns the portion of code starting at the wheel addEventListener call
/// through the closing `}, {` options object.
String _extractTextareaWheelListener(String src) {
  final marker = "addEventListener('wheel'";
  // Find the one inside startEdit (textarea context), not the container one.
  // We look for the occurrence that is preceded by 'textarea' within ~300 chars.
  int pos = 0;
  while (true) {
    final idx = src.indexOf(marker, pos);
    if (idx == -1) break;
    final context = src.substring(idx > 300 ? idx - 300 : 0, idx);
    if (context.contains('textarea')) {
      // Extract from this point to the end of the listener (closing });)
      final end = src.indexOf('});', idx);
      if (end == -1) return src.substring(idx);
      return src.substring(idx, end + 3);
    }
    pos = idx + 1;
  }
  return '';
}
