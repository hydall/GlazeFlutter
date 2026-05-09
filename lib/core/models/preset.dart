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
      _$PresetBlockFromJson(_normalizeBlock(json));
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

  factory PresetRegex.fromJson(Map<String, dynamic> json) =>
      _$PresetRegexFromJson(_normalizeRegex(json));
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

  factory Preset.fromJson(Map<String, dynamic> json) =>
      _$PresetFromJson(_normalizePreset(json));
}

Map<String, dynamic> _normalizeBlock(Map<String, dynamic> json) {
  final n = Map<String, dynamic>.from(json);
  n['enabled'] = _coerceBool(n['enabled'], true);
  n['isStatic'] = _coerceBool(n['isStatic'], false);
  n['isStashed'] = _coerceBool(n['isStashed'], false);
  n['depth'] = _coerceInt(n['depth']);
  return n;
}

Map<String, dynamic> _normalizeRegex(Map<String, dynamic> json) {
  final n = Map<String, dynamic>.from(json);
  n['disabled'] = _coerceBool(n['disabled'], false);
  n['minDepth'] = _coerceInt(n['minDepth']);
  n['maxDepth'] = _coerceInt(n['maxDepth']);
  n['macroRules'] = _coerceString(n['macroRules'], '0');
  return n;
}

Map<String, dynamic> _normalizePreset(Map<String, dynamic> json) {
  final n = Map<String, dynamic>.from(json);
  n['reasoningEnabled'] = _coerceBool(n['reasoningEnabled'], false);
  n['mergePrompts'] = _coerceBool(n['mergePrompts'], false);
  n['createdAt'] = _coerceInt(n['createdAt']) ?? 0;
  return n;
}

int? _coerceInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool _coerceBool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  return fallback;
}

String _coerceString(dynamic v, String fallback) {
  if (v is String) return v;
  return fallback;
}
