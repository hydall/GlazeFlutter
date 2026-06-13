import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/import/st_lorebook_importer.dart';
import '../../core/models/lorebook.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/lorebook_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/sheet_view.dart';
import '../../shared/widgets/glaze_error_dialog.dart';
import '../../shared/widgets/glaze_toast.dart';
import 'embedding_settings_screen.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import 'lorebook_connections_sheet.dart';
import 'lorebook_editor_screen.dart';

class LorebookListScreen extends ConsumerWidget {
  const LorebookListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lorebooksAsync = ref.watch(lorebooksProvider);

    return SheetView(
      showRouteBackground: false,
      title: 'menu_lorebooks'.tr(),
      showBack: true,
      onBack: () => context.go('/tools'),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.cs.primary,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () => _createLorebook(context, ref),
      ),
      actions: [
        SheetViewAction(
          icon: const Icon(Icons.settings_outlined, size: 20),
          tooltip: 'lorebook_global_settings_tooltip'.tr(),
          onPressed: () => context.push('/tools/lorebooks/settings'),
        ),
        SheetViewAction(
          icon: const Icon(Icons.upload_file, size: 20),
          tooltip: 'lorebook_import_st_tooltip'.tr(),
          onPressed: () => _importSTLorebook(context, ref),
        ),
        SheetViewAction(
          icon: const Icon(Icons.search, size: 20),
          tooltip: 'lorebook_embedding_settings_tooltip'.tr(),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const EmbeddingSettingsScreen()),
          ),
        ),
      ],
      body: lorebooksAsync.when(
        data: (lorebooks) {
          if (lorebooks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 64,
                    color: context.cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'no_lorebooks'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      color: context.cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'empty_lorebooks_desc'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          return Builder(
            builder: (context) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16,
              ).add(EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top,
                bottom: MediaQuery.paddingOf(context).bottom,
              )),
              itemCount: lorebooks.length,
              itemBuilder: (_, i) => _LorebookTile(
                lorebook: lorebooks[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LorebookEditorScreen(lorebookId: lorebooks[i].id),
                  ),
                ),
                onDelete: () => _deleteLorebook(context, ref, lorebooks[i]),
                onToggle: () => ref
                    .read(lorebooksProvider.notifier)
                    .updateLorebook(
                      lorebooks[i].copyWith(enabled: !lorebooks[i].enabled),
                    ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${'title_error'.tr()}: $e')),
      ),
    );
  }

  void _createLorebook(BuildContext context, WidgetRef ref) {
    final id = generateId();
    final lorebook = Lorebook(
      id: id,
      name: 'new_lorebook'.tr(),
      entries: [],
      updatedAt: currentTimestampSeconds(),
    );
    ref.read(lorebooksProvider.notifier).addLorebook(lorebook).then((_) {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LorebookEditorScreen(lorebookId: id)),
      );
    });
  }

  Future<void> _importSTLorebook(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'lorebook_import_st_dialog_title'.tr(),
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;

    try {
      final importResult = await importSTLorebookFromFile(filePath);
      await ref
          .read(lorebooksProvider.notifier)
          .addLorebook(importResult.lorebook);
      if (context.mounted) {
        GlazeToast.show(
          context,
          'lorebook_imported'.tr(args: [importResult.lorebook.name, importResult.entryCount.toString()]),
        );
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                LorebookEditorScreen(lorebookId: importResult.lorebook.id),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        GlazeErrorDialog.show(context, e, prefix: 'Import failed: ');
      }
    }
  }

  void _deleteLorebook(BuildContext context, WidgetRef ref, Lorebook lb) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'confirm_delete_lorebook'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'lorebook_confirm_delete_desc'.tr(args: [lb.name]),
      ),
      items: [
        BottomSheetItem(
          label: 'btn_delete'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () {
            ref.read(lorebooksProvider.notifier).deleteLorebook(lb.id);
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
        BottomSheetItem(
          label: 'btn_cancel'.tr(),
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }
}

class _LorebookTile extends ConsumerWidget {
  final Lorebook lorebook;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _LorebookTile({
    required this.lorebook,
    required this.onTap,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activations = ref.watch(lorebookActivationsProvider);
    final hasCharBinding = activations.character.values.any(
      (list) => list.contains(lorebook.id),
    );
    final hasChatBinding = activations.chat.values.any(
      (list) => list.contains(lorebook.id),
    );

    final scopeColor = lorebook.enabled
        ? Colors.green
        : hasCharBinding
        ? Colors.purple
        : hasChatBinding
        ? Colors.orange
        : Colors.grey;

    final scopeLabel = lorebook.enabled
        ? 'level_global'.tr()
        : hasCharBinding
        ? 'level_character'.tr()
        : hasChatBinding
        ? 'level_chat'.tr()
        : 'label_none'.tr();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        leading: Icon(
          Icons.menu_book,
          color: lorebook.enabled ? context.cs.primary : context.cs.onSurfaceVariant,
        ),
        title: Text(lorebook.name),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scopeColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                scopeLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: scopeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${lorebook.entries.length} ${'label_entries'.tr()}',
              style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.link, size: 18),
              tooltip: 'header_connections'.tr(),
              onPressed: () => showLorebookConnections(context, lorebook.id),
            ),
            Switch(
              value: lorebook.enabled,
              onChanged: (_) => onToggle(),
              activeThumbColor: context.cs.primary,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
