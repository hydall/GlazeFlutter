import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../chat_provider.dart';

void showRawPromptDialog(
  BuildContext context,
  WidgetRef ref,
  String charId,
) async {
  final chatState = ref.read(chatProvider(charId)).value;
  if (chatState == null || chatState.session == null) return;

  try {
    final builder = ref.read(promptPayloadBuilderProvider);
    final payload = await builder.buildFromSession(charId: charId, session: chatState.session);
    final result = await buildPromptInIsolate(payload);

    final rawJson = const JsonEncoder.withIndent('  ').convert({
      'model': payload.apiConfig.model,
      'messages': result.messages.map((m) {
        final map = <String, dynamic>{'role': m.role, 'content': m.content};
        if (m.isLorebook) map['lorebook'] = true;
        if (m.blockName != null) map['block'] = m.blockName;
        return map;
      }).toList(),
      'max_tokens': payload.apiConfig.maxTokens,
      'temperature': payload.apiConfig.temperature,
      'top_p': payload.apiConfig.topP,
    'stream': payload.apiConfig.stream,
  });

  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (ctx) => _CopyableDialog(title: 'Raw Prompt', content: rawJson),
  );
  } catch (e) {
    if (context.mounted) GlazeToast.error(context, 'Failed to build prompt: ', e);
  }
}

void showRawResponseDialog(BuildContext context, WidgetRef ref, String charId) {
  final chatState = ref.read(chatProvider(charId)).value;
  final raw = chatState?.lastRawResponse;
  if (raw == null || raw.isEmpty) {
    GlazeToast.show(context, 'No response yet — generate something first');
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) => _CopyableDialog(title: 'Raw Response', content: raw),
  );
}

void showPresetPickerDialog(BuildContext context, WidgetRef ref) async {
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

void showPersonaPickerDialog(BuildContext context, WidgetRef ref) async {
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

void confirmClearChatDialog(
  BuildContext context,
  WidgetRef ref,
  String charId,
) {
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

class _CopyableDialog extends StatelessWidget {
  final String title;
  final String content;

  const _CopyableDialog({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(title),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              GlazeToast.show(context, 'Copied to clipboard');
            },
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        child: SelectableText(
          content,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
