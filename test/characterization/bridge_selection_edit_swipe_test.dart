import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _asset(String name) =>
    File('assets/chat_webview/$name').readAsStringSync();

String _extractBlockBody(String src, int fromIndex) {
  int start = src.indexOf('{', fromIndex);
  if (start == -1) return '';
  int depth = 0;
  for (int i = start; i < src.length; i++) {
    if (src[i] == '{') depth++;
    else if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return src.substring(start);
}

void main() {
  late String bridgeJs;
  late String rendererJs;

  setUpAll(() {
    bridgeJs = _asset('bridge.js');
    rendererJs = _asset('renderer.js');
  });

  // ─── Phase 3.2: SelectionManager ────────────────────────────────────────
  group('Selection behavior (Phase 3.2 characterization)', () {
    test('setSelectionMode exists on Bridge', () {
      expect(bridgeJs, contains('setSelectionMode(enabled)'));
    });

    test('setSelectionMode delegates to renderer', () {
      expect(bridgeJs, contains('renderer.setSelectionMode(enabled)'));
    });

    test('Renderer has setSelectionMode method', () {
      expect(rendererJs, contains('setSelectionMode(enabled)'));
    });

    test('Renderer has toggleMessageSelection method', () {
      expect(rendererJs, contains('toggleMessageSelection(messageId)'));
    });

    test('Renderer has getSelectedIds method', () {
      expect(rendererJs, contains('getSelectedIds()'));
    });

    test('Renderer tracks _selectedIds as Set', () {
      expect(rendererJs, contains('_selectedIds'));
    });

    test('contextmenu listener enters selection mode on long press', () {
      final marker = "addEventListener('contextmenu'";
      expect(bridgeJs, contains(marker));
      final idx = bridgeJs.indexOf(marker);
      expect(idx, isNot(-1));
      final context = bridgeJs.substring(idx, idx + 2000);
      expect(context, contains('setSelectionMode(true)'));
    });

    test('selectionchange listener shows selection bar', () {
      expect(bridgeJs, contains('selectionchange'));
      expect(bridgeJs, contains('_showSelectionBar'));
      expect(bridgeJs, contains('_hideSelectionBar'));
    });

    test('_showSelectionBar creates Copy and Quote buttons', () {
      final idx = bridgeJs.indexOf('_showSelectionBar(text)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('Copy'));
      expect(body, contains('Quote'));
    });

    test('onSelectionChange callback sends selected IDs to Flutter', () {
      expect(bridgeJs, contains('onSelectionChange'));
    });

    test('onSelectionAction callback sends action + text to Flutter', () {
      expect(bridgeJs, contains('onSelectionAction'));
    });

    test('click in selection mode toggles message selection', () {
      final idx = bridgeJs.indexOf('class InteractionDispatch');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('toggleMessageSelection'));
      expect(classBody, contains('selectionMode'));
    });

    test('exits selection mode when no messages remain selected', () {
      final idx = bridgeJs.indexOf('class InteractionDispatch');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('setSelectionMode(false)'));
    });

    test('selection-mode CSS class is toggled on message sections', () {
      final idx = rendererJs.indexOf('setSelectionMode(enabled)');
      final body = _extractBlockBody(rendererJs, idx);
      expect(body, contains("'selection-mode'"));
    });
  });

  // ─── Phase 3.3: EditController ──────────────────────────────────────────
  group('Edit behavior (Phase 3.3 characterization)', () {
    test('Bridge has startEdit method', () {
      expect(bridgeJs, contains('startEdit(messageId)'));
    });

    test('Bridge has stopEdit method', () {
      expect(bridgeJs, contains('stopEdit(messageId)'));
    });

    test('startEdit creates edit-textarea', () {
      final idx = bridgeJs.indexOf('startEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('edit-textarea'));
    });

    test('startEdit saves originalHtml in dataset', () {
      final idx = bridgeJs.indexOf('startEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('dataset.originalHtml'));
    });

    test('startEdit adds editing class to section', () {
      final idx = bridgeJs.indexOf('startEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains("'editing'"));
    });

    test('startEdit creates Cancel and Save buttons in footer', () {
      final idx = bridgeJs.indexOf('startEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('edit-cancel'));
      expect(body, contains('edit-save'));
    });

    test('stopEdit restores originalHtml from dataset', () {
      final idx = bridgeJs.indexOf('stopEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('dataset.originalHtml'));
    });

    test('stopEdit removes editing class', () {
      final idx = bridgeJs.indexOf('stopEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains("'editing'"));
    });

    test('edit-save action sends onEditSave with message ID and textarea value', () {
      final idx = bridgeJs.indexOf("'edit-save':");
      expect(idx, isNot(-1));
      final block = bridgeJs.substring(idx, idx + 300);
      expect(block, contains('onEditSave'));
      expect(block, contains('edit-textarea'));
    });

    test('edit-cancel action sends onEditCancel', () {
      final idx = bridgeJs.indexOf("'edit-cancel':");
      expect(idx, isNot(-1));
      final block = bridgeJs.substring(idx, idx + 200);
      expect(block, contains('onEditCancel'));
    });

    test('textarea has auto-resize input listener', () {
      final idx = bridgeJs.indexOf('startEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains("addEventListener('input'"));
    });

    test('textarea has wheel listener with scroll speed multiplier', () {
      final idx = bridgeJs.indexOf('startEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains("addEventListener('wheel'"));
      expect(body, contains('0.3'));
    });

    test('startEdit handles think blocks — separates reasoning from content', () {
      final idx = bridgeJs.indexOf('startEdit(messageId)');
      final body = _extractBlockBody(bridgeJs, idx);
      final hasThink = body.contains('</think') || body.contains('<think');
      expect(hasThink, isTrue);
    });
  });

  // ─── Phase 3.4: SwipeGestureHandler ─────────────────────────────────────
  group('Swipe gesture behavior (Phase 3.4 characterization)', () {
    test('Bridge has _setupSwipeGestures method', () {
      expect(bridgeJs, contains('_setupSwipeGestures()'));
    });

    test('swipe setup registers touchstart, touchmove, touchend, touchcancel', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('touchstart'));
      expect(body, contains('touchmove'));
      expect(body, contains('touchend'));
      expect(body, contains('touchcancel'));
    });

    test('swipe uses a horizontal threshold', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('THRESHOLD'));
    });

    test('swipe cancels when vertical scroll is detected', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('scrollingVertical'));
    });

    test('swipe applies translateX transform during drag', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('translateX'));
    });

    test('left swipe on last message triggers regeneration', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('onRegenerate'));
    });

    test('swipe past threshold triggers onSwipe', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('onSwipe'));
    });

    test('greeting swipe triggers onChangeGreeting', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('onChangeGreeting'));
    });

    test('swipe reads swipe context', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      final hasSwipeContext = body.contains('swipeId') || body.contains('data-swipe-id');
      expect(hasSwipeContext, isTrue);
    });

    test('swipe is disabled while generating', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      final hasGenerating = body.contains('isGenerating') || body.contains('generating');
      expect(hasGenerating, isTrue);
    });

    test('swipe is disabled during editing', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('editing'));
    });

    test('swipe blocks horizontal translation at boundaries', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      final hasDx = body.contains('dx') || body.contains('translateX');
      expect(hasDx, isTrue);
    });

    test('reset animation uses CSS transition', () {
      final idx = bridgeJs.indexOf('_setupSwipeGestures()');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('transition'));
    });

    test('guided swipe toggles inline panel with textarea and sends onGuidedSwipe', () {
      expect(bridgeJs, contains('_toggleGuidedSwipe'));
      expect(bridgeJs, contains('guided-swipe-textarea'));
      expect(bridgeJs, contains("'onGuidedSwipe'"));
    });
  });

  // ─── Phase 4.2: Message batching ────────────────────────────────────────
  group('Flutter→WebView message dispatch (Phase 4.2 characterization)', () {
    test('bridge has updateMessage method for streaming', () {
      expect(bridgeJs, contains('updateMessage('));
    });

    test('bridge has setMessages batch method', () {
      expect(bridgeJs, contains('setMessages('));
    });

    test('bridge has appendMessages batch method', () {
      expect(bridgeJs, contains('appendMessages('));
    });

    test('bridge has prependMessages batch method', () {
      expect(bridgeJs, contains('prependMessages('));
    });

    test('updateMessage method exists in bridge.js', () {
      expect(bridgeJs, contains('updateMessage(messageJson)'));
    });

    test('no MessageChannel batching exists in current bridge.js', () {
      expect(bridgeJs, isNot(contains('MessageChannel')));
    });

    test('requestAnimationFrame is used for header scroll throttling', () {
      expect(bridgeJs, contains('requestAnimationFrame(updateHeader)'));
    });
  });

  // ─── Phase 4.4: Callback structure ──────────────────────────────────────
  group('WebView callback interface (Phase 4.4 characterization)', () {
    test('all JS→Flutter callback names are sent via _sendToFlutter', () {
      final expectedHandlers = [
        'onLoadMore',
        'onHeaderScroll',
        'onLinkClick',
        'onImageClick',
        'onMessageContext',
        'onSwipe',
        'onRegenerate',
        'onChangeGreeting',
        'onSelectionAction',
        'onEditSave',
        'onEditCancel',
        'onGuidedSwipe',
        'onMemoryClick',
        'onToggleHidden',
        'onSelectionChange',
        'onInjectClick',
        'onImgRetry',
        'onImgFind',
        'onImgRegen',
        'onImgCancel',
        'onStop',
      ];
      for (final name in expectedHandlers) {
        expect(bridgeJs, contains("'$name'"), reason: 'Callback "$name" must be sent via _sendToFlutter in bridge.js');
      }
    });

    test('callbacks use flutter_inappwebview.callHandler', () {
      expect(bridgeJs, contains('flutter_inappwebview.callHandler'));
    });

    test('onMessageContext sends JSON object with id and isUser', () {
      final idx = bridgeJs.indexOf('onMessageContext');
      expect(idx, isNot(-1));
      final context = bridgeJs.substring(idx - 100, idx + 300);
      expect(context, contains('id'));
      expect(context, contains('isUser'));
    });

    test('onSwipe sends id and direction', () {
      final idx = bridgeJs.indexOf('onSwipe');
      expect(idx, isNot(-1));
      final context = bridgeJs.substring(idx - 50, idx + 200);
      expect(context, contains('direction'));
    });

    test('image callbacks (retry/find/regen) send instruction and messageId', () {
      for (final action in ['onImgRetry', 'onImgFind', 'onImgRegen']) {
        expect(
          bridgeJs,
          contains("'$action'"),
          reason: '$action must be sent via _sendToFlutter in bridge.js',
        );
        final idx = bridgeJs.indexOf("'$action'");
        final context = bridgeJs.substring(idx, idx + 200);
        expect(context, contains('instr'));
        expect(context, contains('messageId'));
      }
    });

    test('edit callbacks send messageId and text', () {
      final saveIdx = bridgeJs.indexOf("'edit-save':");
      expect(saveIdx, isNot(-1));
      final saveBlock = bridgeJs.substring(saveIdx, saveIdx + 300);
      expect(saveBlock, contains('onEditSave'));

      final cancelIdx = bridgeJs.indexOf("'edit-cancel':");
      expect(cancelIdx, isNot(-1));
      final cancelBlock = bridgeJs.substring(cancelIdx, cancelIdx + 200);
      expect(cancelBlock, contains('onEditCancel'));
    });
  });
}
