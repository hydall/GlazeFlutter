import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/theme_provider.dart';
import '../theme/theme_preset.dart';

final chatFontSizeProvider = Provider<double>((ref) {
  final preset = ref.watch(themeProvider).activePreset;
  return preset.chatFontSizeValue;
});

final chatLetterSpacingProvider = Provider<double>((ref) {
  final preset = ref.watch(themeProvider).activePreset;
  return preset.chatLetterSpacing;
});

class ChatFontStyle {
  final double fontSize;
  final double letterSpacing;
  final String? fontFamily;
  const ChatFontStyle({required this.fontSize, required this.letterSpacing, this.fontFamily});
}

final chatFontStyleProvider = Provider<ChatFontStyle>((ref) {
  final preset = ref.watch(themeProvider).activePreset;
  return ChatFontStyle(
    fontSize: preset.chatFontSizeValue,
    letterSpacing: preset.chatLetterSpacing,
    fontFamily: ref.watch(chatFontFamilyProvider).valueOrNull,
  );
});

final uiFontSizeProvider = Provider<double?>((ref) {
  final preset = ref.watch(themeProvider).activePreset;
  final v = preset.uiFontSize;
  if (v == 'system' || v == null) return null;
  return preset.uiFontSizeValue;
});

final uiLetterSpacingProvider = Provider<double>((ref) {
  final preset = ref.watch(themeProvider).activePreset;
  return preset.uiLetterSpacing;
});

final _loadedFonts = <String>{};

Uint8List? _extractFontBytes(String dataUri) {
  String base64Str;
  final commaIdx = dataUri.indexOf(',');
  if (commaIdx != -1) {
    base64Str = dataUri.substring(commaIdx + 1);
  } else {
    base64Str = dataUri;
  }

  try {
    final bytes = base64Decode(base64Str);

    // Validate: real font files start with known magic bytes
    // TrueType: 0x00 0x01 0x00 0x00
    // OpenType/CFF: 'OTTO'
    // WOFF: 'wOFF'
    // WOFF2: 'wOF2'
    // TrueType Collection: 'ttcf'
    if (bytes.length < 4) return null;
    final b0 = bytes[0], b1 = bytes[1], b2 = bytes[2], b3 = bytes[3];
    final isTtf = b0 == 0x00 && b1 == 0x01 && b2 == 0x00 && b3 == 0x00;
    final isOtf = b0 == 0x4F && b1 == 0x54 && b2 == 0x54 && b3 == 0x4F; // OTTO
    final isWoff = b0 == 0x77 && b1 == 0x4F && b2 == 0x46 && b3 == 0x46; // wOFF
    final isWoff2 = b0 == 0x77 && b1 == 0x4F && b2 == 0x46 && b3 == 0x32; // wOF2
    final isTtc = b0 == 0x74 && b1 == 0x74 && b2 == 0x63 && b3 == 0x66; // ttcf

    if (!isTtf && !isOtf && !isWoff && !isWoff2 && !isTtc) return null;

    return bytes;
  } catch (_) {
    return null;
  }
}

Future<String?> _loadFontFromBase64(String dataUri, String name) async {
  if (_loadedFonts.contains(name)) return name;

  try {
    final bytes = _extractFontBytes(dataUri);
    if (bytes == null) return null;

    await ui.loadFontFromList(bytes, fontFamily: name);
    _loadedFonts.add(name);
    return name;
  } catch (_) {
    return null;
  }
}

final chatFontFamilyProvider = FutureProvider<String?>((ref) async {
  final preset = ref.watch(themeProvider).activePreset;
  if (preset.chatFontMode != 'custom') return null;
  if (!preset.hasChatFont || preset.chatFontName == null) return null;
  return _loadFontFromBase64(preset.chatFont!, preset.chatFontName!);
});

final uiFontFamilyProvider = FutureProvider<String?>((ref) async {
  final preset = ref.watch(themeProvider).activePreset;
  if (preset.uiFontMode != 'custom') return null;
  if (!preset.hasCustomFont || preset.customFontName == null) return null;
  return _loadFontFromBase64(preset.customFont!, preset.customFontName!);
});

final bgImageProvider = FutureProvider<String?>((ref) async {
  final preset = ref.watch(themeProvider).activePreset;
  if (!preset.hasBgImage) return null;

  try {
    final data = preset.bgImage!;
    final commaIdx = data.indexOf(',');
    if (commaIdx == -1) return null;
    final base64Str = data.substring(commaIdx + 1);
    final bytes = base64Decode(base64Str);

    final dir = await getApplicationSupportDirectory();
    final hash = base64Str.length.hashCode.toRadixString(36);
    final file = File('${dir.path}/bg/$hash.jpg');
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    await file.writeAsBytes(bytes);
    return file.path;
  } catch (_) {
    return null;
  }
});
