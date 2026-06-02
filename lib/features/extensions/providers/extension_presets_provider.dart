import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/repositories/extension_presets_repository.dart';
import '../../../core/state/db_provider.dart';
import '../models/extension_preset.dart';

final extensionPresetsProvider =
    StateNotifierProvider<ExtensionPresetsNotifier, List<ExtensionPreset>>(
  (ref) => ExtensionPresetsNotifier(ref),
);

final extensionPresetByIdProvider =
    Provider.family<ExtensionPreset?, String>((ref, id) {
  final presets = ref.watch(extensionPresetsProvider);
  return presets.where((p) => p.id == id).firstOrNull;
});

class ExtensionPresetsNotifier extends StateNotifier<List<ExtensionPreset>> {
  ExtensionPresetsNotifier(this._ref) : super([]) {
    _load();
  }

  final Ref _ref;

  ExtensionPresetsRepository get _repo =>
      ExtensionPresetsRepository(_ref.read(appDbProvider));

  Future<void> _load() async {
    state = await _repo.getAll();
  }

  Future<void> add(ExtensionPreset preset) async {
    await _repo.insert(preset);
    state = [...state, preset];
  }

  Future<void> update(ExtensionPreset preset) async {
    await _repo.updatePreset(preset);
    state = [
      for (final p in state)
        if (p.id == preset.id) preset else p,
    ];
  }

  Future<void> delete(String id) async {
    await _repo.deletePreset(id);
    state = state.where((p) => p.id != id).toList();
  }

  Future<void> refresh() async {
    await _load();
  }
}
