import 'dart:convert';

import 'chat_bridge_controller.dart';

/// Outgoing layout/UX commands: padding, search, edit, selection,
/// message settings. These are WebView-level controls that don't
/// affect message content directly.
class LayoutBridgeCommands {
  final ChatBridgeController _host;

  LayoutBridgeCommands(this._host);

  Future<void> setSearch({
    required String query,
    int activeIndex = -1,
  }) {
    return _host.evalJs(
      'window.bridge?.setSearch("${_host.escape(query)}", $activeIndex)',
    );
  }

  Future<void> setBottomPadding(double px) {
    return _host.evalJs(
      'window.bridge?.setBottomPadding(${px.toStringAsFixed(1)})',
    );
  }

  Future<void> setTopPadding(double px) {
    return _host.evalJs(
      'window.bridge?.setTopPadding(${px.toStringAsFixed(1)})',
    );
  }

  Future<void> setHeaderOverlay(double topPx, double heightPx) {
    return _host.evalJs(
      'window.bridge?.setHeaderOverlay(${topPx.toStringAsFixed(1)}, ${heightPx.toStringAsFixed(1)})',
    );
  }

  Future<void> setInputOverlay(double heightPx) {
    return _host.evalJs(
      'window.bridge?.setInputOverlay(${heightPx.toStringAsFixed(1)})',
    );
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
