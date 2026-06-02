import 'package:freezed_annotation/freezed_annotation.dart';

import 'block_config.dart';

part 'extension_preset.freezed.dart';
part 'extension_preset.g.dart';

@freezed
class ExtensionPreset with _$ExtensionPreset {
  const factory ExtensionPreset({
    required String id,
    required String name,
    required List<BlockConfig> blocks,
    @Default(0) int createdAt,
  }) = _ExtensionPreset;

  factory ExtensionPreset.fromJson(Map<String, dynamic> json) =>
      _$ExtensionPresetFromJson(json);
}
