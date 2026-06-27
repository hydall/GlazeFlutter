import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/pipeline_settings.dart';
import 'shared_prefs_provider.dart';

/// Global pipeline LLM settings, persisted in SharedPreferences under the
/// 'pipelineSettings' key. Loaded once at startup. This is a singleton global —
/// the same [PipelineSettings] instance applies to every chat session.
///
/// Previously a per-session Drift row (`pipeline_settings_rows`) merged with a
/// [PipelineGlobalSettings] subset; that table was dropped in schema v52 and
/// the two freezed classes were merged into this single [PipelineSettings]
/// shape.
final pipelineSettingsProvider = StateNotifierProvider<
    PipelineSettingsNotifier, PipelineSettings>(
  (ref) => PipelineSettingsNotifier(ref),
);

class PipelineSettingsNotifier extends StateNotifier<PipelineSettings> {
  final Ref _ref;
  PipelineSettingsNotifier(this._ref) : super(const PipelineSettings());

  Future<void> load() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    final raw = prefs.getString('pipelineSettings');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        state = PipelineSettings.fromJson(json);
      } catch (_) {}
    }
  }

  Future<void> save(PipelineSettings settings) async {
    state = settings;
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    await prefs.setString('pipelineSettings', jsonEncode(settings.toJson()));
  }
}
