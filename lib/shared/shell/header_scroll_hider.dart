import 'package:flutter/widgets.dart';

/// Drives hide-on-scroll for a floating header, ported from the chat header's
/// algorithm (`initHeaderScroll` in
/// `assets/chat_webview/bridge/chat_bridge_controller.js`). Unlike
/// [UserScrollNotification.direction] — which flips the instant a drag starts
/// — this requires a few pixels of actual movement and ignores rubber-band
/// overscroll at the list's edges.
class HeaderScrollHider {
  double _lastPixels = 0;
  bool _hidden = false;

  bool get hidden => _hidden;

  /// Feed every [ScrollNotification] from the list here. Calls [onChanged]
  /// with the new hidden state when it flips. Ignores horizontal scrollables.
  void handle(ScrollNotification notification, ValueChanged<bool> onChanged) {
    if (notification.metrics.axis != Axis.vertical) return;
    if (notification is! ScrollUpdateNotification &&
        notification is! OverscrollNotification) {
      return;
    }

    final metrics = notification.metrics;
    final pixels = metrics.pixels;

    if (pixels < metrics.minScrollExtent || pixels > metrics.maxScrollExtent) {
      _lastPixels = pixels <= metrics.minScrollExtent
          ? metrics.minScrollExtent
          : pixels;
      return;
    }

    if (pixels > _lastPixels + 3 && pixels > 50) {
      if (!_hidden) {
        _hidden = true;
        onChanged(true);
      }
    } else if (pixels < _lastPixels - 3) {
      if (_hidden) {
        _hidden = false;
        onChanged(false);
      }
    }
    _lastPixels = pixels <= metrics.minScrollExtent
        ? metrics.minScrollExtent
        : pixels;
  }
}
