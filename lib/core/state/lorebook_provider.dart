import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lorebook.dart';
import '../../features/cloud_sync/services/sync_deletion_tracker.dart';
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

Future<void> loadLorebookSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final settingsJson = prefs.getString('lorebookSettings');
  if (settingsJson != null) {
    try {
      return;
    } catch (_) {}
  }
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
    ref.invalidateSelf();
  }

  Future<void> updateLorebook(Lorebook lorebook) async {
    final repo = ref.read(lorebookRepoProvider);
    await repo.put(lorebook);
    ref.invalidateSelf();
  }

  Future<void> deleteLorebook(String id) async {
    final repo = ref.read(lorebookRepoProvider);
    await repo.delete(id);
    await SyncDeletionTracker.record('lorebooks', id);
    ref.invalidateSelf();
  }
}
