import 'package:freezed_annotation/freezed_annotation.dart';

part 'memory_book.freezed.dart';
part 'memory_book.g.dart';

@freezed
abstract class MemoryDraft with _$MemoryDraft {
  const factory MemoryDraft({
    required String id,
    @Default('') String title,
    @Default('') String content,
    @Default([]) List<String> keys,
    @Default([]) List<String> glazeKeys,
    @Default(false) bool vectorSearch,
    @Default([]) List<String> messageIds,
    MessageRange? messageRange,
    @Default('pending_generation') String status,
    @Default('') String source,
    @Default(0) int createdAt,
    @Default(0) int updatedAt,
    int? generatedAt,
    String? error,
  }) = _MemoryDraft;

  factory MemoryDraft.fromJson(Map<String, dynamic> json) =>
      _$MemoryDraftFromJson(json);
}

@freezed
abstract class MessageRange with _$MessageRange {
  const factory MessageRange({required int start, required int end}) =
      _MessageRange;

  factory MessageRange.fromJson(Map<String, dynamic> json) =>
      _$MessageRangeFromJson(json);
}

@freezed
abstract class MemoryEntry with _$MemoryEntry {
  const factory MemoryEntry({
    required String id,
    @Default('') String title,
    @Default([]) List<String> keys,
    @Default('') String content,
    @Default('active') String status,
    @Default(false) bool vectorSearch,
    @Default([]) List<String> messageIds,
    int? createdAt,
    MessageRange? messageRange,
    @Default(0) double importance,
    @Default(false) bool temporallyBlind,
    @Default('') String arc,
    @Default('curated') String kind,
    @Default('') String sourceHash,
  }) = _MemoryEntry;

  factory MemoryEntry.fromJson(Map<String, dynamic> json) =>
      _$MemoryEntryFromJson(_migrateEntryInPlace(json));
}

@freezed
abstract class MemoryBookSettings with _$MemoryBookSettings {
  const factory MemoryBookSettings({
    @Default(true) bool enabled,
    @Default('fast') String memoryMode,
    @Default(true) bool autoCreateEnabled,
    @Default(false) bool autoGenerateEnabled,
    @Default(7) int maxInjectedEntries,
    @Default(0.35) double maxInjectionBudgetPercent,
    int? maxInjectedTokens,
    @Default('auto') String memoryBudgetPreset,
    @Default(15) int autoCreateInterval,
    @Default(true) bool useDelayedAutomation,
    @Default('hard_block') String injectionTarget,
    @Default(3) int batchSize,
    @Default(false) bool vectorSearchEnabled,
    @Default('glaze') String keyMatchMode,
    @Default('current') String generationSource,
    @Default('') String generationModel,
    @Default('') String generationEndpoint,
    @Default('') String generationApiKey,
    @Default(null) double? generationTemperature,
    @Default(null) int? generationMaxTokens,
    @Default('detailed_beats') String promptPreset,
    @Default(true) bool diversityAware,
    @Default(0.15) double diversityPenalty,
    @Default(true) bool recencyBoost,
    @Default(100) double recencyHalfLifeDays,
    @Default(true) bool importanceBoost,
    @Default(0.5) double importanceWeight,
    @Default(true) bool sourceWindowExclusion,
    @Default(false) bool factualContinuityGuardEnabled,
    @Default(false) bool classifierEnabled,
    @Default('current') String classifierSource,
    @Default('') String classifierModel,
    @Default('') String classifierEndpoint,
    @Default('') String classifierApiKey,
    @Default(2500) int classifierTimeoutMs,
    @Default(false) bool sidecarEnabled,
    @Default('current') String sidecarSource,
    @Default('') String sidecarModel,
    @Default('') String sidecarEndpoint,
    @Default('') String sidecarApiKey,
    @Default(4000) int sidecarTimeoutMs,
    @Default(true) bool queryIncludeAssistant,
    @Default(6) int queryRecentTurns,
    @Default(1500) int queryMaxChars,
  }) = _MemoryBookSettings;

  factory MemoryBookSettings.fromJson(Map<String, dynamic> json) =>
      _$MemoryBookSettingsFromJson(_migrateInjectionTargetInPlace(json));
}

/// Translates the legacy `summary_block` / `summary_macro` enum values
/// (pre-{{memory}}-split) to `hard_block` / `macro` in-place. The old
/// values were misleadingly named because the "summary" prefix was
/// about *where* memory goes, not about the summary feature itself.
Map<String, dynamic> _migrateInjectionTargetInPlace(Map<String, dynamic> json) {
  final raw = json['injectionTarget'];
  if (raw == 'summary_block') {
    return {...json, 'injectionTarget': 'hard_block'};
  }
  if (raw == 'summary_macro') {
    return {...json, 'injectionTarget': 'macro'};
  }
  return json;
}

/// Coerces new optional fields into safe defaults when reading older JSON
/// payloads written before the v2 selector schema.
Map<String, dynamic> _migrateEntryInPlace(Map<String, dynamic> json) {
  var out = json;
  if (out['messageRange'] != null && out['messageRange'] is! Map) {
    out = {...out, 'messageRange': null};
  }
  if (out['importance'] is! num) {
    out = {...out, 'importance': 0.0};
  }
  if (out['temporallyBlind'] is! bool) {
    out = {...out, 'temporallyBlind': false};
  }
  if (out['arc'] is! String) {
    out = {...out, 'arc': ''};
  }
  if (out['kind'] is! String) {
    out = {...out, 'kind': 'curated'};
  }
  if (out['sourceHash'] is! String) {
    out = {...out, 'sourceHash': ''};
  }
  return out;
}

@freezed
abstract class MemoryBook with _$MemoryBook {
  const factory MemoryBook({
    required String id,
    required String sessionId,
    @Default([]) List<MemoryEntry> entries,
    @Default([]) List<MemoryDraft> pendingDrafts,
    @Default(MemoryBookSettings()) MemoryBookSettings settings,
    @Default(0) int lastProcessedMessageCount,
    @Default(0) int updatedAt,
  }) = _MemoryBook;

  factory MemoryBook.fromJson(Map<String, dynamic> json) =>
      _$MemoryBookFromJson(json);
}
