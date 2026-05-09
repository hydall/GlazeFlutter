import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryGlobalSettings {
  final bool enabled;
  final bool autoCreateEnabled;
  final bool autoGenerateEnabled;
  final int maxInjectedEntries;
  final int autoCreateInterval;
  final bool useDelayedAutomation;
  final String injectionTarget;
  final int batchSize;
  final int parallelJobs;
  final bool vectorSearchEnabled;
  final String keyMatchMode;
  final String generationSource;
  final String generationModel;
  final bool generationUseCurrentModelOverride;
  final String generationEndpoint;
  final String generationApiKey;
  final double? generationTemperature;
  final int? generationMaxTokens;
  final String promptPreset;
  final List<Map<String, dynamic>> customPrompts;

  const MemoryGlobalSettings({
    this.enabled = true,
    this.autoCreateEnabled = true,
    this.autoGenerateEnabled = false,
    this.maxInjectedEntries = 7,
    this.autoCreateInterval = 15,
    this.useDelayedAutomation = true,
    this.injectionTarget = 'summary_block',
    this.batchSize = 3,
    this.parallelJobs = 1,
    this.vectorSearchEnabled = false,
    this.keyMatchMode = 'glaze',
    this.generationSource = 'current',
    this.generationModel = '',
    this.generationUseCurrentModelOverride = false,
    this.generationEndpoint = '',
    this.generationApiKey = '',
    this.generationTemperature,
    this.generationMaxTokens,
    this.promptPreset = 'detailed_beats',
    this.customPrompts = const [],
  });

  factory MemoryGlobalSettings.fromJson(Map<String, dynamic> json) {
    return MemoryGlobalSettings(
      enabled: json['enabled'] as bool? ?? true,
      autoCreateEnabled: json['autoCreateEnabled'] as bool? ?? true,
      autoGenerateEnabled: json['autoGenerateEnabled'] as bool? ?? false,
      maxInjectedEntries: _toInt(json['maxInjectedEntries']) ?? 7,
      autoCreateInterval: _toInt(json['autoCreateInterval']) ?? 15,
      useDelayedAutomation: json['useDelayedAutomation'] as bool? ?? true,
      injectionTarget: json['injectionTarget'] == 'summary_macro'
          ? 'summary_macro'
          : 'summary_block',
      batchSize: _toInt(json['batchSize']) ?? 3,
      parallelJobs: _toInt(json['parallelJobs']) ?? 1,
      vectorSearchEnabled: json['vectorSearchEnabled'] as bool? ?? false,
      keyMatchMode: ['plain', 'glaze', 'both'].contains(json['keyMatchMode'])
          ? json['keyMatchMode'] as String
          : 'glaze',
      generationSource: json['generationSource'] == 'custom'
          ? 'custom'
          : 'current',
      generationModel: json['generationModel'] is String
          ? json['generationModel'] as String
          : '',
      generationUseCurrentModelOverride:
          json['generationUseCurrentModelOverride'] as bool? ?? false,
      generationEndpoint: json['generationEndpoint'] is String
          ? json['generationEndpoint'] as String
          : '',
      generationApiKey: json['generationApiKey'] is String
          ? json['generationApiKey'] as String
          : '',
      generationTemperature: json['generationTemperature'] is num
          ? (json['generationTemperature'] as num).toDouble()
          : null,
      generationMaxTokens: _toInt(json['generationMaxTokens']),
      promptPreset: json['promptPreset'] is String &&
              (json['promptPreset'] as String).isNotEmpty
          ? json['promptPreset'] as String
          : 'detailed_beats',
      customPrompts: json['customPrompts'] is List
          ? (json['customPrompts'] as List)
              .whereType<Map<String, dynamic>>()
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'autoCreateEnabled': autoCreateEnabled,
        'autoGenerateEnabled': autoGenerateEnabled,
        'maxInjectedEntries': maxInjectedEntries,
        'autoCreateInterval': autoCreateInterval,
        'useDelayedAutomation': useDelayedAutomation,
        'injectionTarget': injectionTarget,
        'batchSize': batchSize,
        'parallelJobs': parallelJobs,
        'vectorSearchEnabled': vectorSearchEnabled,
        'keyMatchMode': keyMatchMode,
        'generationSource': generationSource,
        'generationModel': generationModel,
        'generationUseCurrentModelOverride': generationUseCurrentModelOverride,
        'generationEndpoint': generationEndpoint,
        'generationApiKey': generationApiKey,
        'generationTemperature': generationTemperature,
        'generationMaxTokens': generationMaxTokens,
        'promptPreset': promptPreset,
        'customPrompts': customPrompts,
      };

  static int? _toInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : null);

  MemoryGlobalSettings copyWith({
    bool? enabled,
    bool? autoCreateEnabled,
    bool? autoGenerateEnabled,
    int? maxInjectedEntries,
    int? autoCreateInterval,
    bool? useDelayedAutomation,
    String? injectionTarget,
    int? batchSize,
    int? parallelJobs,
    bool? vectorSearchEnabled,
    String? keyMatchMode,
    String? generationSource,
    String? generationModel,
    bool? generationUseCurrentModelOverride,
    String? generationEndpoint,
    String? generationApiKey,
    double? generationTemperature,
    int? generationMaxTokens,
    String? promptPreset,
    List<Map<String, dynamic>>? customPrompts,
  }) {
    return MemoryGlobalSettings(
      enabled: enabled ?? this.enabled,
      autoCreateEnabled: autoCreateEnabled ?? this.autoCreateEnabled,
      autoGenerateEnabled: autoGenerateEnabled ?? this.autoGenerateEnabled,
      maxInjectedEntries: maxInjectedEntries ?? this.maxInjectedEntries,
      autoCreateInterval: autoCreateInterval ?? this.autoCreateInterval,
      useDelayedAutomation: useDelayedAutomation ?? this.useDelayedAutomation,
      injectionTarget: injectionTarget ?? this.injectionTarget,
      batchSize: batchSize ?? this.batchSize,
      parallelJobs: parallelJobs ?? this.parallelJobs,
      vectorSearchEnabled: vectorSearchEnabled ?? this.vectorSearchEnabled,
      keyMatchMode: keyMatchMode ?? this.keyMatchMode,
      generationSource: generationSource ?? this.generationSource,
      generationModel: generationModel ?? this.generationModel,
      generationUseCurrentModelOverride: generationUseCurrentModelOverride ?? this.generationUseCurrentModelOverride,
      generationEndpoint: generationEndpoint ?? this.generationEndpoint,
      generationApiKey: generationApiKey ?? this.generationApiKey,
      generationTemperature: generationTemperature ?? this.generationTemperature,
      generationMaxTokens: generationMaxTokens ?? this.generationMaxTokens,
      promptPreset: promptPreset ?? this.promptPreset,
      customPrompts: customPrompts ?? this.customPrompts,
    );
  }
}

final memoryGlobalSettingsProvider =
    StateNotifierProvider<MemoryGlobalSettingsNotifier, MemoryGlobalSettings>(
  (ref) => MemoryGlobalSettingsNotifier(),
);

class MemoryGlobalSettingsNotifier extends StateNotifier<MemoryGlobalSettings> {
  MemoryGlobalSettingsNotifier() : super(const MemoryGlobalSettings());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('memorySettings');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        state = MemoryGlobalSettings.fromJson(json);
      } catch (_) {}
    }
  }

  Future<void> save(MemoryGlobalSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('memorySettings', jsonEncode(settings.toJson()));
  }
}
