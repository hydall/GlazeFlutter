import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData dark({Color? accent}) {
    final a = accent ?? AppColors.accent;
    final c = GlazeColors.dark.withAccent(a);

    final base = ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: a,
      useMaterial3: true,
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
          borderSide: BorderSide(color: a),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: a,
          foregroundColor: Colors.black,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: c.textPrimary),
        bodyMedium: TextStyle(color: c.textPrimary),
        bodySmall: TextStyle(color: c.textSecondary),
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

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
    );
  }

  static ThemeData light({Color? accent}) {
    final a = accent ?? AppColors.accent;
    final c = GlazeColors.light.withAccent(a);

    final base = ThemeData(
      brightness: Brightness.light,
      colorSchemeSeed: a,
      useMaterial3: true,
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
          borderSide: BorderSide(color: a),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: a,
          foregroundColor: Colors.black,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: c.textPrimary),
        bodyMedium: TextStyle(color: c.textPrimary),
        bodySmall: TextStyle(color: c.textSecondary),
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

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
    );
  }
}
