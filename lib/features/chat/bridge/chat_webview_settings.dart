import 'package:flutter/foundation.dart';

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
