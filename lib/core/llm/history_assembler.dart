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
      final macroResult = replaceMacros(msg.content, macroCtx);
      messages.add(PromptMessage(
        role: msg.role,
        content: macroResult.text,
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
  final int? depth;
  final bool isHistory;
  final bool isDepth;
  final bool isLorebook;
  final String? blockName;

  const PromptMessage({
    required this.role,
    required this.content,
    this.depth,
    this.isHistory = false,
    this.isDepth = false,
    this.isLorebook = false,
    this.blockName,
  });

  Map<String, String> toApiMap() => {'role': role, 'content': content};
}
