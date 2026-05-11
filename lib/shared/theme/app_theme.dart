import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'theme_preset.dart';

TextTheme _applySafe(TextTheme theme, {
  required Color bodyColor,
  required Color displayColor,
  required double fontSizeFactor,
  required double letterSpacingDelta,
}) {
  TextStyle? scale(TextStyle? s) {
    if (s == null) return null;
    return s.copyWith(
      color: s.color ?? bodyColor,
      fontSize: s.fontSize != null ? s.fontSize! * fontSizeFactor : null,
      letterSpacing: (s.letterSpacing ?? 0) + letterSpacingDelta,
    );
  }

  return TextTheme(
    displayLarge: scale(theme.displayLarge),
    displayMedium: scale(theme.displayMedium),
    displaySmall: scale(theme.displaySmall),
    headlineLarge: scale(theme.headlineLarge),
    headlineMedium: scale(theme.headlineMedium),
    headlineSmall: scale(theme.headlineSmall),
    titleLarge: scale(theme.titleLarge),
    titleMedium: scale(theme.titleMedium),
    titleSmall: scale(theme.titleSmall),
    bodyLarge: scale(theme.bodyLarge),
    bodyMedium: scale(theme.bodyMedium),
    bodySmall: scale(theme.bodySmall),
    labelLarge: scale(theme.labelLarge),
    labelMedium: scale(theme.labelMedium),
    labelSmall: scale(theme.labelSmall),
  );
}

Color _btnForeground(Color accent) {
  return accent.computeLuminance() > 0.35
      ? const Color(0xFF1A1A1B)
      : const Color(0xFFE1E3E6);
}

class AppTheme {
  static ThemeData dark(ThemePreset preset, {String? fontFamily}) {
    final accent = preset.accent;
    final c = GlazeColors.fromPreset(preset, isDark: true);
    final effectiveFont = fontFamily ?? GoogleFonts.inter().fontFamily;
    final uiSize = preset.uiFontSizeValue;
    final uiSpacing = preset.uiLetterSpacing;
    final scaleFactor = preset.uiFontSize is num ? uiSize / 14.0 : 1.0;
    final btnFg = _btnForeground(accent);

    final base = FlexThemeData.dark(
      colors: FlexSchemeColor.from(
        primary: accent,
        secondary: accent,
        tertiary: accent,
      ),
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 0,
      subThemesData: const FlexSubThemesData(
        inputDecoratorIsFilled: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        cardRadius: 16,
        dialogRadius: 16,
      ),
      visualDensity: VisualDensity.compact,
      fontFamily: effectiveFont,
    );

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: c.surfaceHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: c.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: accent),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: btnFg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.textPrimary,
        ),
      ),
      iconTheme: IconThemeData(color: c.textPrimary),
      textTheme: _applySafe(
        GoogleFonts.interTextTheme(base.textTheme),
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
        fontSizeFactor: scaleFactor,
        letterSpacingDelta: uiSpacing,
      ),
      extensions: [
        c,
        GptMarkdownThemeData(
          brightness: Brightness.dark,
          highlightColor: c.accent.withAlpha(40),
          linkColor: c.accent,
          linkHoverColor: c.accent.withAlpha(180),
          hrLineColor: c.border,
          h1: TextStyle(color: c.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
          h2: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
          h3: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
          h4: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          h5: TextStyle(color: c.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          h6: TextStyle(color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  static ThemeData light(ThemePreset preset, {String? fontFamily}) {
    final accent = preset.accent;
    final c = GlazeColors.fromPreset(preset, isDark: false);
    final effectiveFont = fontFamily ?? GoogleFonts.inter().fontFamily;
    final uiSize = preset.uiFontSizeValue;
    final uiSpacing = preset.uiLetterSpacing;
    final scaleFactor = preset.uiFontSize is num ? uiSize / 14.0 : 1.0;
    final btnFg = _btnForeground(accent);

    final base = FlexThemeData.light(
      colors: FlexSchemeColor.from(
        primary: accent,
        secondary: accent,
        tertiary: accent,
      ),
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 0,
      subThemesData: const FlexSubThemesData(
        inputDecoratorIsFilled: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        cardRadius: 16,
        dialogRadius: 16,
      ),
      visualDensity: VisualDensity.compact,
      fontFamily: effectiveFont,
    );

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: c.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: accent),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: btnFg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.textPrimary,
        ),
      ),
      iconTheme: IconThemeData(color: c.textPrimary),
      textTheme: _applySafe(
        GoogleFonts.interTextTheme(base.textTheme),
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
        fontSizeFactor: scaleFactor,
        letterSpacingDelta: uiSpacing,
      ),
      extensions: [
        c,
        GptMarkdownThemeData(
          brightness: Brightness.light,
          highlightColor: c.accent.withAlpha(40),
          linkColor: c.accent,
          linkHoverColor: c.accent.withAlpha(180),
          hrLineColor: c.border,
          h1: TextStyle(color: c.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
          h2: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
          h3: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
          h4: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          h5: TextStyle(color: c.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          h6: TextStyle(color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
