import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/repositories/lorebook_repo.dart';
import '../models/lorebook.dart';
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
    ref.invalidateSelf();
  }
}
