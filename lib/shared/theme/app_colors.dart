import 'package:flutter/material.dart';

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
    );
  }
}

extension GlazeColorsX on BuildContext {
  GlazeColors get colors => Theme.of(this).extension<GlazeColors>() ?? GlazeColors.dark;
}
