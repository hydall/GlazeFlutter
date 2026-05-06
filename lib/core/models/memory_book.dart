import 'package:freezed_annotation/freezed_annotation.dart';

part 'memory_book.freezed.dart';
part 'memory_book.g.dart';

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
    String? createdAt,
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
    @Default(15) int autoCreateInterval,
    @Default(true) bool useDelayedAutomation,
    @Default('summary_block') String injectionTarget,
    @Default(3) int batchSize,
    @Default(false) bool vectorSearchEnabled,
    @Default('plain') String keyMatchMode,
    @Default('') String generationModel,
    @Default('') String generationEndpoint,
    @Default('') String generationApiKey,
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
    @Default(MemoryBookSettings()) MemoryBookSettings settings,
    @Default(0) int lastProcessedMessageCount,
    @Default(0) int updatedAt,
  }) = _MemoryBook;

  factory MemoryBook.fromJson(Map<String, dynamic> json) =>
      _$MemoryBookFromJson(json);
}
