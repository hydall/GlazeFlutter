import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/persona.dart';
import '../models/preset.dart';
import 'db_provider.dart';
import 'memory_settings_provider.dart';
import 'shared_prefs_provider.dart';

import 'global_regex_provider.dart';
import '../../features/personas/persona_list_provider.dart';

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
  final prefs = await ref.read(sharedPreferencesProvider.future);
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
  final prefs = await ref.read(sharedPreferencesProvider.future);
  if (id != null) {
    await prefs.setString('activePresetId', id);
  } else {
    await prefs.remove('activePresetId');
  }
}

Future<void> setActivePersona(WidgetRef ref, String? id) async {
  ref.read(activePersonaIdProvider.notifier).state = id;
  final prefs = await ref.read(sharedPreferencesProvider.future);
  if (id != null) {
    await prefs.setString('activePersonaId', id);
  } else {
    await prefs.remove('activePersonaId');
  }
}

PersonaConnections _buildUpdatedConnections(
  PersonaConnections current,
  String type,
  String targetId,
  String? personaId,
) {
  if (type == 'character') {
    final map = Map<String, String>.from(current.character);
    if (personaId == null) {
      map.remove(targetId);
    } else {
      map[targetId] = personaId;
    }
    return current.copyWith(character: map);
  } else {
    final map = Map<String, String>.from(current.chat);
    if (personaId == null) {
      map.remove(targetId);
    } else {
      map[targetId] = personaId;
    }
    return current.copyWith(chat: map);
  }
}

Future<void> setPersonaConnection(
  WidgetRef ref,
  String type,
  String targetId,
  String? personaId,
) async {
  final current = ref.read(personaConnectionsProvider);
  final updated = _buildUpdatedConnections(current, type, targetId, personaId);
  ref.read(personaConnectionsProvider.notifier).state = updated;
  final prefs = await ref.read(sharedPreferencesProvider.future);
  await prefs.setString('personaConnections', jsonEncode(updated.toJson()));
}

void setPersonaConnectionRef(
  Ref ref,
  String type,
  String targetId,
  String? personaId,
) {
  final current = ref.read(personaConnectionsProvider);
  final updated = _buildUpdatedConnections(current, type, targetId, personaId);
  ref.read(personaConnectionsProvider.notifier).state = updated;
  final prefs = ref.read(sharedPreferencesProvider).valueOrNull;
  if (prefs != null) {
    prefs.setString('personaConnections', jsonEncode(updated.toJson()));
  }
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

typedef EffectivePersonaChatKey = ({String charId, String? sessionId});

final effectivePersonaForChatProvider =
    Provider.family<Persona?, EffectivePersonaChatKey>((ref, key) {
  final personasAsync = ref.watch(personaListProvider);
  if (!personasAsync.hasValue) return null;

  final activePersonaId = ref.watch(activePersonaIdProvider);
  final personaConnections = ref.watch(personaConnectionsProvider);
  return getEffectivePersona(
    personasAsync.requireValue,
    key.charId,
    key.sessionId,
    activePersonaId,
    personaConnections,
  );
});

void updateGlobalVarsRef(Ref ref, Map<String, String> vars) {
  ref.read(globalVarsProvider.notifier).state = vars;
  final prefs = ref.read(sharedPreferencesProvider).valueOrNull;
  if (prefs != null) {
    prefs.setString('globalVars', jsonEncode(vars));
  }
}
