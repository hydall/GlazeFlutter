import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/pipeline_global_settings.dart';
import 'shared_prefs_provider.dart';

/// Global pipeline defaults, persisted in SharedPreferences under the
/// 'pipelineSettings' key. Loaded once at startup and folded into per-session
/// [PipelineSettings] rows by `PipelineSettingsRepo.ensureForSession`.
final pipelineGlobalSettingsProvider = StateNotifierProvider<
    PipelineGlobalSettingsNotifier, PipelineGlobalSettings>(
  (ref) => PipelineGlobalSettingsNotifier(ref),
);

class PipelineGlobalSettingsNotifier
    extends StateNotifier<PipelineGlobalSettings> {
  final Ref _ref;
  PipelineGlobalSettingsNotifier(this._ref)
      : super(const PipelineGlobalSettings());

  Future<void> load() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    final raw = prefs.getString('pipelineSettings');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        state = PipelineGlobalSettings.fromJson(json);
      } catch (_) {}
    }
  }

  Future<void> save(PipelineGlobalSettings settings) async {
    state = settings;
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    await prefs.setString('pipelineSettings', jsonEncode(settings.toJson()));
  }
}


