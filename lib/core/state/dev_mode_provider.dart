import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shared_prefs_provider.dart';

/// Whether developer mode (hidden dev tools / settings) is unlocked.
/// Persisted across launches so the chosen state is remembered.
final devModeProvider = NotifierProvider<DevModeNotifier, bool>(
  DevModeNotifier.new,
);

class DevModeNotifier extends Notifier<bool> {
  static const _prefsKey = 'devModeEnabled';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider).value;
    return prefs?.getBool(_prefsKey) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_prefsKey, value);
  }

  Future<void> toggle() => set(!state);
}

/// Dev setting: hide the build-date watermark pinned to the bottom-right
/// corner of the screen. The watermark is visible by default.
final hideBuildWatermarkProvider =
    NotifierProvider<HideBuildWatermarkNotifier, bool>(
  HideBuildWatermarkNotifier.new,
);

class HideBuildWatermarkNotifier extends Notifier<bool> {
  static const _prefsKey = 'hideBuildWatermark';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider).value;
    return prefs?.getBool(_prefsKey) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_prefsKey, value);
  }

  Future<void> toggle() => set(!state);
}
