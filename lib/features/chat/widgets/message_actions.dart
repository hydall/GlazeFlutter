import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTyping) ...[
              ListTile(
                leading: const Icon(Icons.stop_circle, color: Colors.orange),
                title: const Text('Stop Generating', style: TextStyle(color: Colors.orange)),
                onTap: () { Navigator.pop(ctx); notifier.abortGeneration(); },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                enabled: !(isGenerating && isLast),
                onTap: isGenerating && isLast ? null : () { Clipboard.setData(ClipboardData(text: content)); Navigator.pop(ctx); },
              ),
              if (!isError)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  enabled: !(isGenerating && isLast),
                  onTap: isGenerating && isLast ? null : () { Navigator.pop(ctx); showMessageEditDialog(context: context, ref: ref, charId: charId, content: content, messageIndex: messageIndex); },
                ),
              if ((!isUser && isLast && !isGenerating) || isError)
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Regenerate'),
                  onTap: () { Navigator.pop(ctx); notifier.regenerateLastAssistant(); },
                ),
              if (isGenerating && isLast)
                ListTile(
                  leading: const Icon(Icons.stop_circle, color: Colors.orange),
                  title: const Text('Stop Generating', style: TextStyle(color: Colors.orange)),
                  onTap: () { Navigator.pop(ctx); notifier.abortGeneration(); },
                ),
              if (!isError)
                ListTile(
                  leading: const Icon(Icons.call_split),
                  title: const Text('Branch'),
                  enabled: !(isGenerating && isLast),
                  onTap: isGenerating && isLast ? null : () { Navigator.pop(ctx); notifier.branchSession(messageIndex); },
                ),
              ListTile(
                leading: Icon(isHidden ? Icons.visibility : Icons.visibility_off),
                title: Text(isHidden ? 'Unhide' : 'Hide'),
                onTap: () { Navigator.pop(ctx); notifier.toggleMessageHidden(messageIndex); },
              ),
              if (isLast && !isGenerating)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () { Navigator.pop(ctx); notifier.deleteMessage(messageIndex); },
                ),
            ],
          ],
        ),
      ),
    ),
  );
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
