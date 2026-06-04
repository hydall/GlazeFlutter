import 'package:freezed_annotation/freezed_annotation.dart';

part 'memory_book.freezed.dart';
part 'memory_book.g.dart';

@freezed
class MemoryDraft with _$MemoryDraft {
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
class MessageRange with _$MessageRange {
  const factory MessageRange({
    required int start,
    required int end,
  }) = _MessageRange;

  factory MessageRange.fromJson(Map<String, dynamic> json) =>
      _$MessageRangeFromJson(json);
}

@freezed
class MemoryEntry with _$MemoryEntry {
  const factory MemoryEntry({
    required String id,
    @Default('') String title,
    @Default([]) List<String> keys,
    @Default('') String content,
    @Default('active') String status,
    @Default(false) bool vectorSearch,
    @Default([]) List<String> messageIds,
    int? createdAt,
  }) = _MemoryEntry;

  factory MemoryEntry.fromJson(Map<String, dynamic> json) =>
      _$MemoryEntryFromJson(json);
}

@freezed
class MemoryBookSettings with _$MemoryBookSettings {
  const factory MemoryBookSettings({
    @Default(true) bool enabled,
    @Default(true) bool autoCreateEnabled,
    @Default(false) bool autoGenerateEnabled,
    @Default(7) int maxInjectedEntries,
    @Default(0.35) double maxInjectionBudgetPercent,
    @Default(15) int autoCreateInterval,
    @Default(true) bool useDelayedAutomation,
    @Default('summary_block') String injectionTarget,
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
  }) = _MemoryBookSettings;

  factory MemoryBookSettings.fromJson(Map<String, dynamic> json) =>
      _$MemoryBookSettingsFromJson(json);
}

@freezed
class MemoryBook with _$MemoryBook {
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
