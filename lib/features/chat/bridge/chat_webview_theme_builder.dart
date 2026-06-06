import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';

/// Snapshot of the WebView theme inputs collected from the parent
/// [ChatWebViewWidget]. Pure data — the builder does not reach into
/// the widget tree on its own, which makes the same builder usable
/// in widget tests without a full [MaterialApp] ancestor.
class ChatWebViewThemeInput {
  const ChatWebViewThemeInput({
    required this.elementOpacity,
    required this.elementBlur,
    required this.chatFontSize,
    required this.chatLayout,
    required this.bgDim,
  });

  final double elementOpacity;
  final double elementBlur;
  final double chatFontSize;
  final String? chatLayout;
  final double bgDim;
}

/// Builds the `Map<String, String>` that [ChatBridgeController.applyTheme]
/// expects. Pure functions on top of a [BuildContext] and an input
/// snapshot. Extracted from `chat_webview_widget.dart` so the widget
/// can call [build] without owning the color helpers.
class ChatWebViewThemeBuilder {
  const ChatWebViewThemeBuilder._();

  /// Build the theme map for the current `BuildContext` and the
  /// widget's theme-related fields.
  static Map<String, String> build(
    BuildContext context,
    ChatWebViewThemeInput input,
  ) {
    final glaze = context.colors;
    final cs = context.cs;
    final primary = cs.primary;
    return {
      'bg-color': _colorHex(cs.surface),
      'text-color': _colorHex(cs.onSurface),
      'ui-bg-rgb': _colorRgb(cs.surface),
      'vk-blue-rgb': _colorRgb(primary),
      'primary-rgb': _colorRgb(primary),
      'user-bubble-color-rgb': _colorRgb(glaze.userBubble),
      'char-bubble-color-rgb': _colorRgb(glaze.charBubble),
      'user-text-color': _colorHex(glaze.userText ?? cs.onSurface),
      'char-text-color': _colorHex(glaze.charText ?? cs.onSurface),
      'user-quote-color': _colorHex(glaze.userQuote ?? cs.primary),
      'char-quote-color': _colorHex(glaze.charQuote ?? cs.primary),
      'user-italic-color': _colorHex(glaze.userItalic ?? cs.primary),
      'char-italic-color': _colorHex(glaze.charItalic ?? cs.primary),
      'primary-color': _colorHex(primary),
      'error-color': _colorHex(cs.error),
      'element-opacity': input.elementOpacity
          .clamp(0.0, 1.0)
          .toStringAsFixed(2),
      'element-blur': '${input.elementBlur.clamp(0.0, 64.0).round()}px',
      'font-size': '${input.chatFontSize}px',
      'chat-font-size': '${input.chatFontSize}px',
      'chat-layout': input.chatLayout ?? 'default',
      'bg-dim': input.bgDim.clamp(0.0, 1.0).toStringAsFixed(2),
    };
  }

  static String _colorRgb(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '$r, $g, $b';
  }

  static String _colorHex(Color c) {
    final a = c.a;
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    if (a >= 0.99) {
      return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    }
    final alphaR = (r * a + 255 * (1 - a)).round().clamp(0, 255);
    final alphaG = (g * a + 255 * (1 - a)).round().clamp(0, 255);
    final alphaB = (b * a + 0 * (1 - a)).round().clamp(0, 255);
    return '#${alphaR.toRadixString(16).padLeft(2, '0')}'
        '${alphaG.toRadixString(16).padLeft(2, '0')}'
        '${alphaB.toRadixString(16).padLeft(2, '0')}';
  }
}
