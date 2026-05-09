import 'package:freezed_annotation/freezed_annotation.dart';

part 'preset.freezed.dart';
part 'preset.g.dart';

@freezed
class PresetBlock with _$PresetBlock {
  const factory PresetBlock({
    required String id,
    required String name,
    required String role,
    required String content,
    @Default(true) bool enabled,
    @Default(false) bool isStatic,
    @Default('relative') String insertionMode,
    int? depth,
    String? prefix,
    @Default(false) bool isStashed,
  }) = _PresetBlock;

  factory PresetBlock.fromJson(Map<String, dynamic> json) =>
      _$PresetBlockFromJson(json);
}

@freezed
class PresetRegex with _$PresetRegex {
  const factory PresetRegex({
    required String id,
    required String name,
    required String regex,
    @Default('') String replacement,
    @Default('') String trimOut,
    @Default([1, 2]) List<int> placement,
    @Default([1, 2]) List<int> ephemerality,
    @Default(false) bool disabled,
    @Default('0') String macroRules,
    int? minDepth,
    int? maxDepth,
  }) = _PresetRegex;

  factory PresetRegex.fromJson(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);
    for (final key in ['minDepth', 'maxDepth']) {
      final v = normalized[key];
      if (v is bool) {
        normalized[key] = null;
      } else if (v is num) {
        normalized[key] = v.toInt();
      }
    }
    normalized['disabled'] = _coerceBool(normalized['disabled']);
    return _$PresetRegexFromJson(normalized);
  }
}

@freezed
class Preset with _$Preset {
  const factory Preset({
    required String id,
    required String name,
    String? author,
    @Default([]) List<PresetBlock> blocks,
    @Default([]) List<PresetRegex> regexes,
    @Default(false) bool reasoningEnabled,
    String? reasoningStart,
    String? reasoningEnd,
    String? guidedGenerationPrompt,
    String? guidedImpersonationPrompt,
    String? summaryPrompt,
    @Default(false) bool mergePrompts,
    @Default('system') String mergeRole,
    @Default(0) int createdAt,
  }) = _Preset;

  factory Preset.fromJson(Map<String, dynamic> json) => _$PresetFromJson(json);
}

bool _coerceBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  return false;
}
