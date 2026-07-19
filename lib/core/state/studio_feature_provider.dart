import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global master switch for the **Studio** experimental feature.
///
/// Studio is otherwise a per-session setting ([StudioConfig.enabled]). This
/// provider is the app-wide gate exposed from Settings → Experimental Features:
///
/// * When `false` (the default), Studio never runs in chat — the generation
///   pipeline treats every session's Studio config as disabled — and the Studio
///   card is hidden from the magic drawer (Quick Access / Tools).
/// * When `true`, Studio behaves as before, honouring each session's own
///   [StudioConfig.enabled] flag.
///
/// Ext Blocks has an equivalent master flag inside `ExtensionsSettings.enabled`;
/// this provider covers Studio, which had no global on/off before.
final studioFeatureEnabledProvider =
    StateNotifierProvider<StudioFeatureEnabledNotifier, bool>(
      (ref) => StudioFeatureEnabledNotifier(),
    );

class StudioFeatureEnabledNotifier extends StateNotifier<bool> {
  StudioFeatureEnabledNotifier() : super(false) {
    _load();
  }

  static const _storageKey = 'feature_studio_enabled';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_storageKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey, enabled);
  }
}
