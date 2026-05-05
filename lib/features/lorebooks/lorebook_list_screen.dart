import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/lorebook.dart';
import '../../core/state/lorebook_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import 'lorebook_editor_screen.dart';

class LorebookListScreen extends ConsumerWidget {
  const LorebookListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lorebooksAsync = ref.watch(lorebooksProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () => _createLorebook(context, ref),
      ),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlazeAppBar(
                title: 'Lorebooks',
                leading: BackButton(onPressed: () => context.go('/tools')),
              ),
            ),
          ),
          Expanded(
            child: lorebooksAsync.when(
              data: (lorebooks) {
                if (lorebooks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_outlined, size: 64, color: AppColors.textSecondary),
                        const SizedBox(height: 16),
                        Text(
                          'No lorebooks yet',
                          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap + to create one',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: lorebooks.length,
                  itemBuilder: (_, i) => _LorebookTile(
                    lorebook: lorebooks[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LorebookEditorScreen(lorebookId: lorebooks[i].id),
                      ),
                    ),
                    onDelete: () => _deleteLorebook(context, ref, lorebooks[i]),
                    onToggle: () => ref
                        .read(lorebooksProvider.notifier)
                        .updateLorebook(lorebooks[i].copyWith(enabled: !lorebooks[i].enabled)),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _createLorebook(BuildContext context, WidgetRef ref) {
    final id = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final lorebook = Lorebook(
      id: id,
      name: 'New Lorebook',
      entries: [],
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    ref.read(lorebooksProvider.notifier).addLorebook(lorebook).then((_) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LorebookEditorScreen(lorebookId: id),
        ),
      );
    });
  }

  void _deleteLorebook(BuildContext context, WidgetRef ref, Lorebook lb) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Lorebook'),
        content: Text('Delete "${lb.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(lorebooksProvider.notifier).deleteLorebook(lb.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _LorebookTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scopeColor = switch (lorebook.activationScope) {
      'global' => Colors.green,
      'character' => Colors.purple,
      'chat' => Colors.orange,
      _ => Colors.grey,
    };

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
          color: lorebook.enabled ? AppColors.accent : AppColors.textSecondary,
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
                lorebook.activationScope,
                style: TextStyle(fontSize: 10, color: scopeColor, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${lorebook.entries.length} entries',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: lorebook.enabled, onChanged: (_) => onToggle(), activeColor: AppColors.accent),
            IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: onDelete),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
