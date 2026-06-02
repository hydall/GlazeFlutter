import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _asset(String name) =>
    File('assets/chat_webview/$name').readAsStringSync();

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

void main() {
  late String bridgeJs;

  setUpAll(() {
    bridgeJs = _asset('bridge.js');
  });

  // ─── Phase 3.2: SelectionManager ────────────────────────────────────────
  group('Selection behavior (Phase 3.2 characterization)', () {
    test('setSelectionMode exists on Bridge', () {
      expect(bridgeJs, contains('setSelectionMode(enabled)'));
    });

    test('setSelectionMode delegates to SelectionManager', () {
      expect(bridgeJs, contains('_selectionManager.setSelectionMode(enabled)'));
    });

    test('SelectionManager class exists in bridge.js', () {
      expect(bridgeJs, contains('class SelectionManager'));
    });

    test('SelectionManager has setSelectionMode method', () {
      expect(bridgeJs, contains('setSelectionMode(enabled)'));
    });

    test('SelectionManager has toggleMessageSelection method', () {
      expect(bridgeJs, contains('toggleMessageSelection(messageId)'));
    });

    test('SelectionManager has getSelectedIds method', () {
      expect(bridgeJs, contains('getSelectedIds()'));
    });

    test('SelectionManager tracks _selectedIds as Set', () {
      expect(bridgeJs, contains('_selectedIds'));
    });

    test('contextmenu listener delegates to SelectionManager', () {
      final marker = "addEventListener('contextmenu'";
      expect(bridgeJs, contains(marker));
      final idx = bridgeJs.indexOf(marker);
      expect(idx, isNot(-1));
      final context = bridgeJs.substring(idx, idx + 2000);
      expect(context, contains('_selectionManager.handleContextMenu'));
    });

    test('selectionchange listener delegates to SelectionManager', () {
      expect(bridgeJs, contains('selectionchange'));
      expect(bridgeJs, contains('_selectionManager.handleSelectionChange'));
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

    test('click in selection mode delegated to SelectionManager.handleClick', () {
      final idx = bridgeJs.indexOf('class InteractionDispatch');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('_selectionManager.handleClick'));
    });

    test('SelectionManager exits selection mode when no messages remain selected', () {
      expect(bridgeJs, contains('exitIfEmpty'));
    });

    test('selection-mode CSS class is toggled by SelectionManager', () {
      final idx = bridgeJs.indexOf('class SelectionManager');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains("'selection-mode'"));
    });
  });

  // ─── Phase 3.3: EditController ──────────────────────────────────────────
  group('Edit behavior (Phase 3.3 characterization)', () {
    test('Bridge has startEdit method that delegates to EditController', () {
      expect(bridgeJs, contains('startEdit(messageId)'));
      expect(bridgeJs, contains('_editController.startEdit'));
    });

    test('Bridge has stopEdit method that delegates to EditController', () {
      expect(bridgeJs, contains('stopEdit(messageId)'));
      expect(bridgeJs, contains('_editController.stopEdit'));
    });

    test('EditController class exists in bridge.js', () {
      expect(bridgeJs, contains('class EditController'));
    });

    test('EditController startEdit creates edit-textarea', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final startIdx = classBody.indexOf('startEdit(messageId');
      expect(startIdx, isNot(-1));
      final body = _extractBlockBody(classBody, startIdx);
      expect(body, contains('edit-textarea'));
    });

    test('EditController startEdit saves originalHtml in dataset', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final startIdx = classBody.indexOf('startEdit(messageId');
      final body = _extractBlockBody(classBody, startIdx);
      expect(body, contains('dataset.originalHtml'));
    });

    test('EditController startEdit adds editing class to section', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final startIdx = classBody.indexOf('startEdit(messageId');
      final body = _extractBlockBody(classBody, startIdx);
      expect(body, contains("'editing'"));
    });

    test('EditController startEdit creates Cancel and Save buttons in footer', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final startIdx = classBody.indexOf('startEdit(messageId');
      final body = _extractBlockBody(classBody, startIdx);
      expect(body, contains('edit-cancel'));
      expect(body, contains('edit-save'));
    });

    test('EditController stopEdit restores originalHtml from dataset', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final stopIdx = classBody.indexOf('stopEdit(messageId');
      final body = _extractBlockBody(classBody, stopIdx);
      expect(body, contains('dataset.originalHtml'));
    });

    test('EditController stopEdit removes editing class', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final stopIdx = classBody.indexOf('stopEdit(messageId');
      final body = _extractBlockBody(classBody, stopIdx);
      expect(body, contains("'editing'"));
    });

    test('edit-save action delegates to EditController.handleSave', () {
      final idx = bridgeJs.indexOf("'edit-save':");
      expect(idx, isNot(-1));
      final block = bridgeJs.substring(idx, idx + 300);
      expect(block, contains('_editController.handleSave'));
    });

    test('EditController handleSave sends onEditSave with textarea value', () {
      expect(bridgeJs, contains('handleSave(el)'));
      final idx = bridgeJs.indexOf('handleSave(el)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('onEditSave'));
      expect(body, contains('edit-textarea'));
    });

    test('edit-cancel action delegates to EditController.handleCancel', () {
      final idx = bridgeJs.indexOf("'edit-cancel':");
      expect(idx, isNot(-1));
      final block = bridgeJs.substring(idx, idx + 200);
      expect(block, contains('_editController.handleCancel'));
    });

    test('EditController handleCancel sends onEditCancel', () {
      expect(bridgeJs, contains('handleCancel(el)'));
      final idx = bridgeJs.indexOf('handleCancel(el)');
      final body = _extractBlockBody(bridgeJs, idx);
      expect(body, contains('onEditCancel'));
    });

    test('textarea has auto-resize input listener', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains("addEventListener('input'"));
    });

    test('textarea has wheel listener with scroll speed multiplier', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains("addEventListener('wheel'"));
      expect(classBody, contains('0.3'));
    });

    test('startEdit handles think blocks — separates reasoning from content', () {
      final idx = bridgeJs.indexOf('class EditController');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final hasThink = classBody.contains('</think') || classBody.contains('<think');
      expect(hasThink, isTrue);
    });
  });

  // ─── Phase 3.4: SwipeGestureHandler ─────────────────────────────────────
  group('Swipe gesture behavior (Phase 3.4 characterization)', () {
    test('SwipeGestureHandler class exists in bridge.js', () {
      expect(bridgeJs, contains('class SwipeGestureHandler'));
    });

    test('Bridge creates SwipeGestureHandler and calls setup', () {
      expect(bridgeJs, contains('_swipeHandler = new SwipeGestureHandler'));
      expect(bridgeJs, contains('_swipeHandler.setup()'));
    });

    test('swipe setup registers touchstart, touchmove, touchend, touchcancel', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('touchstart'));
      expect(classBody, contains('touchmove'));
      expect(classBody, contains('touchend'));
      expect(classBody, contains('touchcancel'));
    });

    test('swipe uses a horizontal threshold', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('THRESHOLD'));
    });

    test('swipe cancels when vertical scroll is detected', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('scrollingVertical'));
    });

    test('swipe applies translateX transform during drag', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('translateX'));
    });

    test('left swipe on last message triggers regeneration', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('onRegenerate'));
    });

    test('swipe past threshold triggers onSwipe', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('onSwipe'));
    });

    test('greeting swipe triggers onChangeGreeting', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('onChangeGreeting'));
    });

    test('swipe reads swipe context', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final hasSwipeContext = classBody.contains('swipeId') || classBody.contains('data-swipe-id');
      expect(hasSwipeContext, isTrue);
    });

    test('swipe is disabled while generating', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final hasGenerating = classBody.contains('isGenerating') || classBody.contains('generating');
      expect(hasGenerating, isTrue);
    });

    test('swipe is disabled during editing', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('editing'));
    });

    test('swipe blocks horizontal translation at boundaries', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      final hasDx = classBody.contains('dx') || classBody.contains('translateX');
      expect(hasDx, isTrue);
    });

    test('reset animation uses CSS transition', () {
      final idx = bridgeJs.indexOf('class SwipeGestureHandler');
      final classBody = _extractBlockBody(bridgeJs, idx);
      expect(classBody, contains('transition'));
    });

    test('guided swipe toggles inline panel with textarea and sends onGuidedSwipe', () {
      expect(bridgeJs, contains('toggleGuidedSwipe'));
      expect(bridgeJs, contains('guided-swipe-textarea'));
      expect(bridgeJs, contains("'onGuidedSwipe'"));
    });

    test('toggle-guided action delegates to SwipeGestureHandler', () {
      final idx = bridgeJs.indexOf("'toggle-guided':");
      expect(idx, isNot(-1));
      final block = bridgeJs.substring(idx, idx + 200);
      expect(block, contains('_swipeHandler.toggleGuidedSwipe'));
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

    test('edit callbacks delegate to EditController', () {
      final saveIdx = bridgeJs.indexOf("'edit-save':");
      expect(saveIdx, isNot(-1));
      final saveBlock = bridgeJs.substring(saveIdx, saveIdx + 300);
      expect(saveBlock, contains('_editController.handleSave'));

      final cancelIdx = bridgeJs.indexOf("'edit-cancel':");
      expect(cancelIdx, isNot(-1));
      final cancelBlock = bridgeJs.substring(cancelIdx, cancelIdx + 200);
      expect(cancelBlock, contains('_editController.handleCancel'));

      expect(bridgeJs, contains('onEditSave'));
      expect(bridgeJs, contains('onEditCancel'));
    });
  });

  // ─── Phase 4.2: MessageUpdateBatcher ──────────────────────────────────────
  group('MessageUpdateBatcher (Phase 4.2 characterization)', () {
    test('MessageUpdateBatcher class exists', () {
      expect(bridgeJs, contains('class MessageUpdateBatcher'));
    });

    test('has enqueue method', () {
      expect(bridgeJs, contains('enqueue(id, updateFn)'));
    });

    test('has flush method', () {
      final idx = bridgeJs.indexOf('class MessageUpdateBatcher');
      final classBody = bridgeJs.substring(idx, idx + 500);
      expect(classBody, contains('flush()'));
    });

    test('has hasPending method', () {
      final idx = bridgeJs.indexOf('class MessageUpdateBatcher');
      final classBody = bridgeJs.substring(idx, idx + 700);
      expect(classBody, contains('hasPending()'));
    });

    test('uses requestAnimationFrame for batching', () {
      final idx = bridgeJs.indexOf('class MessageUpdateBatcher');
      final classBody = bridgeJs.substring(idx, idx + 500);
      expect(classBody, contains('requestAnimationFrame'));
    });

    test('Bridge creates _updateBatcher', () {
      expect(bridgeJs, contains('new MessageUpdateBatcher()'));
    });

    test('updateMessage delegates to _updateBatcher.enqueue', () {
      final idx = bridgeJs.indexOf('updateMessage(messageJson)');
      final methodBody = bridgeJs.substring(idx, idx + 200);
      expect(methodBody, contains('_updateBatcher.enqueue'));
    });

    test('_executeUpdateMessage contains update logic', () {
      expect(bridgeJs, contains('_executeUpdateMessage(msg)'));
      final idx = bridgeJs.indexOf('_executeUpdateMessage(msg) {');
      final methodBody = bridgeJs.substring(idx, idx + 800);
      expect(methodBody, contains('updateMessageContent'));
    });

    test('flush() called before setMessages', () {
      final idx = bridgeJs.indexOf('setMessages(messagesJson)');
      final methodBody = bridgeJs.substring(idx, idx + 100);
      expect(methodBody, contains('this.flush()'));
    });

    test('flush() called before appendMessage', () {
      final idx = bridgeJs.indexOf('appendMessage(messageJson)');
      final methodBody = bridgeJs.substring(idx, idx + 100);
      expect(methodBody, contains('this.flush()'));
    });

    test('flush() called before appendMessages', () {
      final idx = bridgeJs.indexOf('appendMessages(messagesJson)');
      final methodBody = bridgeJs.substring(idx, idx + 100);
      expect(methodBody, contains('this.flush()'));
    });

    test('flush() called before prependMessages', () {
      final idx = bridgeJs.indexOf('prependMessages(messagesJson)');
      final methodBody = bridgeJs.substring(idx, idx + 100);
      expect(methodBody, contains('this.flush()'));
    });

    test('flush() called before removeMessage', () {
      final idx = bridgeJs.indexOf('removeMessage(messageId)');
      final methodBody = bridgeJs.substring(idx, idx + 100);
      expect(methodBody, contains('this.flush()'));
    });

    test('flush() called before clearAll', () {
      final idx = bridgeJs.indexOf('clearAll()');
      final methodBody = bridgeJs.substring(idx, idx + 100);
      expect(methodBody, contains('this.flush()'));
    });

    test('bridge has public flush method', () {
      expect(bridgeJs, contains('flush() { this._updateBatcher.flush(); }'));
    });
  });
}
