import 'package:flutter/material.dart';
import '../../../core/models/chat_message.dart';
import 'message_bubble.dart';

class MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final String? streamingText;
  final String? streamingReasoning;
  final bool isGenerating;
  final String charId;

  const MessageList({
    super.key,
    required this.messages,
    this.streamingText,
    this.streamingReasoning,
    required this.isGenerating,
    required this.charId,
  });

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final showStreaming =
        widget.streamingText != null && widget.streamingText!.isNotEmpty;
    final showTyping =
        widget.isGenerating &&
        !showStreaming &&
        (widget.messages.isEmpty || widget.messages.last.role == 'user');

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 80, bottom: 180),
      itemCount: widget.messages.length + (showStreaming || showTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < widget.messages.length) {
          final msg = widget.messages[index];
          return MessageBubble(
            content: msg.content,
            isUser: msg.role == 'user',
            isSystem: msg.role == 'system',
            reasoning: msg.reasoning,
            genTime: msg.genTime,
            tokens: msg.tokens,
            isHidden: msg.isHidden,
            isError: msg.isError,
            messageIndex: index,
            isLast: index == widget.messages.length - 1,
            isGenerating: widget.isGenerating,
            charId: widget.charId,
          );
        }

        if (showStreaming) {
          return MessageBubble(
            content: widget.streamingText!,
            isUser: false,
            isStreaming: true,
            reasoning: widget.streamingReasoning,
            messageIndex: -1,
            isLast: false,
            isGenerating: true,
            charId: widget.charId,
          );
        }

        return MessageBubble(
          content: '',
          isUser: false,
          isTyping: true,
          messageIndex: -1,
          isLast: false,
          isGenerating: true,
          charId: widget.charId,
        );
      },
    );
  }
}
