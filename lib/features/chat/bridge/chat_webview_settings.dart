import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Android reserved domain for [WebViewAssetLoader] (flutter_inappwebview default).
const String kChatWebViewAndroidAssetDomain = 'appassets.androidplatform.net';

/// HTTPS entry for the chat WebView on Android. ES module imports require a
/// proper origin; `initialFile` / `file://` leaves modules on an opaque origin.
const String kChatWebViewAndroidAssetUrl =
    'https://$kChatWebViewAndroidAssetDomain/assets/flutter_assets/assets/chat_webview/index.html';

/// HTTPS path for local user files that the Android chat WebView may render
/// inside HTML, such as avatars, backgrounds, and generated images.
const String kChatWebViewAndroidFilePath = '/glaze-files/';

String? _chatWebViewAndroidFileRoot;

String? get chatWebViewAndroidFileRoot => _chatWebViewAndroidFileRoot;

void setChatWebViewAndroidFileRoot(String root) {
  _chatWebViewAndroidFileRoot = root;
}

/// Value for [InAppWebViewSettings.transparentBackground].
///
/// On Windows, `flutter_inappwebview_windows` 0.6.x inverts this flag in native
/// code (true leaves an opaque white WebView2 surface). Pass `false` there so
/// WebView2 gets a transparent default background and the Flutter stack behind
/// the chat WebView is visible. See flutter_inappwebview issue #2735.
bool chatWebViewTransparentBackground() {
  if (defaultTargetPlatform == TargetPlatform.windows) return false;
  return true;
}

/// Value for [InAppWebViewSettings.allowFileAccessFromFileURLs].
///
/// Windows/WebView2 loads Flutter assets through `file://` URLs, and ES module
/// imports need access to sibling module files in `assets/chat_webview/`.
/// Android uses [WebViewAssetLoader] instead. Universal file URL access stays
/// disabled on every platform.
bool chatWebViewAllowFileAccessFromFileUrls() {
  if (defaultTargetPlatform == TargetPlatform.windows) return true;
  return false;
}

/// Whether the chat WebView should load bundled assets through Android's
/// [WebViewAssetLoader] (HTTPS app-assets origin) instead of `initialFile`.
bool chatWebViewUsesAndroidAssetLoader() {
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

/// HTTPS URL for the chat WebView entry page on Android, or `null` elsewhere.
String? chatWebViewAndroidAssetUrl() {
  if (!chatWebViewUsesAndroidAssetLoader()) return null;
  return kChatWebViewAndroidAssetUrl;
}

/// Android [WebViewAssetLoader] for bundled chat assets, or `null` elsewhere.
WebViewAssetLoader? chatWebViewAssetLoader() {
  if (!chatWebViewUsesAndroidAssetLoader()) return null;
  final fileRoot = _chatWebViewAndroidFileRoot;
  return WebViewAssetLoader(
    pathHandlers: [
      AssetsPathHandler(path: '/assets/'),
      if (fileRoot != null)
        InternalStoragePathHandler(
          path: kChatWebViewAndroidFilePath,
          directory: fileRoot,
        ),
    ],
  );
}

/// Shared [InAppWebViewSettings] for the chat WebView and its preloader.
InAppWebViewSettings chatWebViewInAppSettings({bool isInspectable = true}) {
  return InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    transparentBackground: chatWebViewTransparentBackground(),
    isInspectable: isInspectable,
    useHybridComposition: true,
    cacheEnabled: true,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    allowFileAccess: true,
    allowContentAccess: true,
    allowFileAccessFromFileURLs: chatWebViewAllowFileAccessFromFileUrls(),
    allowUniversalAccessFromFileURLs: false,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    webViewAssetLoader: chatWebViewAssetLoader(),
  );
}
