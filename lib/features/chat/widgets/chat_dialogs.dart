import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
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

  GlazeBottomSheet.show(
    context,
    title: 'Raw Prompt',
    headerAction: IconButton(
      icon: const Icon(Icons.copy),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: rawJson));
        GlazeToast.show(context, 'Copied to clipboard');
      },
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SelectableText(
        rawJson,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    ),
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

  GlazeBottomSheet.show(
    context,
    title: 'Raw Response',
    headerAction: IconButton(
      icon: const Icon(Icons.copy),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: raw));
        GlazeToast.show(context, 'Copied to clipboard');
      },
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SelectableText(
        raw,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    ),
  );
}

void showPresetPickerDialog(BuildContext context, WidgetRef ref) async {
  final presets = await ref.read(presetRepoProvider).getAll();
  final activeId = ref.read(activePresetIdProvider);
  if (!context.mounted) return;

  GlazeBottomSheet.show(
    context,
    title: 'Select Preset',
    items: [
      BottomSheetItem(
        label: 'Default (first)',
        icon: activeId == null ? Icons.check : null,
        iconColor: activeId == null ? const Color(0xFF7996CE) : null,
        onTap: () {
          setActivePreset(ref, null);
          Navigator.pop(context);
        },
      ),
      ...presets.map(
        (p) => BottomSheetItem(
          label: p.name,
          icon: activeId == p.id ? Icons.check : null,
          iconColor: activeId == p.id ? const Color(0xFF7996CE) : null,
          onTap: () {
            setActivePreset(ref, p.id);
            Navigator.pop(context);
          },
        ),
      ),
    ],
  );
}

void showPersonaPickerDialog(BuildContext context, WidgetRef ref) async {
  final personas = await ref.read(personaRepoProvider).getAll();
  final activeId = ref.read(activePersonaIdProvider);
  if (!context.mounted) return;

  GlazeBottomSheet.show(
    context,
    title: 'Select Persona',
    items: [
      BottomSheetItem(
        label: 'Default (first)',
        icon: activeId == null ? Icons.check : null,
        iconColor: activeId == null ? const Color(0xFF7996CE) : null,
        onTap: () {
          setActivePersona(ref, null);
          Navigator.pop(context);
        },
      ),
      ...personas.map(
        (p) => BottomSheetItem(
          label: p.name,
          icon: activeId == p.id ? Icons.check : null,
          iconColor: activeId == p.id ? const Color(0xFF7996CE) : null,
          onTap: () {
            setActivePersona(ref, p.id);
            Navigator.pop(context);
          },
        ),
      ),
    ],
  );
}

void confirmClearChatDialog(
  BuildContext context,
  WidgetRef ref,
  String charId,
) {
  GlazeBottomSheet.show(
    context,
    title: 'Clear Chat',
    bigInfo: const BottomSheetBigInfo(
      icon: Icons.delete_outline,
      description: 'Delete all messages? This cannot be undone.',
    ),
    items: [
      BottomSheetItem(
        label: 'Clear',
        isDestructive: true,
        centered: true,
        onTap: () {
          Navigator.pop(context);
          ref.read(chatProvider(charId).notifier).clearChat();
        },
      ),
      BottomSheetItem(
        label: 'Cancel',
        centered: true,
        onTap: () => Navigator.pop(context),
      ),
    ],
  );
}
