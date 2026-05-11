import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'theme_preset.freezed.dart';
part 'theme_preset.g.dart';

@Freezed(fromJson: true, toJson: true)
class ThemePreset with _$ThemePreset {
  const factory ThemePreset({
    required String id,
    required String name,
    @Default('') String author,
    @Default('dark') String themeMode,
    @Default('#7996CE') String accentColor,
    @Default(0.85) double bgOpacity,
    @Default(0) double bgBlur,
    @Default(0.8) double elementOpacity,
    @Default(12) double elementBlur,
    String? uiColor,
    @Default('default') String chatLayout,
    String? userBubbleColor,
    String? charBubbleColor,
    String? userQuoteColor,
    String? charQuoteColor,
    String? userTextColor,
    String? charTextColor,
    String? userItalicColor,
    String? charItalicColor,
    @Default('system') dynamic uiFontSize,
    @Default(0) double uiLetterSpacing,
    @Default('system') dynamic chatFontSize,
    @Default(0) double chatLetterSpacing,
    String? customFont,
    String? customFontName,
    String? chatFont,
    String? chatFontName,
    @Default('glaze') String uiFontMode,
    @Default('ui') String chatFontMode,
    String? uiTextColor,
    String? uiTextGrayColor,
    @Default(1) double borderWidth,
    String? borderColor,
    @Default(0.1) double borderOpacity,
    @Default(0.03) double noiseOpacity,
    @Default(0.8) double noiseIntensity,
    @Default(0.03) double bgNoiseOpacity,
    @Default(0.4) double bgNoiseIntensity,
    String? bgImage,
  }) = _ThemePreset;

  factory ThemePreset.fromJson(Map<String, dynamic> json) =>
      _$ThemePresetFromJson(json);
}

extension ThemePresetX on ThemePreset {
  Color get accent => _parseHex(accentColor);
  Color? get uiColorParsed => _parseNullableHex(uiColor);
  Color? get userBubbleParsed => _parseNullableHex(userBubbleColor);
  Color? get charBubbleParsed => _parseNullableHex(charBubbleColor);
  Color? get userQuoteParsed => _parseNullableHex(userQuoteColor);
  Color? get charQuoteParsed => _parseNullableHex(charQuoteColor);
  Color? get userTextParsed => _parseNullableHex(userTextColor);
  Color? get charTextParsed => _parseNullableHex(charTextColor);
  Color? get userItalicParsed => _parseNullableHex(userItalicColor);
  Color? get charItalicParsed => _parseNullableHex(charItalicColor);
  Color? get uiTextParsed => _parseNullableHex(uiTextColor);
  Color? get uiTextGrayParsed => _parseNullableHex(uiTextGrayColor);
  Color? get borderParsed => _parseNullableHex(borderColor);

  double get chatFontSizeValue {
    final v = chatFontSize;
    if (v is num) return v.toDouble();
    return 14.0;
  }

  double get uiFontSizeValue {
    final v = uiFontSize;
    if (v is num) return v.toDouble();
    return 14.0;
  }

  bool get hasCustomFont => customFont != null && customFont!.isNotEmpty;
  bool get hasChatFont => chatFont != null && chatFont!.isNotEmpty;
  bool get hasBgImage => bgImage != null && bgImage!.isNotEmpty;
}

Color _parseHex(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  if (clean.length == 8) {
    return Color(int.parse(clean, radix: 16));
  }
  return const Color(0xFF7996CE);
}

Color? _parseNullableHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  return _parseHex(hex);
}
