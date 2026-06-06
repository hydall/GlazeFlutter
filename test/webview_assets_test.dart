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
  late String glazeSdkJs;
  late String indexHtml;
  late String headlessHtml;
  late String stylessCss;

  setUpAll(() {
    rendererJs = _asset('renderer.js');
    bridgeJs = _asset('bridge.js');
    glazeSdkJs = _asset('glaze_sdk.js');
    indexHtml = _asset('index.html');
    headlessHtml = _asset('headless.html');
    stylessCss = _asset('styles.css');
  });

  group('window.glaze SDK', () {
    test('index.html loads glaze_sdk before bridge.js', () {
      final sdkIdx = indexHtml.indexOf('glaze_sdk.js');
      final bridgeIdx = indexHtml.indexOf('bridge.js');
      expect(sdkIdx, isNonNegative);
      expect(bridgeIdx, isNonNegative);
      expect(sdkIdx < bridgeIdx, isTrue);
    });

    test('SDK exposes expected window.glaze methods', () {
      for (final method in [
        'getVariables',
        'setVariables',
        'deleteVariable',
        'executeCommand',
        'triggerGeneration',
        'injectPrompt',
        'uninjectPrompt',
        'generateText',
        'showToast',
        'playAudio',
      ]) {
        expect(glazeSdkJs, contains('$method('));
      }
    });

    test('sandboxed runner relays glaze requests and ignores relay messages as final output', () {
      expect(bridgeJs, contains("data.type !== 'glaze:request'"));
      expect(bridgeJs, contains("type: 'glaze:response'"));
      expect(bridgeJs, contains('if (e.data && e.data.type) return;'));
    });
  });

  // ─── Headless engine (Phase 6.1) ────────────────────────────────────────────
  group('headless engine (headless.html)', () {
    test('loads glaze_sdk.js', () {
      expect(headlessHtml, contains('glaze_sdk.js'));
    });

    test('exposes window.headlessBridge.runSandboxedScript', () {
      expect(headlessHtml, contains('window.headlessBridge'));
      expect(
        headlessHtml,
        contains('runSandboxedScript'),
      );
    });

    test('sandbox uses allow-scripts iframe', () {
      expect(headlessHtml, contains("sandbox"));
      expect(headlessHtml, contains('allow-scripts'));
      // Must not opt into same-origin execution.
      expect(headlessHtml, isNot(contains('allow-same-origin')));
    });
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

  // ─── InteractionDispatch extraction (Phase 3.1) ────────────────────────────
  group('InteractionDispatch (bridge.js)', () {
    test('InteractionDispatch class exists', () {
      expect(bridgeJs, contains('class InteractionDispatch'));
    });

    test('handleClick method exists', () {
      expect(bridgeJs, contains('handleClick(e)'));
    });

    test('action map contains all expected data-action keys', () {
      final requiredActions = [
        'memory-click',
        'inject-click',
        'toggle-hidden',
        'toggle-image-hidden',
        'swipe-left',
        'swipe-right',
        'greeting-prev',
        'greeting-next',
        'stop',
        'regenerate',
        'toggle-guided',
        'edit-save',
        'edit-cancel',
        'open-actions',
        'img-retry',
        'img-find',
        'img-regen',
        'img-stop',
      ];
      for (final action in requiredActions) {
        expect(
          bridgeJs,
          contains("'$action':"),
          reason: 'InteractionDispatch._actionMap must contain key "$action"',
        );
      }
    });

    test('Bridge creates InteractionDispatch instance', () {
      expect(bridgeJs, contains('new InteractionDispatch(this)'));
    });

    test('click listener delegates to InteractionDispatch.handleClick', () {
      expect(
        bridgeJs,
        contains('this._interaction.handleClick(e)'),
      );
    });
  });

  // ─── GenTimer extraction (Phase 3.5) ───────────────────────────────────────
  group('GenTimer (bridge.js)', () {
    test('GenTimer class exists', () {
      expect(bridgeJs, contains('class GenTimer'));
    });

    test('GenTimer has start method', () {
      expect(bridgeJs, contains('GenTimer'));
      expect(bridgeJs, contains('start()'));
    });

    test('GenTimer has stop method', () {
      expect(bridgeJs, contains('GenTimer'));
      expect(bridgeJs, contains('stop()'));
    });

    test('Bridge creates GenTimer instance', () {
      expect(bridgeJs, contains('new GenTimer('));
    });

    test('setGenerating delegates to _genTimer.start/stop', () {
      expect(bridgeJs, contains('this._genTimer.start()'));
      expect(bridgeJs, contains('this._genTimer.stop()'));
    });
  });

  // ─── renderMessage always returns array (Phase 3.6) ────────────────────────
  group('renderMessage return type (renderer.js)', () {
    test('renderMessage returns elements array (not conditional)', () {
      final marker = 'renderMessage(messageData)';
      final idx = rendererJs.indexOf(marker);
      expect(idx, isNot(-1), reason: 'renderMessage must exist');

      final body = _extractBlockBody(rendererJs, idx);
      expect(
        body,
        isNot(contains('elements.length > 1 ? elements : messageEl')),
        reason: 'renderMessage must always return array, not conditional HTMLElement|Array',
      );
      expect(
        body,
        contains('return elements'),
        reason: 'renderMessage must return the elements array directly',
      );
    });

    test('no Array.isArray checks remain in bridge.js call sites', () {
      expect(
        bridgeJs,
        isNot(contains('Array.isArray(rendered)')),
        reason: 'All Array.isArray(rendered) checks should be removed since renderMessage always returns array',
      );
    });
  });

  // ─── selectionMode public getter (Phase 3.7) ──────────────────────────────
  group('selectionMode encapsulation (SelectionManager)', () {
    test('SelectionManager has public selectionMode getter', () {
      expect(
        bridgeJs,
        contains('get selectionMode()'),
        reason: 'SelectionManager must expose selectionMode as public getter',
      );
    });

    test('bridge.js does not access _selectionMode directly', () {
      expect(
        bridgeJs,
        isNot(contains('renderer._selectionMode')),
        reason: 'Bridge must use SelectionManager.selectionMode, not the private _selectionMode field',
      );
    });
  });

  // ─── Streaming fast path (Phase 4.1) ───────────────────────────────────────
  group('updateMessageContent fast path (renderer.js)', () {
    test('updateMessageContent has fast path for text-only updates', () {
      final marker = 'updateMessageContent(sectionEl, text, reasoning, isUser, isTyping, animate)';
      final idx = rendererJs.indexOf(marker);
      expect(idx, isNot(-1), reason: 'updateMessageContent must exist');

      final body = _extractBlockBody(rendererJs, idx);
      expect(
        body,
        contains('!isTyping && !isError && !animate'),
        reason: 'Fast path condition must check not-typing, not-error, not-animate',
      );
      expect(
        body,
        contains('.glaze-message'),
        reason: 'Fast path must patch existing .glaze-message element',
      );
    });
  });

  // ─── _createGenStat dedup (Phase 4.3) ──────────────────────────────────────
  group('_createGenStat dedup (renderer.js)', () {
    test('_createGenStat method exists', () {
      expect(rendererJs, contains('_createGenStat('));
    });

    test('_createGenStat creates gen-stat div', () {
      final idx = rendererJs.indexOf('_createGenStat(');
      final body = _extractBlockBody(rendererJs, idx);
      expect(body, contains("'gen-stat'"));
    });

    test('_createBubbleMeta uses _createGenStat', () {
      final idx = rendererJs.indexOf('_createBubbleMeta(m)');
      final body = _extractBlockBody(rendererJs, idx);
      expect(
        body,
        contains('_createGenStat'),
        reason: '_createBubbleMeta must delegate to _createGenStat instead of inline DOM construction',
      );
    });

    test('_createFooter uses _createGenStat', () {
      final idx = rendererJs.indexOf('_createFooter(m)');
      final body = _extractBlockBody(rendererJs, idx);
      expect(
        body,
        contains('_createGenStat'),
        reason: '_createFooter must delegate to _createGenStat instead of inline DOM construction',
      );
    });
  });
}

// ─── helpers ──────────────────────────────────────────────────────────────────

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
    if (src[i] == '{') {
      depth++;
    } else if (src[i] == '}') {
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

/// Extracts the body of a JS method/class block starting from [fromIndex].
/// Walks braces to find the matching close.
String _extractBlockBody(String src, int fromIndex) {
  int start = src.indexOf('{', fromIndex);
  if (start == -1) return '';
  int depth = 0;
  for (int i = start; i < src.length; i++) {
    if (src[i] == '{') {
      depth++;
    } else if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return src.substring(start);
}
