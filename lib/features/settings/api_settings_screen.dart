import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/api_config.dart';
import '../../core/state/db_provider.dart';
import '../cloud_sync/services/sync_deletion_tracker.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import 'api_editor_screen.dart';

final apiListProvider = AsyncNotifierProvider<ApiListNotifier, List<ApiConfig>>(
  ApiListNotifier.new,
);

class ApiListNotifier extends AsyncNotifier<List<ApiConfig>> {
  @override
  Future<List<ApiConfig>> build() async {
    return ref.watch(apiConfigRepoProvider).getAll();
  }

  Future<void> put(ApiConfig config) async {
    await ref.read(apiConfigRepoProvider).put(config);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(apiConfigRepoProvider).delete(id);
    await SyncDeletionTracker.record('api_presets', id);
    ref.invalidateSelf();
  }
}

class ApiSettingsScreen extends ConsumerWidget {
  const ApiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(apiListProvider);

    return GlazeScaffold(
      title: 'API Settings',
      onBack: () => context.go('/tools'),
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          color: AppColors.accent,
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ApiEditorScreen())),
        ),
      ],
      body: configs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.api, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    const Text('No API configs yet'),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ApiEditorScreen(),
                        ),
                      ),
                      child: const Text('Add API Config'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _ApiConfigTile(config: list[i]),
              ),
      ),
    );
  }
}

class _ApiConfigTile extends ConsumerWidget {
  final ApiConfig config;
  const _ApiConfigTile({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEmbedding = config.embeddingModel.isNotEmpty && !config.embeddingUseSame;
    return ListTile(
      leading: Icon(
        isEmbedding ? Icons.hub : Icons.smart_toy,
        color: isEmbedding ? AppColors.accent : null,
        size: 20,
      ),
      title: Text(config.name.isNotEmpty ? config.name : config.model),
      subtitle: Text(
        '${config.endpoint.replaceAll(RegExp(r'https?://'), '').split('/').first} · ${config.model}',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ApiEditorScreen(config: config),
              ),
            );
          } else if (value == 'delete') {
            ref.read(apiListProvider.notifier).remove(config.id);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ApiEditorScreen(config: config)),
      ),
    );
  }
}
