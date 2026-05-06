import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../chat_provider.dart';

void showMessageContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required String charId,
  required String content,
  required int messageIndex,
  required bool isUser,
  required bool isTyping,
  required bool isError,
  required bool isLast,
  required bool isGenerating,
  required bool isHidden,
}) {
  final notifier = ref.read(chatProvider(charId).notifier);

  final items = <BottomSheetItem>[
    if (isTyping)
      BottomSheetItem(
        icon: Icons.stop_circle,
        iconColor: Colors.orange,
        label: 'Stop Generating',
        onTap: () { Navigator.pop(context); notifier.abortGeneration(); },
      )
    else ...[
      if (!(isGenerating && isLast))
        BottomSheetItem(
          icon: Icons.copy,
          label: 'Copy',
          onTap: () { Clipboard.setData(ClipboardData(text: content)); Navigator.pop(context); },
        ),
      if (!isError && !(isGenerating && isLast))
        BottomSheetItem(
          icon: Icons.edit,
          label: 'Edit',
          onTap: () { Navigator.pop(context); showMessageEditDialog(context: context, ref: ref, charId: charId, content: content, messageIndex: messageIndex); },
        ),
      if ((!isUser && isLast && !isGenerating) || isError)
        BottomSheetItem(
          icon: Icons.refresh,
          label: 'Regenerate',
          onTap: () { Navigator.pop(context); notifier.regenerateLastAssistant(); },
        ),
      if (isGenerating && isLast)
        BottomSheetItem(
          icon: Icons.stop_circle,
          iconColor: Colors.orange,
          label: 'Stop Generating',
          onTap: () { Navigator.pop(context); notifier.abortGeneration(); },
        ),
      if (!isError && !(isGenerating && isLast))
        BottomSheetItem(
          icon: Icons.call_split,
          label: 'Branch',
          onTap: () { Navigator.pop(context); notifier.branchSession(messageIndex); },
        ),
      BottomSheetItem(
        icon: isHidden ? Icons.visibility : Icons.visibility_off,
        label: isHidden ? 'Unhide' : 'Hide',
        onTap: () { Navigator.pop(context); notifier.toggleMessageHidden(messageIndex); },
      ),
      if (isLast && !isGenerating)
        BottomSheetItem(
          icon: Icons.delete,
          label: 'Delete',
          isDestructive: true,
          onTap: () { Navigator.pop(context); notifier.deleteMessage(messageIndex); },
        ),
    ],
  ];

  GlazeBottomSheet.show(context, items: items);
}

void showMessageEditDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String charId,
  required String content,
  required int messageIndex,
}) {
  final controller = TextEditingController(text: content);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit Message'),
      content: TextField(controller: controller, maxLines: 8, minLines: 3, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final newText = controller.text.trim();
            if (newText.isNotEmpty) ref.read(chatProvider(charId).notifier).editMessage(messageIndex, newText);
            Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
