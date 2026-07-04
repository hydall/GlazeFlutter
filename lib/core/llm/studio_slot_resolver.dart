import 'package:flutter/foundation.dart';

import '../models/api_config.dart';
import 'aux_llm_client.dart';

/// Resolves a Studio API-config slot to an [AuxApiConfig] for auxiliary LLM
/// calls (cleaner, fact-checker, ledger, write-loop).
///
/// **Fail-explicit:** throws when [apiConfigId] is empty or not found in the
/// API config list. No silent fallback to the active chat config — Studio
/// slots must be configured deliberately.
///
/// Usage:
/// ```dart
/// await ref.read(apiListProvider.future);
/// final apiConfigs = ref.read(apiListProvider).value ?? const <ApiConfig>[];
/// final config = StudioSlotResolver.resolve(
///   apiConfigs: apiConfigs,
///   apiConfigId: studioConfig.cleanerApiConfigId,
///   errorLabel: 'post-cleaner',
///   modelOverride: pipeline.cleaner.postCleanerModel,
/// );
/// ```
class StudioSlotResolver {
  StudioSlotResolver._();

  /// Resolves [apiConfigId] to an [AuxApiConfig]. Throws if the id is empty
  /// or not found.
  ///
  /// [modelOverride] — when non-empty, replaces the config's model. Used for
  /// per-service model overrides (e.g. `postCleanerModel`,
  /// `studioLedgerModel`).
  static AuxApiConfig resolve({
    required List<ApiConfig> apiConfigs,
    required String apiConfigId,
    String errorLabel = 'studio-slot',
    String modelOverride = '',
  }) {
    if (apiConfigId.isEmpty) {
      debugPrint(
        '[StudioSlotResolver] $errorLabel: apiConfigId is empty — '
        'configure the Studio cleaner slot',
      );
      throw Exception(
        'Studio slot "$errorLabel" not configured: apiConfigId is empty',
      );
    }
    final selected =
        apiConfigs.where((c) => c.id == apiConfigId).firstOrNull;
    if (selected == null) {
      debugPrint(
        '[StudioSlotResolver] $errorLabel: apiConfigId "$apiConfigId" '
        'not found in API config list',
      );
      throw Exception(
        'Studio slot "$errorLabel" not found: apiConfigId "$apiConfigId" '
        'does not match any saved API config',
      );
    }
    final model =
        modelOverride.isNotEmpty ? modelOverride : selected.model;
    debugPrint(
      '[StudioSlotResolver] resolved $errorLabel '
      'model=$model endpoint=${selected.endpoint}',
    );
    return AuxApiConfig(
      endpoint: selected.endpoint,
      apiKey: selected.apiKey,
      model: model,
      protocol: selected.protocol,
    );
  }
}
