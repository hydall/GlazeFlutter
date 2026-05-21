import 'package:flutter/material.dart';

import 'theme_preset.dart';

class GlazeColors extends ThemeExtension<GlazeColors> {
  final Color accent;
  final Color userBubble;
  final Color charBubble;
  final Color? userText;
  final Color? charText;
  final Color? userQuote;
  final Color? charQuote;
  final Color? userItalic;
  final Color? charItalic;

  const GlazeColors({
    required this.accent,
    required this.userBubble,
    required this.charBubble,
    this.userText,
    this.charText,
    this.userQuote,
    this.charQuote,
    this.userItalic,
    this.charItalic,
  });

  static const dark = GlazeColors(
    accent: Color(0xFF7996CE),
    userBubble: Color(0xFF7996CE),
    charBubble: Color(0xFF1E1E1E),
  );

  static const light = GlazeColors(
    accent: Color(0xFF7996CE),
    userBubble: Color(0xFF7996CE),
    charBubble: Color(0xFFEEEEF0),
  );

  // Defaults matching Glaze JS: quote = vk-blue (#7996ce), italic = gray (#888)
  static const _defaultQuote = Color(0xFF7996CE);
  static const _defaultItalic = Color(0xFF888888);

  static GlazeColors fromPreset(ThemePreset preset, {required bool isDark}) {
    final base = isDark ? dark : light;
    final accent = preset.accent;
    final uiColor = preset.uiColorParsed ?? _deriveUiColor(accent, isDark);
    final effectiveBg = uiColor;

    final userBubble = preset.userBubbleParsed ?? accent;
    final charBubbleRaw = preset.charBubbleParsed ?? base.charBubble;
    final charBubble = _distinctBubble(charBubbleRaw, effectiveBg, isDark);

    return base.copyWith(
      accent: accent,
      userBubble: userBubble,
      charBubble: charBubble,
      userText: _ensureContrast(preset.userTextParsed, userBubble),
      charText: _ensureContrast(preset.charTextParsed, charBubble),
      // If preset sets a quote/italic color — use it; otherwise fall back to JS defaults
      userQuote: preset.userQuoteParsed ?? _defaultQuote,
      charQuote: preset.charQuoteParsed ?? _defaultQuote,
      userItalic: preset.userItalicParsed ?? _defaultItalic,
      charItalic: preset.charItalicParsed ?? _defaultItalic,
    );
  }

  static Color _deriveUiColor(Color accent, bool isDark) {
    if (isDark) {
      final hsl = HSLColor.fromColor(accent);
      return HSLColor.fromAHSL(
        1.0,
        hsl.hue,
        (hsl.saturation * 0.6).clamp(0.0, 1.0),
        (hsl.lightness * 0.15).clamp(0.02, 0.12),
      ).toColor();
    }
    final hsl = HSLColor.fromColor(accent);
    return HSLColor.fromAHSL(
      1.0,
      hsl.hue,
      (hsl.saturation * 0.3).clamp(0.0, 1.0),
      (0.92 + hsl.lightness * 0.06).clamp(0.9, 0.97),
    ).toColor();
  }

  static Color _distinctBubble(Color bubble, Color bg, bool isDark) {
    final diff = ((bubble.r * 255 - bg.r * 255).abs()).round() +
        ((bubble.g * 255 - bg.g * 255).abs()).round() +
        ((bubble.b * 255 - bg.b * 255).abs()).round();
    if (diff < 60) {
      final factor = isDark ? 1.25 : 0.85;
      return Color.fromARGB(
        (bubble.a * 255).round(),
        (bubble.r * 255 * factor).round().clamp(0, 255),
        (bubble.g * 255 * factor).round().clamp(0, 255),
        (bubble.b * 255 * factor).round().clamp(0, 255),
      );
    }
    return bubble;
  }

  static Color _contrastFor(Color bg) {
    final lum = bg.computeLuminance();
    final hsl = HSLColor.fromColor(bg);
    final threshold = hsl.saturation > 0.2 ? 0.25 : 0.35;
    return lum > threshold ? const Color(0xFF1A1A1B) : const Color(0xFFE1E3E6);
  }

  static Color? _ensureContrast(Color? text, Color bg) {
    if (text == null) return _contrastFor(bg);
    final ratio = _contrastRatio(text, bg);
    if (ratio < 2.5) return _contrastFor(bg);
    return text;
  }

  static double _contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  @override
  GlazeColors copyWith({
    Color? accent,
    Color? userBubble,
    Color? charBubble,
    Color? userText,
    Color? charText,
    Color? userQuote,
    Color? charQuote,
    Color? userItalic,
    Color? charItalic,
  }) {
    return GlazeColors(
      accent: accent ?? this.accent,
      userBubble: userBubble ?? this.userBubble,
      charBubble: charBubble ?? this.charBubble,
      userText: userText ?? this.userText,
      charText: charText ?? this.charText,
      userQuote: userQuote ?? this.userQuote,
      charQuote: charQuote ?? this.charQuote,
      userItalic: userItalic ?? this.userItalic,
      charItalic: charItalic ?? this.charItalic,
    );
  }

  @override
  GlazeColors lerp(covariant GlazeColors? other, double t) {
    if (other == null) return this;
    return GlazeColors(
      accent: Color.lerp(accent, other.accent, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      charBubble: Color.lerp(charBubble, other.charBubble, t)!,
      userText: Color.lerp(userText, other.userText, t),
      charText: Color.lerp(charText, other.charText, t),
      userQuote: Color.lerp(userQuote, other.userQuote, t),
      charQuote: Color.lerp(charQuote, other.charQuote, t),
      userItalic: Color.lerp(userItalic, other.userItalic, t),
      charItalic: Color.lerp(charItalic, other.charItalic, t),
    );
  }
}

extension GlazeColorsX on BuildContext {
  GlazeColors get colors => Theme.of(this).extension<GlazeColors>() ?? GlazeColors.dark;
  ColorScheme get cs => Theme.of(this).colorScheme;
}
