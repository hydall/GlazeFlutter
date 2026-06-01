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
import '../../shared/widgets/glaze_toast.dart';
import 'embedding_settings_screen.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import 'lorebook_connections_sheet.dart';
import 'lorebook_editor_screen.dart';
import 'lorebook_global_settings_screen.dart';

class LorebookListScreen extends ConsumerWidget {
  const LorebookListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lorebooksAsync = ref.watch(lorebooksProvider);

    return SheetView(
      showRouteBackground: false,
      title: 'Lorebooks',
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
          tooltip: 'Global Settings',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const LorebookGlobalSettingsScreen(),
            ),
          ),
        ),
        SheetViewAction(
          icon: const Icon(Icons.upload_file, size: 20),
          tooltip: 'Import ST Lorebook',
          onPressed: () => _importSTLorebook(context, ref),
        ),
        SheetViewAction(
          icon: const Icon(Icons.search, size: 20),
          tooltip: 'Embedding Settings',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EmbeddingSettingsScreen()),
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
                    'No lorebooks yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: context.cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to create one',
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
                  MaterialPageRoute(
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
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _createLorebook(BuildContext context, WidgetRef ref) {
    final id = generateId();
    final lorebook = Lorebook(
      id: id,
      name: 'New Lorebook',
      entries: [],
      updatedAt: currentTimestampSeconds(),
    );
    ref.read(lorebooksProvider.notifier).addLorebook(lorebook).then((_) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LorebookEditorScreen(lorebookId: id)),
      );
    });
  }

  Future<void> _importSTLorebook(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Import SillyTavern Lorebook',
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
          'Imported "${importResult.lorebook.name}" (${importResult.entryCount} entries)',
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                LorebookEditorScreen(lorebookId: importResult.lorebook.id),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        GlazeToast.error(context, 'Import failed: ', e);
      }
    }
  }

  void _deleteLorebook(BuildContext context, WidgetRef ref, Lorebook lb) {
    GlazeBottomSheet.show(
      context,
      title: 'Delete Lorebook',
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'Delete "${lb.name}"? This cannot be undone.',
      ),
      items: [
        BottomSheetItem(
          label: 'Delete',
          isDestructive: true,
          centered: true,
          onTap: () {
            ref.read(lorebooksProvider.notifier).deleteLorebook(lb.id);
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
        BottomSheetItem(
          label: 'Cancel',
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
        ? 'global'
        : hasCharBinding
        ? 'character'
        : hasChatBinding
        ? 'chat'
        : 'none';

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
              '${lorebook.entries.length} entries',
              style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.link, size: 18),
              tooltip: 'Connections',
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
