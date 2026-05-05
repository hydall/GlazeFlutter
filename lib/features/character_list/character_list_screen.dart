import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/character.dart';
import '../../core/state/character_provider.dart';
import '../../shared/theme/app_colors.dart';

class CharacterListScreen extends ConsumerWidget {
  const CharacterListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final characters = ref.watch(charactersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Glaze'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings/api'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // TODO: implement character import
            },
          ),
        ],
      ),
      body: characters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chars) => chars.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_add, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    const Text('No characters yet'),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () {
                        // TODO: implement character import
                      },
                      child: const Text('Import Character'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: chars.length,
                itemBuilder: (_, i) => _CharacterTile(character: chars[i]),
              ),
      ),
    );
  }
}

class _CharacterTile extends ConsumerWidget {
  final Character character;
  const _CharacterTile({required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: character.color != null
            ? _parseColor(character.color!)
            : AppColors.accent,
        child: Text(
          character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.black),
        ),
      ),
      title: Text(character.name),
      subtitle: Text(
        character.description ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.go('/chat/${character.id}'),
    );
  }

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceFirst('#', '');
      return Color(int.parse('FF$c', radix: 16));
    } catch (_) {
      return AppColors.accent;
    }
  }
}
