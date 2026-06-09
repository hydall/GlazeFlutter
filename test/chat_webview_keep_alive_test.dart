import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/features/chat/bridge/chat_webview_environment.dart';
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

  group('chat WebView Android asset loader', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('loads bundled chat assets over HTTPS on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(chatWebViewUsesAndroidAssetLoader(), isTrue);
      expect(
        chatWebViewAndroidAssetUrl(),
        contains(kChatWebViewAndroidAssetDomain),
      );
      expect(chatWebViewInitialFile(), isNull);
      expect(
        chatWebViewInitialUrlRequest()?.url.toString(),
        kChatWebViewAndroidAssetUrl,
      );
    });

    test('maps local Glaze files to the Android asset loader origin', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      setChatWebViewAndroidFileRoot('/data/user/0/com.hydall.glaze/Glaze');

      expect(
        chatWebViewResolveLocalFileUrl(
          '/data/user/0/com.hydall.glaze/Glaze/avatars/char 1.png',
        ),
        'https://$kChatWebViewAndroidAssetDomain/glaze-files/avatars/char%201.png',
      );
      expect(
        chatWebViewResolveLocalFileUrl('/data/user/0/com.other/app/avatar.png'),
        '/data/user/0/com.other/app/avatar.png',
      );
    });

    test('does not use Android asset loader on Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(chatWebViewUsesAndroidAssetLoader(), isFalse);
      expect(chatWebViewAndroidAssetUrl(), isNull);
      expect(chatWebViewInitialFile(), 'assets/chat_webview/index.html');
      expect(chatWebViewInitialUrlRequest(), isNull);
    });
  });
}
