import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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
      setChatWebViewLocalFileBaseUrlForTesting(null);
      setChatWebViewAndroidFileRoot('');
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

    test('allows loopback image URLs via mixed content compatibility mode', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(
        chatWebViewMixedContentMode(),
        MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      );
    });

    test('maps Android Glaze files to loopback HTTP URLs', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      setChatWebViewAndroidFileRoot('/data/user/0/com.hydall.glaze/Glaze');
      setChatWebViewLocalFileBaseUrlForTesting(
        WebUri('http://127.0.0.1:42424/'),
      );

      final resolved = chatWebViewResolveLocalFileUrl(
        '/data/user/0/com.hydall.glaze/Glaze/avatars/char.png',
      );
      expect(resolved, startsWith('http://127.0.0.1:42424/__glaze_file__?path='));
      expect(resolved, contains('avatars'));
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
      expect(
        chatWebViewMixedContentMode(),
        MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      );
    });
  });
}
