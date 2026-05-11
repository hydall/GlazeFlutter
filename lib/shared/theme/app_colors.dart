import 'package:flutter/material.dart';

import 'theme_preset.dart';

class AppColors {
  static const Color background = Color(0xFF19191A);
  static const Color surface = Color(0xFF19191A);
  static const Color surfaceHigh = Color(0xFF1E1E1E);
  static const Color accent = Color(0xFF7996CE);
  static const Color activeTab = Color(0xFF7996CE);
  static const Color inactiveTab = Color(0xFF828282);
  static const Color textPrimary = Color(0xFFE1E3E6);
  static const Color textSecondary = Color(0xFFB0B8C1);
  static const Color border = Color(0xFF2C2D2E);
  static const Color glassBorder = Color(0x1AFFFFFF);
  static const Color userBubble = Color(0xFF7996CE);
  static const Color charBubble = Color(0xFF1E1E1E);
}

class GlazeColors extends ThemeExtension<GlazeColors> {
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color accent;
  final Color activeTab;
  final Color inactiveTab;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color glassBorder;
  final Color userBubble;
  final Color charBubble;
  final Color? userText;
  final Color? charText;
  final Color? userQuote;
  final Color? charQuote;
  final Color? userItalic;
  final Color? charItalic;

  const GlazeColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.accent,
    required this.activeTab,
    required this.inactiveTab,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.glassBorder,
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
    background: Color(0xFF19191A),
    surface: Color(0xFF19191A),
    surfaceHigh: Color(0xFF1E1E1E),
    accent: Color(0xFF7996CE),
    activeTab: Color(0xFF7996CE),
    inactiveTab: Color(0xFF828282),
    textPrimary: Color(0xFFE1E3E6),
    textSecondary: Color(0xFFB0B8C1),
    border: Color(0xFF2C2D2E),
    glassBorder: Color(0x1AFFFFFF),
    userBubble: Color(0xFF7996CE),
    charBubble: Color(0xFF1E1E1E),
  );

  static const light = GlazeColors(
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEEEEF0),
    accent: Color(0xFF7996CE),
    activeTab: Color(0xFF7996CE),
    inactiveTab: Color(0xFF828282),
    textPrimary: Color(0xFF1A1A1B),
    textSecondary: Color(0xFF6B6D70),
    border: Color(0xFFD8D9DA),
    glassBorder: Color(0x1A000000),
    userBubble: Color(0xFF7996CE),
    charBubble: Color(0xFFEEEEF0),
  );

  GlazeColors withAccent(Color c) => copyWith(
        accent: c,
        activeTab: c,
        userBubble: c,
      );

  static GlazeColors fromPreset(ThemePreset preset, {required bool isDark}) {
    final base = isDark ? dark : light;
    final accent = preset.accent;
    final uiColor = preset.uiColorParsed ?? _deriveUiColor(accent, isDark);
    final effectiveBg = uiColor;

    final userBubble = preset.userBubbleParsed ?? accent;
    final charBubbleRaw = preset.charBubbleParsed ?? base.charBubble;
    final charBubble = _distinctBubble(charBubbleRaw, effectiveBg, isDark);

    final textPrimary = preset.uiTextParsed ?? _contrastFor(effectiveBg);
    final textSecondary = preset.uiTextGrayParsed ?? _contrastFor(effectiveBg, secondary: true);

    return base.copyWith(
      accent: accent,
      activeTab: accent,
      userBubble: userBubble,
      charBubble: charBubble,
      border: preset.borderParsed ?? _borderFor(effectiveBg, isDark),
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      surface: uiColor,
      surfaceHigh: _shiftColor(uiColor, isDark ? 1.08 : 0.96),
      background: uiColor,
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

  static Color _shiftColor(Color c, double factor) {
    return Color.fromARGB(
      c.alpha,
      (c.red * factor).clamp(0, 255).round(),
      (c.green * factor).clamp(0, 255).round(),
      (c.blue * factor).clamp(0, 255).round(),
    );
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

  static Color _contrastFor(Color bg, {bool secondary = false}) {
    final lum = bg.computeLuminance();
    final light = secondary
        ? const Color(0xFFB0B8C1)
        : const Color(0xFFE1E3E6);
    final dark = secondary
        ? const Color(0xFF6B6D70)
        : const Color(0xFF1A1A1B);
    return lum > 0.35 ? dark : light;
  }

  static Color _borderFor(Color bg, bool isDark) {
    final lum = bg.computeLuminance();
    if (isDark) {
      return lum > 0.35
          ? const Color(0xFF5C5D5E)
          : const Color(0xFF2C2D2E);
    }
    return lum > 0.35
        ? const Color(0xFFB8B9BA)
        : const Color(0xFFD8D9DA);
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
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? accent,
    Color? activeTab,
    Color? inactiveTab,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? glassBorder,
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
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      accent: accent ?? this.accent,
      activeTab: activeTab ?? this.activeTab,
      inactiveTab: inactiveTab ?? this.inactiveTab,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      glassBorder: glassBorder ?? this.glassBorder,
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
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      activeTab: Color.lerp(activeTab, other.activeTab, t)!,
      inactiveTab: Color.lerp(inactiveTab, other.inactiveTab, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
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
}
