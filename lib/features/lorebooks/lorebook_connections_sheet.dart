import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/character.dart';
import '../../../core/models/lorebook.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';

class LorebookConnectionsSheet extends ConsumerStatefulWidget {
  final String lorebookId;
  const LorebookConnectionsSheet({super.key, required this.lorebookId});

  @override
  ConsumerState<LorebookConnectionsSheet> createState() =>
      _LorebookConnectionsSheetState();
}

class _LorebookConnectionsSheetState
    extends ConsumerState<LorebookConnectionsSheet> {
  @override
  Widget build(BuildContext context) {
    final lorebooks = ref.watch(lorebooksProvider).value ?? [];
    final lb = lorebooks.where((l) => l.id == widget.lorebookId).firstOrNull;
    if (lb == null) return const SizedBox.shrink();

    final activations = ref.watch(lorebookActivationsProvider);
    final charIds = activations.character.entries
        .where((e) => e.value.contains(lb.id))
        .map((e) => e.key)
        .toList();
    final chatIds = activations.chat.entries
        .where((e) => e.value.contains(lb.id))
        .map((e) => e.key)
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Connections: ${lb.name}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Text('Scope:', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              _ScopeChip(
                label: 'global',
                selected: lb.enabled,
                color: Colors.green,
              ),
              const SizedBox(width: 6),
              _ScopeChip(
                label: 'character',
                selected: charIds.isNotEmpty,
                color: Colors.purple,
              ),
              const SizedBox(width: 6),
              _ScopeChip(
                label: 'chat',
                selected: chatIds.isNotEmpty,
                color: Colors.orange,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        _Section(
          icon: Icons.public,
          title: 'Global',
          child: _ToggleRow(
            label: 'Enabled for all chats',
            value: lb.enabled,
            onChanged: (v) {
              final notifier = ref.read(lorebooksProvider.notifier);
              notifier.updateLorebook(lb.copyWith(enabled: v));
            },
          ),
        ),

        _Section(
          icon: Icons.person,
          title: 'Characters',
          onAdd: () => _addCharacterConnection(lb),
          child: charIds.isEmpty
              ? const _EmptyHint('Not bound to any character')
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: charIds
                      .map(
                        (id) => _ConnectionChip(
                          id: id,
                          futureLabel: _charName(id),
                          onRemove: () =>
                              _toggleActivation(lb.id, 'character', id),
                        ),
                      )
                      .toList(),
                ),
        ),

        _Section(
          icon: Icons.chat,
          title: 'Chats',
          onAdd: () => _addChatConnection(lb),
          child: chatIds.isEmpty
              ? const _EmptyHint('Not bound to any chat')
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: chatIds
                      .map(
                        (id) => _ConnectionChip(
                          id: id,
                          futureLabel: Future.value(id),
                          onRemove: () => _toggleActivation(lb.id, 'chat', id),
                        ),
                      )
                      .toList(),
                ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  Future<String> _charName(String id) async {
    final chars = ref.read(charactersProvider).value ?? [];
    final c = chars.where((c) => c.id == id).firstOrNull;
    return c?.name ?? id;
  }

  void _toggleActivation(String lbId, String scope, String targetId) {
    final current = ref.read(lorebookActivationsProvider);
    final map = scope == 'character'
        ? Map<String, List<String>>.from(current.character)
        : Map<String, List<String>>.from(current.chat);

    final list = List<String>.from(map[targetId] ?? []);
    if (list.contains(lbId)) {
      list.remove(lbId);
    } else {
      list.add(lbId);
    }
    if (list.isEmpty) {
      map.remove(targetId);
    } else {
      map[targetId] = list;
    }

    final updated = scope == 'character'
        ? current.copyWith(character: map)
        : current.copyWith(chat: map);
    ref.read(lorebookActivationsProvider.notifier).state = updated;
    saveLorebookActivations(updated);
  }

  void _addCharacterConnection(Lorebook lb) async {
    final chars = ref.read(charactersProvider).value ?? [];
    final activations = ref.read(lorebookActivationsProvider);
    final existingIds = activations.character.entries
        .where((e) => e.value.contains(lb.id))
        .map((e) => e.key)
        .toSet();

    final available = chars.where((c) => !existingIds.contains(c.id)).toList();
    if (available.isEmpty) {
      GlazeToast.show(context, 'All characters already connected');
      return;
    }

    final selected = await showDialog<Character>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add Character'),
        children: available
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c),
                child: Text(c.name),
              ),
            )
            .toList(),
      ),
    );

    if (selected != null) {
      _toggleActivation(lb.id, 'character', selected.id);
    }
  }

  void _addChatConnection(Lorebook lb) async {
    GlazeToast.show(
      context,
      'Chat binding: open a chat first, then bind from there',
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onAdd;
  final Widget child;

  const _Section({
    required this.icon,
    required this.title,
    this.onAdd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (onAdd != null)
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: onAdd,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.accent,
        ),
      ],
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final String id;
  final Future<String> futureLabel;
  final VoidCallback onRemove;

  const _ConnectionChip({
    required this.id,
    required this.futureLabel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: FutureBuilder<String>(
        future: futureLabel,
        builder: (_, snap) =>
            Text(snap.data ?? id, style: const TextStyle(fontSize: 12)),
      ),
      deleteIcon: const Icon(Icons.close, size: 14),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: AppColors.textSecondary.withValues(alpha: 0.6),
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;

  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? color : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? color : AppColors.textSecondary,
        ),
      ),
    );
  }
}

void showLorebookConnections(BuildContext context, String lorebookId) {
  GlazeBottomSheet.show(
    context,
    child: LorebookConnectionsSheet(lorebookId: lorebookId),
  );
}
