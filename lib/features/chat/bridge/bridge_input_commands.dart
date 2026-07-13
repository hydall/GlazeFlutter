import 'dart:convert';

import 'chat_bridge_controller.dart';

/// Outgoing commands for the in-WebView input bar (Phase 2). The compose field,
/// buttons, guidance mode and image attach now live inside the chat WebView;
/// Flutter pushes the reactive state (draft, generating, mode, localized
/// labels) here and the [InputController] on the JS side renders it.
///
/// All user-facing strings arrive pre-localized from Flutter — the WebView has
/// no i18n, mirroring how the header receives its already-localized session
/// name.
class InputBridgeCommands {
  final ChatBridgeController _host;

  InputBridgeCommands(this._host);

  Future<void> setInputState({
    double? safeBottom,
    String? draft,
    String? placeholder,
    String? guidancePlaceholder,
    bool? isGenerating,
    bool? isEditing,
    bool? isDrawerOpen,
    bool? isQuickRepliesOpen,
    bool? isSelectionMode,
    bool? showSearch,
    String? searchLabel,
    String? selectionLabel,
    int? selectedCount,
    bool? allSelectedHidden,
    bool? enterToSend,
    bool? virtualKeyboardSend,
  }) {
    // Only include keys that are provided so the JS side's `'x' in opts` guards
    // leave untouched fields alone.
    final payload = <String, dynamic>{};
    void put(String k, dynamic v) {
      if (v != null) payload[k] = v;
    }

    put('safeBottom', safeBottom);
    put('draft', draft);
    put('placeholder', placeholder);
    put('guidancePlaceholder', guidancePlaceholder);
    put('isGenerating', isGenerating);
    put('isEditing', isEditing);
    put('isDrawerOpen', isDrawerOpen);
    put('isQuickRepliesOpen', isQuickRepliesOpen);
    put('isSelectionMode', isSelectionMode);
    put('showSearch', showSearch);
    put('searchLabel', searchLabel);
    put('selectionLabel', selectionLabel);
    put('selectedCount', selectedCount);
    put('allSelectedHidden', allSelectedHidden);
    put('enterToSend', enterToSend);
    put('virtualKeyboardSend', virtualKeyboardSend);

    return _host.evalJs('window.bridge?.setInputState(${jsonEncode(payload)})');
  }

  /// Native-drawer height (magic / quick-replies). The WebView folds this into
  /// its bottom overlap so the input bar sits above the native panel.
  Future<void> setPanelInset(double px) {
    return _host.evalJs('window.bridge?.setPanelInset(${px.toStringAsFixed(1)})');
  }

  /// On-screen keyboard overlap, sourced from Flutter's `MediaQuery.viewInsets`
  /// (smooth / IME-synced on Android adjustResize). Pushed on the rising and
  /// falling edge with [animate] true so the WebView plays a single eased
  /// transition in sync with the platform keyboard, then once more with
  /// [animate] false as an exact settle correction. Replaces the WebView's own
  /// laggy `visualViewport` measurement for positioning the input bar.
  Future<void> setKeyboardInset(double px, {bool animate = false}) {
    return _host.evalJs(
      'window.bridge?.setKeyboardInset(${px.toStringAsFixed(1)}, $animate)',
    );
  }

  /// Clears the compose field / guidance / image after a validated send.
  Future<void> clearInput() {
    return _host.evalJs('window.bridge?.clearInput()');
  }

  Future<void> blurInput() {
    return _host.evalJs('window.bridge?.blurInput()');
  }

  Future<void> focusInput() {
    return _host.evalJs('window.bridge?.focusInput()');
  }
}
