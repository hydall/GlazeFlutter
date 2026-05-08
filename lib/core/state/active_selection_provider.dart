import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/persona.dart';
import '../models/preset.dart';
import 'db_provider.dart';
import 'memory_settings_provider.dart';

import 'global_regex_provider.dart';

final activePresetIdProvider = StateProvider<String?>((ref) => null);
final activePersonaIdProvider = StateProvider<String?>((ref) => null);

final globalVarsProvider = StateProvider<Map<String, String>>((ref) => {});

final personaConnectionsProvider = StateProvider<PersonaConnections>((ref) {
  return const PersonaConnections();
});

final activeRegexesProvider = FutureProvider<List<PresetRegex>>((ref) async {
  final repo = ref.watch(presetRepoProvider);
  final presets = await repo.getAll();
  final activeId = ref.watch(activePresetIdProvider);
  final preset = activeId != null
      ? presets.where((p) => p.id == activeId).firstOrNull
      : (presets.isNotEmpty ? presets.first : null);
  final presetRegexes = preset?.regexes.where((r) => !r.disabled).toList() ?? <PresetRegex>[];
  final globalRegexes = ref.watch(globalRegexProvider).valueOrNull?.where((r) => !r.disabled).toList() ?? <PresetRegex>[];
  return [...presetRegexes, ...globalRegexes];
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
  final pcJson = prefs.getString('personaConnections');
  if (pcJson != null) {
    try {
      ref.read(personaConnectionsProvider.notifier).state =
          PersonaConnections.fromJson(jsonDecode(pcJson) as Map<String, dynamic>);
    } catch (_) {}
  }
  ref.read(memoryGlobalSettingsProvider.notifier).load();
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

Future<void> setPersonaConnection(
  WidgetRef ref,
  String type,
  String targetId,
  String? personaId,
) async {
  final current = ref.read(personaConnectionsProvider);
  PersonaConnections updated;
  if (type == 'character') {
    final map = Map<String, String>.from(current.character);
    if (personaId == null) {
      map.remove(targetId);
    } else {
      map[targetId] = personaId;
    }
    updated = current.copyWith(character: map);
  } else {
    final map = Map<String, String>.from(current.chat);
    if (personaId == null) {
      map.remove(targetId);
    } else {
      map[targetId] = personaId;
    }
    updated = current.copyWith(chat: map);
  }
  ref.read(personaConnectionsProvider.notifier).state = updated;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('personaConnections', jsonEncode(updated.toJson()));
}

void setPersonaConnectionRef(
  Ref ref,
  String type,
  String targetId,
  String? personaId,
) {
  final current = ref.read(personaConnectionsProvider);
  PersonaConnections updated;
  if (type == 'character') {
    final map = Map<String, String>.from(current.character);
    if (personaId == null) {
      map.remove(targetId);
    } else {
      map[targetId] = personaId;
    }
    updated = current.copyWith(character: map);
  } else {
    final map = Map<String, String>.from(current.chat);
    if (personaId == null) {
      map.remove(targetId);
    } else {
      map[targetId] = personaId;
    }
    updated = current.copyWith(chat: map);
  }
  ref.read(personaConnectionsProvider.notifier).state = updated;
  _persistPersonaConnections(updated);
}

Future<void> _persistPersonaConnections(PersonaConnections conns) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('personaConnections', jsonEncode(conns.toJson()));
}

Persona? getEffectivePersona(
  List<Persona> personas,
  String? charId,
  String? sessionId,
  String? globalPersonaId,
  PersonaConnections connections,
) {
  if (sessionId != null) {
    final chatPersonaId = connections.chat[sessionId];
    if (chatPersonaId != null) {
      final p = personas.where((p) => p.id == chatPersonaId).firstOrNull;
      if (p != null) return p;
    }
  }
  if (charId != null) {
    final charPersonaId = connections.character[charId];
    if (charPersonaId != null) {
      final p = personas.where((p) => p.id == charPersonaId).firstOrNull;
      if (p != null) return p;
    }
  }
  if (globalPersonaId != null) {
    final p = personas.where((p) => p.id == globalPersonaId).firstOrNull;
    if (p != null) return p;
  }
  return personas.isNotEmpty ? personas.first : null;
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
