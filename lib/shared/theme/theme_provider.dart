import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_preset.dart';
import 'theme_preset_storage.dart';

class ThemeSettings {
  final ThemeMode mode;
  final Color accentColor;
  final ThemePreset activePreset;
  final List<ThemePreset> presets;

  const ThemeSettings({
    this.mode = ThemeMode.dark,
    this.accentColor = const Color(0xFF7996CE),
    this.activePreset = const ThemePreset(id: 'default', name: 'Default'),
    this.presets = const [ThemePreset(id: 'default', name: 'Default')],
  });

  ThemeSettings copyWith({
    ThemeMode? mode,
    Color? accentColor,
    ThemePreset? activePreset,
    List<ThemePreset>? presets,
  }) =>
      ThemeSettings(
        mode: mode ?? this.mode,
        accentColor: accentColor ?? this.accentColor,
        activePreset: activePreset ?? this.activePreset,
        presets: presets ?? this.presets,
      );
}

class ThemeNotifier extends StateNotifier<ThemeSettings> {
  final ThemePresetStorage _storage = ThemePresetStorage();

  ThemeNotifier() : super(const ThemeSettings()) {
    _load();
  }

  Future<void> _load() async {
    final presets = await _storage.loadAll();
    final activeId = await _storage.loadActiveId();
    final active = presets.firstWhere(
      (p) => p.id == activeId,
      orElse: () => presets.first,
    );
    state = ThemeSettings(
      mode: state.mode,
      accentColor: active.accent,
      activePreset: active,
      presets: presets,
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
  }

  Future<void> setAccentColor(Color color) async {
    state = state.copyWith(accentColor: color);
  }

  Future<void> applyPreset(ThemePreset preset) async {
    state = state.copyWith(
      accentColor: preset.accent,
      activePreset: preset,
    );
    await _storage.setActive(preset.id);
  }

  Future<void> importPreset(ThemePreset preset) async {
    await _storage.addPreset(preset);
    final presets = await _storage.loadAll();
    state = state.copyWith(presets: presets);
  }

  Future<void> deletePreset(String id) async {
    await _storage.removePreset(id);
    final presets = await _storage.loadAll();
    var active = state.activePreset;
    if (active.id == id) {
      active = presets.first;
    }
    state = state.copyWith(
      presets: presets,
      activePreset: active,
      accentColor: active.accent,
    );
  }

  Future<void> reload() async {
    await _load();
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeSettings>(
  (ref) => ThemeNotifier(),
);
