import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../chat_provider.dart';
import '../editing_message_provider.dart';

void showMessageContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required String charId,
  required String content,
  required int messageIndex,
  required String messageId,
  required bool isUser,
  required bool isTyping,
  required bool isError,
  required bool isLast,
  required bool isGenerating,
  required bool isHidden,
}) {
  final notifier = ref.read(chatProvider(charId).notifier);

  // User messages are never the "active generation target" — the streaming
  // placeholder is a separate assistant section in the webview that does not
  // appear in `widget.state.messages`. Without this, sending a new message
  // would replace the user message's menu with only "Stop Generating".
  final isActivelyGenerating = isGenerating && isLast && !isUser;
  final isTypingTarget = isTyping && !isUser;

  final items = <BottomSheetItem>[
    if (isTypingTarget)
      BottomSheetItem(
        icon: Icons.stop_circle,
        iconColor: Colors.orange,
        label: 'Stop Generating',
        onTap: () {
          Navigator.of(context, rootNavigator: true).pop();
          notifier.abortGeneration();
        },
      )
    else ...[
      if (!isActivelyGenerating)
        BottomSheetItem(
          icon: Icons.copy,
          label: 'Copy',
          onTap: () {
            Clipboard.setData(ClipboardData(text: content));
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
      if (!isError && !isActivelyGenerating)
        BottomSheetItem(
          icon: Icons.edit,
          label: 'Edit',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref.read(editingMessageIdProvider(charId).notifier).state = messageId;
          },
        ),
      if ((!isUser && isLast && !isGenerating) || isError)
        BottomSheetItem(
          icon: Icons.refresh,
          label: 'Regenerate',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            notifier.regenerateLastAssistant();
          },
        ),
      if (isActivelyGenerating)
        BottomSheetItem(
          icon: Icons.stop_circle,
          iconColor: Colors.orange,
          label: 'Stop Generating',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            notifier.abortGeneration();
          },
        ),
      if (!isError && !isActivelyGenerating)
        BottomSheetItem(
          icon: Icons.call_split,
          label: 'Branch',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            notifier.branchSession(messageIndex);
          },
        ),
      BottomSheetItem(
        icon: isHidden ? Icons.visibility : Icons.visibility_off,
        label: isHidden ? 'Unhide' : 'Hide',
        onTap: () {
          Navigator.of(context, rootNavigator: true).pop();
          notifier.toggleMessageHidden(messageIndex);
        },
      ),
      if (isLast && !isGenerating)
        BottomSheetItem(
          icon: Icons.delete,
          label: 'Delete',
          isDestructive: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            notifier.deleteMessage(messageIndex);
          },
        ),
    ],
  ];

  GlazeBottomSheet.show<void>(context, items: items);
}

