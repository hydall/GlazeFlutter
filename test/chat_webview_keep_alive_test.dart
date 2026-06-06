import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/features/chat/bridge/chat_webview_keep_alive.dart';
import 'package:glaze_flutter/features/chat/bridge/chat_webview_settings.dart';

void main() {
  group('chat WebView keepAlive policy', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('does not attach preload keepAlive on Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(chatWebViewKeepAliveForPlatform(), isNull);
    });

    test('reuses app-start preload keepAlive on mobile', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(chatWebViewKeepAliveForPlatform(), same(chatWebViewKeepAlive));
    });
  });

  group('chat WebView file access policy', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('allows bundled asset module imports on Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(chatWebViewAllowFileAccessFromFileUrls(), isTrue);
    });

    test('keeps file URL reads disabled on mobile', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(chatWebViewAllowFileAccessFromFileUrls(), isFalse);
    });
  });
}
