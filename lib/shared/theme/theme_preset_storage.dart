import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'theme_preset.dart';

class ThemePresetStorage {
  static const _presetsKey = 'theme_presets';
  static const _activeKey = 'theme_active_preset';

  Future<List<ThemePreset>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_presetsKey);
    if (raw == null) return [_defaultPreset];
    try {
      final list = jsonDecode(raw) as List;
      final presets = list.map((e) => ThemePreset.fromJson(e as Map<String, dynamic>)).toList();
      if (presets.isEmpty) presets.add(_defaultPreset);
      return presets;
    } catch (_) {
      return [_defaultPreset];
    }
  }

  Future<String> loadActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey) ?? 'default';
  }

  Future<void> saveAll(List<ThemePreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetsKey, jsonEncode(presets.map((e) => e.toJson()).toList()));
  }

  Future<void> saveActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
  }

  Future<ThemePreset> importFromFile(String path) async {
    final file = File(path);
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return _fromThemeJson(json);
  }

  Future<ThemePreset> importFromJson(String jsonStr) async {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return _fromThemeJson(json);
  }

  ThemePreset _fromThemeJson(Map<String, dynamic> json) {
    final isSillyCradle = json['_type'] == 'silly_cradle_theme';
    if (!isSillyCradle && json.containsKey('accentColor') == false) {
      throw const FormatException('Not a valid theme file');
    }

    final id = 'imported_${DateTime.now().millisecondsSinceEpoch}';
    final name = json['name'] as String? ?? 'Imported Theme';

    final stripped = Map<String, dynamic>.from(json)
      ..remove('_type')
      ..remove('id')
      ..remove('name');

    stripped['id'] = id;
    stripped['name'] = name;

    return ThemePreset.fromJson(stripped);
  }

  Future<void> addPreset(ThemePreset preset) async {
    final presets = await loadAll();
    final idx = presets.indexWhere((p) => p.id == preset.id);
    if (idx >= 0) {
      presets[idx] = preset;
    } else {
      presets.add(preset);
    }
    await saveAll(presets);
  }

  Future<void> removePreset(String id) async {
    if (id == 'default') return;
    final presets = await loadAll();
    presets.removeWhere((p) => p.id == id);
    await saveAll(presets);
  }

  Future<void> setActive(String id) async {
    await saveActiveId(id);
  }
}

final _defaultPreset = ThemePreset(
  id: 'default',
  name: 'Default',
  accentColor: '#7996CE',
  bgOpacity: 0.85,
  elementOpacity: 0.8,
  elementBlur: 12,
  chatLayout: 'default',
  borderWidth: 1,
  borderOpacity: 0.1,
  noiseOpacity: 0.03,
  noiseIntensity: 0.8,
  bgNoiseOpacity: 0.03,
  bgNoiseIntensity: 0.4,
);
