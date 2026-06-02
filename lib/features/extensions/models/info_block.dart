import 'package:freezed_annotation/freezed_annotation.dart';

part 'info_block.freezed.dart';
part 'info_block.g.dart';

@freezed
class InfoBlock with _$InfoBlock {
  const factory InfoBlock({
    required String id,
    required String sessionId,
    required String messageId,
    required String blockId,
    required String blockName,
    required String blockType,
    required String content,
    required int createdAt,
  }) = _InfoBlock;

  factory InfoBlock.fromJson(Map<String, dynamic> json) =>
      _$InfoBlockFromJson(json);
}
