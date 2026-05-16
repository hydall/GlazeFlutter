import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lorebook.dart';
import '../utils/sync_deletion_tracker.dart';
import 'db_provider.dart';

final lorebooksProvider = AsyncNotifierProvider<LorebooksNotifier, List<Lorebook>>(
  LorebooksNotifier.new,
);

final lorebookSettingsProvider = StateProvider<LorebookGlobalSettings>((ref) {
  return const LorebookGlobalSettings();
});

final lorebookActivationsProvider = StateProvider<LorebookActivations>((ref) {
  return const LorebookActivations();
});

Future<void> loadLorebookActivations(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('lorebookActivations');
  if (raw != null) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final charMap = <String, List<String>>{};
      final chatMap = <String, List<String>>{};

      final char = decoded['character'] as Map<String, dynamic>?;
      if (char != null) {
        for (final e in char.entries) {
          if (e.value is List) {
            charMap[e.key] = (e.value as List).map((v) => v.toString()).toList();
          }
        }
      }

      final chat = decoded['chat'] as Map<String, dynamic>?;
      if (chat != null) {
        for (final e in chat.entries) {
          if (e.value is List) {
            chatMap[e.key] = (e.value as List).map((v) => v.toString()).toList();
          }
        }
      }

      ref.read(lorebookActivationsProvider.notifier).state =
          LorebookActivations(character: charMap, chat: chatMap);
    } catch (_) {}
  }
}

Future<void> saveLorebookActivations(LorebookActivations activations) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('lorebookActivations', jsonEncode(activations.toJson()));
}

Future<void> loadLorebookSettings(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final settingsJson = prefs.getString('lorebookSettings');
  if (settingsJson != null) {
    try {
      final settings = LorebookGlobalSettings.fromJson(
          jsonDecode(settingsJson) as Map<String, dynamic>);
      ref.read(lorebookSettingsProvider.notifier).state = settings;
    } catch (_) {}
  }
}

Future<void> saveLorebookSettings(LorebookGlobalSettings settings) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('lorebookSettings', jsonEncode(settings.toJson()));
}

class LorebooksNotifier extends AsyncNotifier<List<Lorebook>> {
  @override
  Future<List<Lorebook>> build() async {
    final repo = ref.read(lorebookRepoProvider);
    return repo.getAll();
  }

  Future<void> addLorebook(Lorebook lorebook) async {
    final repo = ref.read(lorebookRepoProvider);
    await repo.put(lorebook);
    _syncActivationToPrefs(lorebook);
    ref.invalidateSelf();
  }

  Future<void> updateLorebook(Lorebook lorebook) async {
    final repo = ref.read(lorebookRepoProvider);
    await repo.put(lorebook);
    _syncActivationToPrefs(lorebook);
    ref.invalidateSelf();
  }

  void _syncActivationToPrefs(Lorebook lorebook) {
    if (lorebook.activationTargetId == null) return;
    if (lorebook.activationScope != 'character' && lorebook.activationScope != 'chat') return;
    final scope = lorebook.activationScope!;
    final targetId = lorebook.activationTargetId!;

    final current = ref.read(lorebookActivationsProvider);
    final map = scope == 'character'
        ? Map<String, List<String>>.from(current.character)
        : Map<String, List<String>>.from(current.chat);
    final list = List<String>.from(map[targetId] ?? []);
    if (!list.contains(lorebook.id)) {
      list.add(lorebook.id);
      map[targetId] = list;
      final updated = scope == 'character'
          ? current.copyWith(character: map)
          : current.copyWith(chat: map);
      ref.read(lorebookActivationsProvider.notifier).state = updated;
      saveLorebookActivations(updated);
    }
  }

  Future<void> deleteLorebook(String id) async {
    final repo = ref.read(lorebookRepoProvider);
    await repo.delete(id);
    await ref.read(embeddingRepoProvider).deleteBySourceId(id);
    await SyncDeletionTracker.record('lorebooks', id);

    final activations = ref.read(lorebookActivationsProvider);
    final charMap = <String, List<String>>{};
    for (final e in activations.character.entries) {
      charMap[e.key] = List<String>.from(e.value);
    }
    final chatMap = <String, List<String>>{};
    for (final e in activations.chat.entries) {
      chatMap[e.key] = List<String>.from(e.value);
    }
    for (final ids in charMap.values) { ids.remove(id); }
    for (final ids in chatMap.values) { ids.remove(id); }
    charMap.removeWhere((_, ids) => ids.isEmpty);
    chatMap.removeWhere((_, ids) => ids.isEmpty);
    final cleaned = LorebookActivations(character: charMap, chat: chatMap);
    ref.read(lorebookActivationsProvider.notifier).state = cleaned;
    await saveLorebookActivations(cleaned);

    ref.invalidateSelf();
  }
}
