import 'package:flutter/material.dart';

import 'theme_preset.dart';

class GlazeColors extends ThemeExtension<GlazeColors> {
  final Color userBubble;
  final Color charBubble;
  final Color? userText;
  final Color? charText;
  final Color? userQuote;
  final Color? charQuote;
  final Color? userItalic;
  final Color? charItalic;

  const GlazeColors({
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
    userBubble: Color(0xFF7996CE),
    charBubble: Color(0xFF1E1E1E),
  );

  static const light = GlazeColors(
    userBubble: Color(0xFF7996CE),
    charBubble: Color(0xFFEEEEF0),
  );

  static GlazeColors fromPreset(ThemePreset preset, {required bool isDark}) {
    final base = isDark ? dark : light;
    final accent = preset.accent;
    final uiColor = preset.uiColorParsed ?? _deriveUiColor(accent, isDark);
    final effectiveBg = uiColor;

    final userBubble = preset.userBubbleParsed ?? accent;
    final charBubbleRaw = preset.charBubbleParsed ?? base.charBubble;
    final charBubble = _distinctBubble(charBubbleRaw, effectiveBg, isDark);

    return base.copyWith(
      userBubble: userBubble,
      charBubble: charBubble,
      userText: _ensureContrast(preset.userTextParsed, userBubble),
      charText: _ensureContrast(preset.charTextParsed, charBubble),
      userQuote: preset.userQuoteParsed ?? _contrastFor(userBubble).withValues(alpha: 0.7),
      charQuote: preset.charQuoteParsed ?? _contrastFor(charBubble).withValues(alpha: 0.7),
      userItalic: preset.userItalicParsed,
      charItalic: preset.charItalicParsed,
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
    final diff = (bubble.red - bg.red).abs() +
        (bubble.green - bg.green).abs() +
        (bubble.blue - bg.blue).abs();
    if (diff < 60) {
      final factor = isDark ? 1.25 : 0.85;
      return Color.fromARGB(
        bubble.alpha,
        (bubble.red * factor).clamp(0, 255).round(),
        (bubble.green * factor).clamp(0, 255).round(),
        (bubble.blue * factor).clamp(0, 255).round(),
      );
    }
    return bubble;
  }

  static Color _contrastFor(Color bg) {
    final lum = bg.computeLuminance();
    return lum > 0.35 ? const Color(0xFF1A1A1B) : const Color(0xFFE1E3E6);
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
