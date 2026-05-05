import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/prompt_builder.dart';
import '../../core/llm/prompt_isolate.dart';
import '../../core/models/character.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../settings/app_settings_provider.dart';
import 'chat_provider.dart';

class ChatScreen extends ConsumerWidget {
  final String charId;
  const ChatScreen({super.key, required this.charId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatStateAsync = ref.watch(chatProvider(charId));
    final chatState = chatStateAsync.value;

    final chars = ref.watch(charactersProvider).value ?? [];
    final character = chars.where((c) => c.id == charId).firstOrNull;
    final title = character?.name ?? 'Chat';
    final sessionName = chatState?.session != null
        ? 'Session #${chatState!.session!.sessionIndex}'
        : 'Loading...';

    return GlazeScaffold(
      extendBodyBehindHeader: true,
      title: title,
      titleWidget: character != null
          ? _ChatHeaderTitle(character: character, sessionName: sessionName)
          : null,
      onBack: () => context.go('/'),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: () => context.go('/character/$charId'),
          color: AppColors.accent,
        ),
        chatStateAsync.when(
          data: (state) => state.isGenerating
              ? IconButton(
                  icon: const Icon(Icons.stop_circle),
                  color: AppColors.accent,
                  onPressed: () =>
                      ref.read(chatProvider(charId).notifier).abortGeneration(),
                )
              : const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        Theme(
          data: Theme.of(
            context,
          ).copyWith(iconTheme: const IconThemeData(color: AppColors.accent)),
          child: PopupMenuButton<String>(
            iconColor: AppColors.accent,
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
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 18),
                    SizedBox(width: 8),
                    Text('Preset'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'persona',
                child: Row(
                  children: [
                    Icon(Icons.person, size: 18),
                    SizedBox(width: 8),
                    Text('Persona'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'raw',
                child: Row(
                  children: [
                    Icon(Icons.data_object, size: 18),
                    SizedBox(width: 8),
                    Text('View Raw Prompt'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear Chat', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      body: chatStateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) => Stack(
          children: [
            _MessageList(
              messages: state.messages,
              streamingText: state.isGenerating ? state.streamingText : null,
              streamingReasoning: state.isGenerating
                  ? state.streamingReasoning
                  : null,
              isGenerating: state.isGenerating,
              charId: charId,
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Text(
                        state.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
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
          ],
        ),
      ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No API config')));
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
            child: Row(
              children: [
                if (activeId == null) const Icon(Icons.check, size: 16),
                const SizedBox(width: 8),
                const Text('Default (first)'),
              ],
            ),
          ),
          ...presets.map(
            (p) => SimpleDialogOption(
              onPressed: () {
                setActivePreset(ref, p.id);
                Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  if (activeId == p.id) const Icon(Icons.check, size: 16),
                  const SizedBox(width: 8),
                  Text(p.name),
                ],
              ),
            ),
          ),
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
            child: Row(
              children: [
                if (activeId == null) const Icon(Icons.check, size: 16),
                const SizedBox(width: 8),
                const Text('Default (first)'),
              ],
            ),
          ),
          ...personas.map(
            (p) => SimpleDialogOption(
              onPressed: () {
                setActivePersona(ref, p.id);
                Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  if (activeId == p.id) const Icon(Icons.check, size: 16),
                  const SizedBox(width: 8),
                  Text(p.name),
                ],
              ),
            ),
          ),
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
            child: const Text('Cancel'),
          ),
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
      padding: const EdgeInsets.only(top: 80, bottom: 180),
      itemCount: widget.messages.length + (showStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < widget.messages.length) {
          final msg = widget.messages[index];
          return _MessageBubble(
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
  final String? genTime;
  final int? tokens;
  final bool isHidden;
  final bool isError;
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
    this.genTime,
    this.tokens,
    this.isHidden = false,
    this.isError = false,
    required this.messageIndex,
    required this.isLast,
    required this.isGenerating,
    required this.charId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final appSettings = ref.watch(appSettingsProvider).value;
    final layoutMode = appSettings?.chatLayout ?? 'default';
    final isStandard = layoutMode == 'default';

    final chars = ref.watch(charactersProvider).value ?? [];
    final character = chars.where((c) => c.id == charId).firstOrNull;

    Color bg;
    Alignment alignment;
    if (isStandard) {
      bg = Colors.transparent;
      alignment = Alignment.centerLeft;
    } else {
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
    }

    String displayName = isUser ? 'User' : (character?.name ?? 'Character');
    String avatarLetter = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';

    FileImage? avatarImage;
    if (!isUser &&
        character?.avatarPath != null &&
        character!.avatarPath!.isNotEmpty) {
      avatarImage = FileImage(File(character.avatarPath!));
    }

    Widget bubble = Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isStandard
              ? double.infinity
              : MediaQuery.of(context).size.width * 0.88,
        ),
        margin: EdgeInsets.symmetric(
          horizontal: isStandard ? 16 : 12,
          vertical: isStandard ? 8 : 4,
        ),
        padding: isStandard
            ? const EdgeInsets.all(0)
            : const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: isStandard
              ? BorderRadius.zero
              : BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isStandard && !isSystem) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: isUser
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(
                            avatarLetter,
                            style: TextStyle(
                              fontSize: 12,
                              color: isUser
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
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
                        Icon(
                          Icons.psychology,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Reasoning',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                  color: (isStandard || !isUser)
                      ? scheme.onSurface
                      : scheme.onPrimary,
                ),
              ),
            ),
            if (isStreaming)
              Text(
                '...',
                style: TextStyle(
                  color: (isStandard || !isUser)
                      ? scheme.onSurfaceVariant
                      : scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (!isSystem && !isStreaming) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (genTime != null) ...[
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: (isStandard || !isUser)
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      genTime!,
                      style: TextStyle(
                        fontSize: 12,
                        color: (isStandard || !isUser)
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (tokens != null && tokens! > 0) ...[
                    Icon(
                      Icons.description_outlined,
                      size: 12,
                      color: (isStandard || !isUser)
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${tokens}t',
                      style: TextStyle(
                        fontSize: 12,
                        color: (isStandard || !isUser)
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  InkWell(
                    onTap: () => _showContextMenu(context, ref),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isStandard
                            ? scheme.surfaceContainerHighest
                            : (isUser
                                  ? Colors.transparent
                                  : scheme.surfaceContainerHighest),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.menu,
                        size: 16,
                        color: (isStandard || !isUser)
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    Widget bubbleWidget = isHidden
        ? Opacity(opacity: 0.5, child: bubble)
        : bubble;
    if (isSystem || isStreaming) return bubbleWidget;

    return GestureDetector(
      onLongPress: () => _showContextMenu(context, ref),
      child: bubbleWidget,
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(chatProvider(charId).notifier);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
              if (!isError)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditDialog(context, ref);
                  },
                ),
              if ((!isUser && isLast && !isGenerating) || isError)
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Regenerate'),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.regenerateLastAssistant();
                  },
                ),
              if (!isError)
                ListTile(
                  leading: const Icon(Icons.call_split),
                  title: const Text('Branch'),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.branchSession(messageIndex);
                  },
                ),
              ListTile(
                leading: Icon(
                  isHidden ? Icons.visibility : Icons.visibility_off,
                ),
                title: Text(isHidden ? 'Unhide' : 'Hide'),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.toggleMessageHidden(messageIndex);
                },
              ),
              if (isLast && !isGenerating)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.deleteMessage(messageIndex);
                  },
                ),
            ],
          ),
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
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).scaffoldBackgroundColor.withValues(alpha: 0.8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: TextField(
                    controller: _controller,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      filled: false,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CircleBtn(icon: Icons.auto_awesome),
                    const SizedBox(width: 8),
                    _CircleBtn(icon: Icons.image_outlined),
                    const SizedBox(width: 8),
                    _CircleBtn(icon: Icons.fullscreen_rounded),
                  ],
                ),
                GestureDetector(
                  onTap: widget.isGenerating ? widget.onStop : _handleSend,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.isGenerating ? 'Stop' : 'Send',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          widget.isGenerating
                              ? Icons.stop_rounded
                              : Icons.send_rounded,
                          color: Colors.black,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  const _CircleBtn({required this.icon});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).scaffoldBackgroundColor.withValues(alpha: 0.8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            shape: BoxShape.circle,
          ),
          child: Center(child: Icon(icon, color: AppColors.accent, size: 20)),
        ),
      ),
    );
  }
}

class _ChatHeaderTitle extends StatelessWidget {
  final Character character;
  final String sessionName;

  const _ChatHeaderTitle({required this.character, required this.sessionName});

  @override
  Widget build(BuildContext context) {
    Color avatarColor = AppColors.accent;
    if (character.color != null && character.color!.isNotEmpty) {
      try {
        final String c = character.color!.replaceFirst('#', '');
        avatarColor = Color(int.parse('FF$c', radix: 16));
      } catch (_) {}
    }

    final String initial = character.name.isNotEmpty
        ? character.name[0].toUpperCase()
        : '?';

    Widget avatar;
    if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
      avatar = CircleAvatar(
        radius: 17,
        backgroundImage: FileImage(File(character.avatarPath!)),
        onBackgroundImageError: (_, __) {},
        backgroundColor: avatarColor.withValues(alpha: 0.2),
        child: const SizedBox.shrink(),
      );
    } else {
      avatar = Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: avatarColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 16,
              color: avatarColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                character.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sessionName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
