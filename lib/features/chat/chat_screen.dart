import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/summary_service.dart';
import '../../core/models/chat_message.dart';
import '../../core/services/chat_import_export.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../chat_history/chat_history_screen.dart' show chatHistoryProvider;
import '../image_gen/widgets/image_gen_sheet.dart';
import 'chat_provider.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_dialogs.dart';
import 'widgets/magic_drawer.dart';
import 'widgets/memory_books_sheet.dart';
import 'widgets/message_list.dart';
import 'widgets/session_lifecycle_tracker.dart';
import 'widgets/tokenizer_sheet.dart';

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
                  case 'clear':
                    confirmClearChatDialog(context, ref, charId);
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
                      onMagicDrawer: () => GlazeBottomSheet.show(
                        context,
                        child: MagicDrawerPanel(charId: charId),
                      ),
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
  final chatState = ref.read(chatProvider(charId)).value;
  if (chatState == null || chatState.session == null) return;

  final apiConfigs = await ref.read(apiConfigRepoProvider).getAll();
  if (apiConfigs.isEmpty) {
    GlazeToast.show(context, 'No API config — set one up first');
    return;
  }

  GlazeToast.show(context, 'Generating summary...');

  try {
    final summaryService = ref.read(summaryServiceProvider);
    final summary = await summaryService.generateSummary(
      sessionId: chatState.session!.id,
      history: chatState.session!.messages,
      apiConfig: apiConfigs.first,
    );
    if (context.mounted) {
      GlazeToast.show(context, 'Summary generated (${summary.length} chars)');
    }
  } catch (e) {
    if (context.mounted) {
      GlazeToast.show(context, 'Summary failed: $e');
    }
  }
}

void _showMemoryBooks(BuildContext context, WidgetRef ref, String charId) {
  final chatState = ref.read(chatProvider(charId)).value;
  if (chatState == null || chatState.session == null) return;

  GlazeBottomSheet.show(
    context,
    child: MemoryBooksSheet(sessionId: chatState.session!.id),
  );
}

Future<void> _exportChat(
  BuildContext context,
  WidgetRef ref,
  String charId,
) async {
  final chatState = ref.read(chatProvider(charId)).value;
  if (chatState == null || chatState.session == null) return;

  final charRepo = ref.read(characterRepoProvider);
  final character = await charRepo.getById(charId);
  if (character == null) return;

  try {
    final desktop =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final outputDir = '${desktop}\\Desktop';

    final result = await exportChatAsJsonl(
      session: chatState.session!,
      character: character,
      outputDir: outputDir,
    );
    if (context.mounted) {
      GlazeToast.show(context, 'Chat exported to ${result.filePath}');
    }
  } catch (e) {
    if (context.mounted) {
      GlazeToast.show(context, 'Export failed: $e');
    }
  }
}

Future<void> _importChat(
  BuildContext context,
  WidgetRef ref,
  String charId,
) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jsonl', 'json'],
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return;

  final filePath = result.files.first.path;
  if (filePath == null) return;

  try {
    final importResult = await importChatFromJsonl(filePath);
    if (importResult.messages.isEmpty) {
      if (context.mounted) {
        GlazeToast.show(context, 'No messages found in file');
      }
      return;
    }

    final repo = ref.read(chatRepoProvider);
    final existingSessions = await repo.getByCharacterId(charId);

    int maxIdx = 0;
    for (final s in existingSessions) {
      if (s.sessionIndex > maxIdx) maxIdx = s.sessionIndex;
    }

    final newSession = ChatSession(
      id: '${charId}_${maxIdx + 1}',
      characterId: charId,
      sessionIndex: maxIdx + 1,
      messages: importResult.messages,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await repo.put(newSession);
    ref.invalidate(chatProvider(charId));
    ref.invalidate(chatHistoryProvider);

    if (context.mounted) {
      GlazeToast.show(
        context,
        'Imported ${importResult.messages.length} messages',
      );
    }
  } catch (e) {
    if (context.mounted) {
      GlazeToast.show(context, 'Import failed: $e');
    }
  }
}
