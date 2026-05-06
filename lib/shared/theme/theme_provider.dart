import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeSettings {
  final ThemeMode mode;
  final Color accentColor;
  const ThemeSettings({this.mode = ThemeMode.dark, this.accentColor = const Color(0xFF7996CE)});

  ThemeSettings copyWith({ThemeMode? mode, Color? accentColor}) =>
      ThemeSettings(mode: mode ?? this.mode, accentColor: accentColor ?? this.accentColor);
}

class ThemeNotifier extends StateNotifier<ThemeSettings> {
  ThemeNotifier() : super(const ThemeSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt('theme_mode') ?? 2;
    final accentHex = prefs.getString('theme_accent') ?? '7996CE';
    state = ThemeSettings(
      mode: ThemeMode.values[modeIndex.clamp(0, 2)],
      accentColor: _hexToColor(accentHex),
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  Future<void> setAccentColor(Color color) async {
    state = state.copyWith(accentColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_accent', _colorToHex(color));
  }

  Color _hexToColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  String _colorToHex(Color c) {
    return '${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
        '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
        '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeSettings>(
  (ref) => ThemeNotifier(),
);
