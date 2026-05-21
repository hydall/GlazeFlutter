import 'package:freezed_annotation/freezed_annotation.dart';

import 'gallery_entry.dart';

part 'character.freezed.dart';
part 'character.g.dart';

@freezed
class Character with _$Character {
  const factory Character({
    required String id,
    required String name,
    String? avatarPath,
    String? description,
    String? personality,
    String? scenario,
    String? firstMes,
    String? mesExample,
    String? systemPrompt,
    String? postHistoryInstructions,
    String? creator,
    String? creatorNotes,
    @Default([]) List<String> tags,
    @Default([]) List<String> alternateGreetings,
    String? color,
    @Default(0) int updatedAt,
    @Default(0) int createdAt,
    @Default([]) List<GalleryEntry> gallery,
    @Default(0) int currentSessionIndex,
    @Default(false) bool fav,
    @Default({}) Map<String, dynamic> extensions,
    @Default('1') String characterVersion,
    @Default('') String depthPrompt,
    @Default(4) int depthPromptDepth,
    @Default('system') String depthPromptRole,
    String? world,
    String? macroName,
    String? picksHash,
  }) = _Character;

  factory Character.fromJson(Map<String, dynamic> json) =>
      _$CharacterFromJson(json);
}
