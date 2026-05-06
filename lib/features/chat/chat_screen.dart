import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/summary_service.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import 'chat_provider.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_dialogs.dart';
import 'widgets/magic_drawer.dart';
import 'widgets/message_list.dart';
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

    return GlazeScaffold(
      extendBodyBehindHeader: true,
      title: title,
      titleWidget: character != null
          ? ChatHeader(character: character, sessionName: sessionName, currentSessionIndex: sessionIndex)
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
          data: Theme.of(context).copyWith(
              iconTheme: const IconThemeData(color: AppColors.accent)),
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
                child: Row(children: [Icon(Icons.tune, size: 18), SizedBox(width: 8), Text('Preset')]),
              ),
              const PopupMenuItem(
                value: 'persona',
                child: Row(children: [Icon(Icons.person, size: 18), SizedBox(width: 8), Text('Persona')]),
              ),
              const PopupMenuItem(
                value: 'summary',
                child: Row(children: [Icon(Icons.summarize, size: 18), SizedBox(width: 8), Text('Generate Summary')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'raw',
                child: Row(children: [Icon(Icons.data_object, size: 18), SizedBox(width: 8), Text('View Raw Prompt')]),
              ),
              const PopupMenuItem(
                value: 'rawResponse',
                child: Row(children: [Icon(Icons.output, size: 18), SizedBox(width: 8), Text('View Raw Response')]),
              ),
              const PopupMenuItem(
                value: 'tokenizer',
                child: Row(children: [Icon(Icons.pie_chart_outline, size: 18), SizedBox(width: 8), Text('Context Usage')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(children: [Icon(Icons.delete_sweep, size: 18, color: Colors.red), SizedBox(width: 8), Text('Clear Chat', style: TextStyle(color: Colors.red))]),
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
              streamingReasoning: state.isGenerating ? state.streamingReasoning : null,
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Text(
                        state.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                      ),
                    ),
                  ChatInputBar(
                    onSend: (text) {
                      if (text.trim().isEmpty) return;
                      ref.read(chatProvider(charId).notifier).sendMessage(text);
                    },
                    isGenerating: state.isGenerating,
                    onStop: state.isGenerating
                        ? () => ref.read(chatProvider(charId).notifier).abortGeneration()
                        : null,
                    onMagicDrawer: () => showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (_) => MagicDrawerPanel(charId: charId),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _generateSummary(BuildContext context, WidgetRef ref, String charId) async {
  final chatState = ref.read(chatProvider(charId)).value;
  if (chatState == null || chatState.session == null) return;

  final apiConfigs = await ref.read(apiConfigRepoProvider).getAll();
  if (apiConfigs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No API config — set one up first')),
    );
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Generating summary...'), duration: Duration(seconds: 2)),
  );

  try {
    final summaryService = ref.read(summaryServiceProvider);
    final summary = await summaryService.generateSummary(
      sessionId: chatState.session!.id,
      history: chatState.session!.messages,
      apiConfig: apiConfigs.first,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Summary generated (${summary.length} chars)'), duration: const Duration(seconds: 2)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Summary failed: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
