import 'package:flutter/material.dart';

/// Modal dialog helpers for editing / deleting an ext-block from the
/// chat WebView's ext-blocks panel. Extracted from
/// `chat_webview_widget.dart` so the widget doesn't have to carry
/// the AlertDialog + TextField plumbing inline.
class ExtBlockDialogs {
  const ExtBlockDialogs._();

  /// Show a multi-line editor seeded with [initialContent] and the
  /// given [blockName] in the title. Returns the user-entered
  /// content on save, or `null` on cancel.
  static Future<String?> promptEdit({
    required BuildContext context,
    required String blockName,
    required String initialContent,
  }) {
    final controller = TextEditingController(text: initialContent);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Редактировать «$blockName»'),
          content: SizedBox(
            width: 500,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 12,
              minLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Содержимое блока…',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  /// Show a confirmation dialog for deleting the named ext-block.
  /// Returns `true` if the user confirmed, `false` otherwise.
  static Future<bool> confirmDelete({
    required BuildContext context,
    required String blockName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Удалить «$blockName»?'),
          content: const Text(
            'Блок будет удалён из базы данных. Это нельзя отменить.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }
}
