import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatWebViewWidget callback contract (Phase 4.4 characterization)', () {
    late String webviewWidgetSource;
    late String bridgeControllerSource;

    setUpAll(() {
      webviewWidgetSource = File(
        'lib/features/chat/widgets/chat_webview_widget.dart',
      ).readAsStringSync();
      bridgeControllerSource = File(
        'lib/features/chat/bridge/chat_bridge_controller.dart',
      ).readAsStringSync();
    });

    test('widget has 5 callback group parameters', () {
      final callbackGroups = [
        'MessageActionsCallbacks',
        'EditActionsCallbacks',
        'ImageGenCallbacks',
        'ScrollCallbacks',
        'MiscCallbacks',
      ];
      for (final name in callbackGroups) {
        expect(
          webviewWidgetSource,
          contains(name),
          reason: 'Widget must accept callback group "$name"',
        );
      }
    });

    test('all expected onXxx callbacks exist in callback classes', () {
      final callbacksSource = File(
        'lib/features/chat/widgets/webview_callbacks.dart',
      ).readAsStringSync();
      final expectedCallbacks = [
        'onMessageContext',
        'onSwipe',
        'onChangeGreeting',
        'onRegenerate',
        'onHeaderScroll',
        'onStop',
        'onSelectionAction',
        'onEditSave',
        'onEditCancel',
        'onImageClick',
        'onGuidedSwipe',
        'onMemoryClick',
        'onToggleHidden',
        'onInjectClick',
        'onImgRetry',
        'onImgFind',
        'onImgRegen',
        'onImgCancel',
        'onSelectionChange',
      ];
      for (final name in expectedCallbacks) {
        expect(
          callbacksSource,
          contains(name),
          reason: 'Callback classes must declare callback "$name"',
        );
      }
    });

    test('Bridge controller has 22 callback properties', () {
      final callbackProps = [
        'onReady',
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
      for (final name in callbackProps) {
        expect(
          bridgeControllerSource,
          contains(name),
          reason: 'Bridge controller must have callback property "$name"',
        );
      }
    });

    test('onMessageContext is adapted (adds index lookup)', () {
      expect(
        webviewWidgetSource,
        contains('indexWhere'),
        reason: 'onMessageContext adapter must look up message index',
      );
    });

    test('onLinkClick is handled internally (url_launcher)', () {
      expect(
        webviewWidgetSource,
        contains('launchUrl'),
        reason: 'onLinkClick must be handled internally with url_launcher',
      );
    });

    test('onLoadMore is handled internally (chatProvider)', () {
      expect(
        webviewWidgetSource,
        contains('loadOlderMessages'),
        reason: 'onLoadMore must be handled internally via chatProvider',
      );
    });

    test('bridge _setupHandlers registers addJavaScriptHandler for each callback', () {
      final expectedHandlers = [
        'onWebViewReady',
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
        expect(
          bridgeControllerSource,
          contains("handlerName: '$name'"),
          reason: '_setupHandlers must register "$name" handler',
        );
      }
    });

    test('image callbacks (retry/find/regen) have (String, String) signature', () {
      for (final name in ['onImgRetry', 'onImgFind', 'onImgRegen']) {
        expect(
          bridgeControllerSource,
          contains('void Function(String instruction, String messageId)? $name;'),
          reason: '$name must accept (String instruction, String messageId) parameters',
        );
      }
    });

    test('onImgCancel and onStop have no-arg signature', () {
      expect(
        bridgeControllerSource,
        contains('void Function()? onImgCancel;'),
        reason: 'onImgCancel must be a no-arg callback',
      );
      expect(
        bridgeControllerSource,
        contains('void Function()? onStop;'),
        reason: 'onStop must be a no-arg callback',
      );
    });

    test('non-callback data props (charId, messages, etc) exist', () {
      final expectedDataProps = [
        'charId',
        'messages',
        'isGenerating',
        'isGeneratingImage',
        'bottomInset',
        'topInset',
        'searchQuery',
        'chatLayout',
        'greetingTotal',
        'chatFontName',
        'chatFontSize',
        'memoryEntries',
        'sessionId',
        'visibleStartIndex',
        'regenTargetId',
        'isSelectionMode',
      ];
      for (final prop in expectedDataProps) {
        expect(
          webviewWidgetSource,
          contains(prop),
          reason: 'Widget must have data prop "$prop"',
        );
      }
    });
  });
}
