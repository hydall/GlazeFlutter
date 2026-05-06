import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/preset.dart';
import 'db_provider.dart';

final activePresetIdProvider = StateProvider<String?>((ref) => null);
final activePersonaIdProvider = StateProvider<String?>((ref) => null);
final globalVarsProvider = StateProvider<Map<String, String>>((ref) => {});

final activeRegexesProvider = FutureProvider<List<PresetRegex>>((ref) async {
  final repo = ref.watch(presetRepoProvider);
  final presets = await repo.getAll();
  final activeId = ref.watch(activePresetIdProvider);
  final preset = activeId != null
      ? presets.where((p) => p.id == activeId).firstOrNull
      : (presets.isNotEmpty ? presets.first : null);
  if (preset == null) return [];
  return preset.regexes.where((r) => !r.disabled).toList();
});

Future<void> loadActiveSelections(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  ref.read(activePresetIdProvider.notifier).state =
      prefs.getString('activePresetId');
  ref.read(activePersonaIdProvider.notifier).state =
      prefs.getString('activePersonaId');
  final gvJson = prefs.getString('globalVars');
  if (gvJson != null) {
    try {
      final map = jsonDecode(gvJson) as Map<String, dynamic>;
      ref.read(globalVarsProvider.notifier).state =
          map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}
  }
}

Future<void> setActivePreset(WidgetRef ref, String? id) async {
  ref.read(activePresetIdProvider.notifier).state = id;
  final prefs = await SharedPreferences.getInstance();
  if (id != null) {
    await prefs.setString('activePresetId', id);
  } else {
    await prefs.remove('activePresetId');
  }
}

Future<void> setActivePersona(WidgetRef ref, String? id) async {
  ref.read(activePersonaIdProvider.notifier).state = id;
  final prefs = await SharedPreferences.getInstance();
  if (id != null) {
    await prefs.setString('activePersonaId', id);
  } else {
    await prefs.remove('activePersonaId');
  }
}

Future<void> _persistGlobalVars(Map<String, String> vars) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('globalVars', jsonEncode(vars));
}

void updateGlobalVarsRef(Ref ref, Map<String, String> vars) {
  ref.read(globalVarsProvider.notifier).state = vars;
  _persistGlobalVars(vars);
}

void updateGlobalVarsWidgetRef(WidgetRef ref, Map<String, String> vars) {
  ref.read(globalVarsProvider.notifier).state = vars;
  _persistGlobalVars(vars);
}
