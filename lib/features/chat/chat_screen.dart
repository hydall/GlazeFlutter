import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/chat_message.dart';
import '../../core/state/db_provider.dart';
import 'chat_provider.dart';

class ChatScreen extends ConsumerWidget {
  final String charId;
  const ChatScreen({super.key, required this.charId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider(charId));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: _buildTitle(ref),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.go('/character/$charId'),
          ),
          chatState.when(
            data: (state) => state.isGenerating
                ? IconButton(
                    icon: const Icon(Icons.stop_circle),
                    onPressed: () =>
                        ref.read(chatProvider(charId).notifier).abortGeneration(),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: chatState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) => Column(
          children: [
            Expanded(
              child: _MessageList(
                messages: state.messages,
                streamingText:
                    state.isGenerating ? state.streamingText : null,
                streamingReasoning:
                    state.isGenerating ? state.streamingReasoning : null,
              ),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  state.error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
            _InputBar(
              onSend: (text) {
                if (text.trim().isEmpty) return;
                ref.read(chatProvider(charId).notifier).sendMessage(text);
              },
              isGenerating: state.isGenerating,
              onStop: state.isGenerating
                  ? () => ref
                      .read(chatProvider(charId).notifier)
                      .abortGeneration()
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(WidgetRef ref) {
    final charAsync = ref.watch(characterRepoProvider);
    return FutureBuilder<String>(
      future: charAsync.getById(charId).then((c) => c?.name ?? 'Chat'),
      builder: (_, snap) => Text(snap.data ?? 'Chat'),
    );
  }
}

class _MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final String? streamingText;
  final String? streamingReasoning;

  const _MessageList({
    required this.messages,
    this.streamingText,
    this.streamingReasoning,
  });

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
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

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.messages.length + (showStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < widget.messages.length) {
          final msg = widget.messages[index];
          return _MessageBubble(
            content: msg.content,
            isUser: msg.role == 'user',
            isSystem: msg.role == 'system',
            reasoning: msg.reasoning,
          );
        }
        return _MessageBubble(
          content: widget.streamingText!,
          isUser: false,
          isStreaming: true,
          reasoning: widget.streamingReasoning,
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isSystem;
  final bool isStreaming;
  final String? reasoning;

  const _MessageBubble({
    required this.content,
    required this.isUser,
    this.isSystem = false,
    this.isStreaming = false,
    this.reasoning,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Color bg;
    Alignment alignment;
    if (isUser) {
      bg = scheme.primary;
      alignment = Alignment.centerRight;
    } else if (isSystem) {
      bg = scheme.surfaceContainerLow;
      alignment = Alignment.center;
    } else {
      bg = scheme.surfaceContainerHighest;
      alignment = Alignment.centerLeft;
    }

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reasoning != null && reasoning!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.psychology,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('Reasoning',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reasoning!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            MarkdownBody(
              data: content,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: isUser ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
            if (isStreaming)
              Text('...',
                  style: TextStyle(
                    color: isUser ? scheme.onPrimary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  )),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  final ValueChanged<String> onSend;
  final bool isGenerating;
  final VoidCallback? onStop;

  const _InputBar({
    required this.onSend,
    required this.isGenerating,
    this.onStop,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: widget.isGenerating ? widget.onStop : _handleSend,
              icon: Icon(widget.isGenerating ? Icons.stop : Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
