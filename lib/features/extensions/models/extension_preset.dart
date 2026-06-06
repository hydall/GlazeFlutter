import 'package:freezed_annotation/freezed_annotation.dart';

import 'block_config.dart';
import 'preset_permissions.dart';

part 'extension_preset.freezed.dart';
part 'extension_preset.g.dart';

@freezed
class ExtensionPreset with _$ExtensionPreset {
  const factory ExtensionPreset({
    required String id,
    required String name,
    required List<BlockConfig> blocks,
    @Default(0) int createdAt,
    @Default(PresetPermissions()) PresetPermissions permissions,
  }) = _ExtensionPreset;

  factory ExtensionPreset.fromJson(Map<String, dynamic> json) =>
      _$ExtensionPresetFromJson(json);
}
