import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import 'macro_engine.dart';

class HistoryAssembler {
  final MacroContext macroCtx;

  HistoryAssembler(this.macroCtx);

  List<PromptMessage> assemble(List<ChatMessage> history) {
    if (history.isEmpty) return [];

    final messages = <PromptMessage>[];

    for (int i = 0; i < history.length; i++) {
      final msg = history[i];
      if (msg.isHidden || msg.isTyping) continue;
      final macroResult = replaceMacros(msg.content, macroCtx);
      final normalized = _normalizeUnderscoreEmphasis(macroResult.text);
      messages.add(PromptMessage(
        role: msg.role,
        content: normalized,
        isHistory: true,
      ));
    }

    return messages;
  }
}

List<PromptMessage> interleaveDepthWithHistory(
  List<PromptMessage> historyMsgs,
  List<PromptMessage> depthBlocks,
) {
  if (depthBlocks.isEmpty) return historyMsgs;

  final result = <PromptMessage>[];

  final deepBlocks = depthBlocks.where((b) => (b.depth ?? 0) > historyMsgs.length);
  debugPrint('INTERLEAVE: historyCount=${historyMsgs.length}, depthBlocksCount=${depthBlocks.length}, deepBlocksCount=${deepBlocks.length}');
  result.addAll(deepBlocks);

  for (int i = 0; i <= historyMsgs.length; i++) {
    final currentDepth = historyMsgs.length - i;
    final blocksAtDepth = depthBlocks.where((b) => (b.depth ?? 0) == currentDepth);
    debugPrint('INTERLEAVE: i=$i, currentDepth=$currentDepth, blocksAtDepth=${blocksAtDepth.length}');
    result.addAll(blocksAtDepth);

    if (i < historyMsgs.length) {
      result.add(historyMsgs[i]);
    }
  }

  debugPrint('INTERLEAVE: result count=${result.length} (history=${result.where((m) => m.isHistory).length}, depth=${result.where((m) => m.isDepth).length})');
  return result;
}

class PromptMessage {
  final String role;
  final String content;
  final String? blockId;
  final int? depth;
  final bool isHistory;
  final bool isDepth;
  final bool isLorebook;
  final bool isSummary;
  final String? blockName;

  const PromptMessage({
    required this.role,
    required this.content,
    this.blockId,
    this.depth,
    this.isHistory = false,
    this.isDepth = false,
    this.isLorebook = false,
    this.isSummary = false,
    this.blockName,
  });

  Map<String, String> toApiMap() => {'role': role, 'content': content};

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'blockId': blockId,
    'depth': depth,
    'isHistory': isHistory,
    'isDepth': isDepth,
    'isLorebook': isLorebook,
    'isSummary': isSummary,
    'blockName': blockName,
  };

  factory PromptMessage.fromJson(Map<String, dynamic> json) => PromptMessage(
    role: json['role'] as String,
    content: json['content'] as String,
    blockId: json['blockId'] as String?,
    depth: json['depth'] as int?,
    isHistory: json['isHistory'] as bool? ?? false,
    isDepth: json['isDepth'] as bool? ?? false,
    isLorebook: json['isLorebook'] as bool? ?? false,
    isSummary: json['isSummary'] as bool? ?? false,
    blockName: json['blockName'] as String?,
  );
}

String _normalizeUnderscoreEmphasis(String text) {
  var result = text;
  result = result.replaceAllMapped(
    RegExp(r'(?<!\w)__(?!\s)(.+?)(?<!\s)__(?!\w)'),
    (m) => '**${m[1]}**',
  );
  result = result.replaceAllMapped(
    RegExp(r'(?<!\w|_)_(?!\s)(.+?)(?<!\s)_(?!\w|_)'),
    (m) => '*${m[1]}*',
  );
  return result;
}
