import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/prompt_builder.dart';
import '../../core/llm/prompt_isolate.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/active_selection_provider.dart';
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
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'preset':
                  _showPresetPicker(context, ref);
                case 'persona':
                  _showPersonaPicker(context, ref);
                case 'raw':
                  _showRawPrompt(context, ref);
                case 'clear':
                  _confirmClearChat(context, ref);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'preset',
                child: Row(children: [
                  Icon(Icons.tune, size: 18),
                  SizedBox(width: 8),
                  Text('Preset'),
                ]),
              ),
              const PopupMenuItem(
                value: 'persona',
                child: Row(children: [
                  Icon(Icons.person, size: 18),
                  SizedBox(width: 8),
                  Text('Persona'),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'raw',
                child: Row(children: [
                  Icon(Icons.data_object, size: 18),
                  SizedBox(width: 8),
                  Text('View Raw Prompt'),
                ]),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(children: [
                  Icon(Icons.delete_sweep, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Clear Chat', style: TextStyle(color: Colors.red)),
                ]),
              ),
            ],
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
                isGenerating: state.isGenerating,
                charId: charId,
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

  void _showRawPrompt(BuildContext context, WidgetRef ref) async {
    final chatState = ref.read(chatProvider(charId)).value;
    if (chatState == null || chatState.session == null) return;

    final charRepo = ref.read(characterRepoProvider);
    final presetRepo = ref.read(presetRepoProvider);
    final personaRepo = ref.read(personaRepoProvider);
    final apiConfigRepo = ref.read(apiConfigRepoProvider);

    final character = await charRepo.getById(charId);
    if (character == null) return;

    final apiConfigs = await apiConfigRepo.getAll();
    if (apiConfigs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No API config')),
        );
      }
      return;
    }
    final apiConfig = apiConfigs.first;

    final activePresetId = ref.read(activePresetIdProvider);
    final activePersonaId = ref.read(activePersonaIdProvider);

    final presets = await presetRepo.getAll();
    final preset = activePresetId != null
        ? presets.where((p) => p.id == activePresetId).firstOrNull
        : (presets.isNotEmpty ? presets.first : null);

    final personas = await personaRepo.getAll();
    final persona = activePersonaId != null
        ? personas.where((p) => p.id == activePersonaId).firstOrNull
        : (personas.isNotEmpty ? personas.first : null);

    final payload = PromptPayload(
      character: character,
      persona: persona,
      preset: preset,
      history: chatState.session!.messages,
      apiConfig: apiConfig,
      sessionVars: chatState.session!.sessionVars,
      globalVars: ref.read(globalVarsProvider),
    );

    final result = await buildPromptInIsolate(payload);

    final rawJson = const JsonEncoder.withIndent('  ').convert({
      'model': apiConfig.model,
      'messages': result.messages.map((m) => m.toApiMap()).toList(),
      'max_tokens': apiConfig.maxTokens,
      'temperature': apiConfig.temperature,
      'top_p': apiConfig.topP,
      'stream': apiConfig.stream,
    });

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('Raw Prompt'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: rawJson));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.7,
          child: SelectableText(
            rawJson,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPresetPicker(BuildContext context, WidgetRef ref) async {
    final presets = await ref.read(presetRepoProvider).getAll();
    final activeId = ref.read(activePresetIdProvider);
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Preset'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setActivePreset(ref, null);
              Navigator.pop(ctx);
            },
            child: Row(children: [
              if (activeId == null) const Icon(Icons.check, size: 16),
              const SizedBox(width: 8),
              const Text('Default (first)'),
            ]),
          ),
          ...presets.map((p) => SimpleDialogOption(
                onPressed: () {
                  setActivePreset(ref, p.id);
                  Navigator.pop(ctx);
                },
                child: Row(children: [
                  if (activeId == p.id) const Icon(Icons.check, size: 16),
                  const SizedBox(width: 8),
                  Text(p.name),
                ]),
              )),
        ],
      ),
    );
  }

  void _showPersonaPicker(BuildContext context, WidgetRef ref) async {
    final personas = await ref.read(personaRepoProvider).getAll();
    final activeId = ref.read(activePersonaIdProvider);
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Persona'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setActivePersona(ref, null);
              Navigator.pop(ctx);
            },
            child: Row(children: [
              if (activeId == null) const Icon(Icons.check, size: 16),
              const SizedBox(width: 8),
              const Text('Default (first)'),
            ]),
          ),
          ...personas.map((p) => SimpleDialogOption(
                onPressed: () {
                  setActivePersona(ref, p.id);
                  Navigator.pop(ctx);
                },
                child: Row(children: [
                  if (activeId == p.id) const Icon(Icons.check, size: 16),
                  const SizedBox(width: 8),
                  Text(p.name),
                ]),
              )),
        ],
      ),
    );
  }

  void _confirmClearChat(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Delete all messages? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(chatProvider(charId).notifier).clearChat();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final String? streamingText;
  final String? streamingReasoning;
  final bool isGenerating;
  final String charId;

  const _MessageList({
    required this.messages,
    this.streamingText,
    this.streamingReasoning,
    required this.isGenerating,
    required this.charId,
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
            messageIndex: index,
            isLast: index == widget.messages.length - 1,
            isGenerating: widget.isGenerating,
            charId: widget.charId,
          );
        }
        return _MessageBubble(
          content: widget.streamingText!,
          isUser: false,
          isStreaming: true,
          reasoning: widget.streamingReasoning,
          messageIndex: -1,
          isLast: false,
          isGenerating: true,
          charId: widget.charId,
        );
      },
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  final String content;
  final bool isUser;
  final bool isSystem;
  final bool isStreaming;
  final String? reasoning;
  final int messageIndex;
  final bool isLast;
  final bool isGenerating;
  final String charId;

  const _MessageBubble({
    required this.content,
    required this.isUser,
    this.isSystem = false,
    this.isStreaming = false,
    this.reasoning,
    required this.messageIndex,
    required this.isLast,
    required this.isGenerating,
    required this.charId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    Widget bubble = Align(
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
            if (!isSystem && !isStreaming) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionChip(
                    icon: Icons.copy,
                    tooltip: 'Copy',
                    color: isUser ? scheme.onPrimary : null,
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: content)),
                  ),
                  _ActionChip(
                    icon: Icons.edit,
                    tooltip: 'Edit',
                    color: isUser ? scheme.onPrimary : null,
                    onTap: () => _showEditDialog(context, ref),
                  ),
                  if (isLast && !isGenerating)
                    _ActionChip(
                      icon: Icons.refresh,
                      tooltip: 'Regenerate',
                      color: isUser ? scheme.onPrimary : null,
                      onTap: () => ref
                          .read(chatProvider(charId).notifier)
                          .regenerateLastAssistant(),
                    ),
                  if (isLast && !isGenerating)
                    _ActionChip(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete',
                      color: isUser ? scheme.onPrimary : Colors.red,
                      onTap: () =>
                          ref.read(chatProvider(charId).notifier).deleteMessage(messageIndex),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (isSystem || isStreaming) return bubble;

    return GestureDetector(
      onLongPress: () => _showContextMenu(context, ref),
      child: bubble,
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(chatProvider(charId).notifier);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: content));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditDialog(context, ref);
              },
            ),
            if (!isUser && isLast && !isGenerating)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Regenerate'),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.regenerateLastAssistant();
                },
              ),
            if (isLast && !isGenerating)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.deleteMessage(messageIndex);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          minLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty) {
                ref
                    .read(chatProvider(charId).notifier)
                    .editMessage(messageIndex, newText);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _ActionChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(icon, size: 16, color: c),
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
