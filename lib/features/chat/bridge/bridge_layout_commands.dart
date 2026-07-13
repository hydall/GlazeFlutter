import 'dart:convert';

import 'chat_bridge_controller.dart';
import 'chat_overlay_blur_region.dart';

/// Outgoing layout/UX commands: padding, search, edit, selection,
/// message settings. These are WebView-level controls that don't
/// affect message content directly.
class LayoutBridgeCommands {
  final ChatBridgeController _host;

  LayoutBridgeCommands(this._host);

  Future<void> setSearch({required String query, int activeIndex = -1}) {
    return _host.evalJs(
      'window.bridge?.setSearch("${_host.escape(query)}", $activeIndex)',
    );
  }

  Future<void> setBottomPadding(double px, {bool animate = false}) {
    return _host.evalJs(
      'window.bridge?.setBottomPadding(${px.toStringAsFixed(1)}, $animate)',
    );
  }

  Future<void> setTopPadding(double px) {
    return _host.evalJs(
      'window.bridge?.setTopPadding(${px.toStringAsFixed(1)})',
    );
  }

  /// Pushes the in-WebView header content (avatar + character name + session
  /// name) and the top safe-area inset. The avatar is resolved to a servable
  /// URL via the same [ChatBridgeController.setAvatarUrl] path the message
  /// avatars use, so a `file://` path becomes a scheme the WebView can load.
  Future<void> setHeader({
    String? charName,
    String? sessionName,
    String? charColor,
    String? charAvatarPath,
    double safeTop = 0,
  }) {
    _host.setAvatarUrl(charAvatarPath, isChar: true);
    final payload = jsonEncode({
      'charName': charName,
      'sessionName': sessionName,
      'charColor': charColor,
      'charAvatarUrl': _host.charAvatarUrl,
      'safeTop': safeTop,
    });
    return _host.evalJs('window.bridge?.setHeader($payload)');
  }

  /// Hides the in-WebView header while the native search bar is shown (the
  /// search text field stays native to keep the platform soft keyboard).
  Future<void> setSearchMode(bool on) {
    return _host.evalJs('window.bridge?.setSearchMode($on)');
  }

  /// Syncs the rects of Flutter glass overlays (header, input pill, ...) so
  /// the WebView can blur the messages scrolling underneath them — Flutter's
  /// own BackdropFilter cannot sample the platform view's pixels.
  Future<void> setOverlayBlurRegions(List<ChatOverlayBlurRegion> regions) {
    final json = chatOverlayBlurRegionsToJs(regions);
    return _host.evalJs('window.bridge?.setOverlayBlurRegions($json)');
  }

  Future<void> startEdit(String messageId) {
    return _host.evalJs(
      'window.bridge?.startEdit("${_host.escape(messageId)}")',
    );
  }

  Future<void> stopEdit(String messageId) {
    return _host.evalJs(
      'window.bridge?.stopEdit("${_host.escape(messageId)}")',
    );
  }

  Future<void> setMessageSettings({
    required bool batterySaver,
    required bool hideMessageId,
    required bool hideGenerationTime,
    required bool hideTokenCount,
    required bool disableSwipeRegeneration,
  }) {
    final json = jsonEncode({
      'batterySaver': batterySaver,
      'hideMessageId': hideMessageId,
      'hideGenerationTime': hideGenerationTime,
      'hideTokenCount': hideTokenCount,
      'disableSwipeRegeneration': disableSwipeRegeneration,
    });
    return _host.callJs('setMessageSettings', json);
  }

  Future<void> setSelectionMode(bool enabled) {
    return _host.evalJs('window.bridge?.setSelectionMode($enabled)');
  }

  Future<void> toggleMessageSelection(String id) {
    return _host.evalJs(
      'window.bridge?.renderer?.toggleMessageSelection("${_host.escape(id)}")',
    );
  }
}
