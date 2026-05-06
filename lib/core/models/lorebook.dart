import 'package:freezed_annotation/freezed_annotation.dart';

part 'lorebook.freezed.dart';
part 'lorebook.g.dart';

@freezed
class LorebookEntry with _$LorebookEntry {
  const factory LorebookEntry({
    required String id,
    @Default('') String comment,
    @Default(true) bool enabled,
    @Default(false) bool constant,
    @Default([]) List<String> keys,
    @Default([]) List<String> secondaryKeys,
    @Default(5) int selectiveLogic,
    @Default('') String content,
    @Default('worldInfoBefore') String position,
    @Default(100) int order,
    int? scanDepth,
    bool? caseSensitive,
    bool? matchWholeWords,
    @Default(100) int probability,
    @Default(false) bool preventRecursion,
    @Default(0) int sticky,
    @Default(0) int cooldown,
    @Default(0) int delay,
    @Default('') String group,
    @Default(0) int groupProminence,
    LorebookCharacterFilter? characterFilter,
    @Default(false) bool ignoreBudget,
    @Default(false) bool vectorSearch,
    @Default(true) bool useKeywordSearch,
  }) = _LorebookEntry;

  factory LorebookEntry.fromJson(Map<String, dynamic> json) =>
      _$LorebookEntryFromJson(json);
}

@freezed
class LorebookCharacterFilter with _$LorebookCharacterFilter {
  const factory LorebookCharacterFilter({
    @Default([]) List<String> names,
    @Default(false) bool isExclude,
  }) = _LorebookCharacterFilter;

  factory LorebookCharacterFilter.fromJson(Map<String, dynamic> json) =>
      _$LorebookCharacterFilterFromJson(json);
}

@freezed
class Lorebook with _$Lorebook {
  const factory Lorebook({
    required String id,
    required String name,
    @Default(true) bool enabled,
    @Default('global') String activationScope,
    String? activationTargetId,
    @Default([]) List<LorebookEntry> entries,
    @Default(0) int updatedAt,
  }) = _Lorebook;

  factory Lorebook.fromJson(Map<String, dynamic> json) =>
      _$LorebookFromJson(json);
}

@freezed
class LorebookGlobalSettings with _$LorebookGlobalSettings {
  const factory LorebookGlobalSettings({
    @Default('keyword') String searchType,
    @Default('tavern') String keySearchMode,
    @Default(false) bool caseSensitive,
    @Default(false) bool matchWholeWords,
    @Default(true) bool recursiveScan,
    @Default(10) int scanDepth,
    @Default(5) int maxInjectedEntries,
    @Default('worldInfoBefore') String injectionPosition,
    @Default('tokens') String reserveMode,
    @Default(0) int reserveValue,
    @Default(50) int keywordVectorSplit,
    @Default(0.45) double vectorThreshold,
    @Default(10) int vectorTopK,
  }) = _LorebookGlobalSettings;

  factory LorebookGlobalSettings.fromJson(Map<String, dynamic> json) =>
      _$LorebookGlobalSettingsFromJson(json);
}

@freezed
class LorebookActivations with _$LorebookActivations {
  const factory LorebookActivations({
    @Default({}) Map<String, List<String>> character,
    @Default({}) Map<String, List<String>> chat,
  }) = _LorebookActivations;

  factory LorebookActivations.fromJson(Map<String, dynamic> json) =>
      _$LorebookActivationsFromJson(json);
}
