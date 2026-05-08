import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/chat_message.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../chat_history/chat_history_provider.dart';
import '../image_gen/widgets/image_gen_sheet.dart';
import 'chat_actions_service.dart';
import 'chat_provider.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_dialogs.dart';
import 'widgets/magic_drawer.dart';
import 'widgets/memory_books_sheet.dart';
import 'widgets/message_list.dart';
import 'widgets/lorebook_coverage_sheet.dart';
import 'widgets/prompt_preview_screen.dart';
import 'widgets/session_lifecycle_tracker.dart';
import 'widgets/tokenizer_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String charId;
  final int? initialSessionIndex;
  final bool forceNewSession;
  const ChatScreen({
    super.key,
    required this.charId,
    this.initialSessionIndex,
    this.forceNewSession = false,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _sessionApplied = false;
  bool _showSearch = false;
  String _searchQuery = '';
  int _searchCurrentIndex = 0;
  List<int> _searchMatches = [];

  @override
  void initState() {
    super.initState();
    if (widget.forceNewSession || widget.initialSessionIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySessionPreference();
      });
    }
  }

  Future<void> _applySessionPreference() async {
    if (_sessionApplied) return;
    _sessionApplied = true;
    final notifier = ref.read(chatProvider(widget.charId).notifier);
    if (widget.forceNewSession) {
      await notifier.createNewSession();
    } else if (widget.initialSessionIndex != null) {
      await notifier.switchSession(widget.initialSessionIndex!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final charId = widget.charId;
    final chatStateAsync = ref.watch(chatProvider(charId));
    final chatState = chatStateAsync.value;

    final chars = ref.watch(charactersProvider).value ?? [];
    final character = chars.where((c) => c.id == charId).firstOrNull;
    final title = character?.name ?? 'Chat';
    final sessionName = chatState?.session != null
        ? 'Session #${chatState!.session!.sessionIndex}'
        : 'Loading...';
    final sessionIndex = chatState?.session?.sessionIndex ?? 0;

    return SessionLifecycleTracker(
      charId: charId,
      child: GlazeScaffold(
        extendBodyBehindHeader: true,
        title: title,
        titleWidget: character != null
            ? ChatHeader(
                character: character,
                sessionName: sessionName,
                currentSessionIndex: sessionIndex,
              )
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
                    onPressed: () => ref
                        .read(chatProvider(charId).notifier)
                        .abortGeneration(),
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
                    showPresetPickerDialog(context, ref);
                  case 'persona':
                    showPersonaPickerDialog(context, ref);
                  case 'summary':
                    _generateSummary(context, ref, charId);
                  case 'memory':
                    _showMemoryBooks(context, ref, charId);
                  case 'export_chat':
                    _exportChat(context, ref, charId);
                  case 'import_chat':
                    _importChat(context, ref, charId);
                  case 'raw':
                    showRawPromptDialog(context, ref, charId);
                  case 'rawResponse':
                    showRawResponseDialog(context, ref, charId);
                  case 'tokenizer':
                    showTokenizerSheet(context, charId);
                  case 'coverage':
                    showLorebookCoverageSheet(context, ref, charId);
                  case 'preview':
                    showPromptPreviewScreen(context, charId);
                  case 'clear':
                    confirmClearChatDialog(context, ref, charId);
                  case 'search':
                    setState(() {
                      _showSearch = !_showSearch;
                      _searchQuery = '';
                      _searchMatches = [];
                      _searchCurrentIndex = 0;
                    });
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
                const PopupMenuItem(
                  value: 'summary',
                  child: Row(
                    children: [
                      Icon(Icons.summarize, size: 18),
                      SizedBox(width: 8),
                      Text('Generate Summary'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'memory',
                  child: Row(
                    children: [
                      Icon(Icons.auto_stories, size: 18),
                      SizedBox(width: 8),
                      Text('Memory Books'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export_chat',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file, size: 18),
                      SizedBox(width: 8),
                      Text('Export Chat (JSONL)'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'import_chat',
                  child: Row(
                    children: [
                      Icon(Icons.file_download, size: 18),
                      SizedBox(width: 8),
                      Text('Import Chat'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'preview',
                  child: Row(
                    children: [
                      Icon(Icons.visibility, size: 18),
                      SizedBox(width: 8),
                      Text('Prompt Preview'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'coverage',
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18),
                      SizedBox(width: 8),
                      Text('Lorebook Coverage'),
                    ],
                  ),
                ),
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
                  value: 'rawResponse',
                  child: Row(
                    children: [
                      Icon(Icons.output, size: 18),
                      SizedBox(width: 8),
                      Text('View Raw Response'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'tokenizer',
                  child: Row(
                    children: [
                      Icon(Icons.pie_chart_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Context Usage'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18),
                      SizedBox(width: 8),
                      Text('Find in Chat'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
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
              MessageList(
                messages: state.messages,
                streamingText: state.isGenerating ? state.streamingText : null,
                streamingReasoning: state.isGenerating
                    ? state.streamingReasoning
                    : null,
                isGenerating: state.isGenerating,
                charId: charId,
              ),
              if (_showSearch)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _ChatSearchBar(
                    query: _searchQuery,
                    matchCount: _searchMatches.length,
                    currentIndex: _searchCurrentIndex,
                    onChanged: (q) {
                      final matches = <int>[];
                      if (q.isNotEmpty) {
                        final lower = q.toLowerCase();
                        for (int i = 0; i < state.messages.length; i++) {
                          if (state.messages[i].content.toLowerCase().contains(lower)) {
                            matches.add(i);
                          }
                        }
                      }
                      setState(() {
                        _searchQuery = q;
                        _searchMatches = matches;
                        _searchCurrentIndex = matches.isNotEmpty ? 0 : 0;
                      });
                    },
                    onPrevious: _searchCurrentIndex > 0
                        ? () => setState(() => _searchCurrentIndex--)
                        : null,
                    onNext: _searchCurrentIndex < _searchMatches.length - 1
                        ? () => setState(() => _searchCurrentIndex++)
                        : null,
                    onClose: () => setState(() {
                      _showSearch = false;
                      _searchQuery = '';
                      _searchMatches = [];
                    }),
                  ),
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
                    ChatInputBar(
                      onSend: (text) {
                        if (text.trim().isEmpty) return;
                        ref
                            .read(chatProvider(charId).notifier)
                            .sendMessage(text);
                      },
                      onSendWithGuidance: (text, guidance) {
                        if (text.trim().isEmpty) return;
                        ref
                            .read(chatProvider(charId).notifier)
                            .sendMessage(text, guidanceText: guidance);
                      },
                      isGenerating: state.isGenerating,
                      onStop: state.isGenerating
                          ? () => ref
                                .read(chatProvider(charId).notifier)
                                .abortGeneration()
                          : null,
                      onMagicDrawer: () => showMagicDrawer(context, charId),
                      onImageGen: () => GlazeBottomSheet.show(
                        context,
                        child: const ImageGenSheet(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _generateSummary(
  BuildContext context,
  WidgetRef ref,
  String charId,
) async {
  try {
    final summary = await ChatActionsService(ref).generateSummary(charId);
    if (context.mounted) {
      GlazeToast.show(context, 'Summary generated (${summary.length} chars)');
    }
  } on StateError catch (e) {
    if (context.mounted) GlazeToast.show(context, e.message);
  } catch (e) {
    if (context.mounted) GlazeToast.error(context, 'Summary failed: ', e);
  }
}

void _showMemoryBooks(BuildContext context, WidgetRef ref, String charId) {
  final chatState = ref.read(chatProvider(charId)).value;
  if (chatState == null || chatState.session == null) return;

  GlazeBottomSheet.show(
    context,
    child: MemoryBooksSheet(sessionId: chatState.session!.id, charId: charId),
  );
}

Future<void> _exportChat(
  BuildContext context,
  WidgetRef ref,
  String charId,
) async {
  try {
    final filePath = await ChatActionsService(ref).exportChat(charId);
    if (context.mounted) {
      GlazeToast.show(context, 'Chat exported to $filePath');
    }
  } on StateError catch (e) {
    if (context.mounted) GlazeToast.show(context, e.message);
  } catch (e) {
    if (context.mounted) GlazeToast.error(context, 'Export failed: ', e);
  }
}

Future<void> _importChat(
  BuildContext context,
  WidgetRef ref,
  String charId,
) async {
  final result = await FilePicker.pickFiles(
    type: Platform.isIOS ? FileType.any : FileType.custom,
    allowedExtensions: Platform.isIOS ? null : ['jsonl', 'json'],
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return;

  final filePath = result.files.first.path;
  if (filePath == null) return;

  try {
    final count = await ChatActionsService(ref).importChat(charId, filePath);
    if (context.mounted) {
      if (count == 0) {
        GlazeToast.show(context, 'No messages found in file');
      } else {
        GlazeToast.show(context, 'Imported $count messages');
      }
    }
  } catch (e) {
    if (context.mounted) {
        GlazeToast.error(context, 'Import failed: ', e);
    }
  }
}

class _ChatSearchBar extends StatelessWidget {
  final String query;
  final int matchCount;
  final int currentIndex;
  final ValueChanged<String> onChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  const _ChatSearchBar({
    required this.query,
    required this.matchCount,
    required this.currentIndex,
    required this.onChanged,
    this.onPrevious,
    this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Find in chat...',
                  hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: onChanged,
              ),
            ),
            if (query.isNotEmpty) ...[
              Text(
                matchCount > 0 ? '${currentIndex + 1}/$matchCount' : '0/0',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              IconButton(icon: const Icon(Icons.keyboard_arrow_up, size: 20), onPressed: onPrevious, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
              IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 20), onPressed: onNext, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
            ],
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
          ],
        ),
      ),
    );
  }
}
