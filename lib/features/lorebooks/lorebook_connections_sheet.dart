import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/character.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/lorebook.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/chat_session_ops_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../../shared/widgets/help_tip.dart';

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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${'header_connections'.tr()}: ${lb.name}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const HelpTip(term: 'connections'),
                ],
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
              Text(
                'lorebook_scope_label'.tr(),
                style: TextStyle(color: context.cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              _ScopeChip(
                label: 'level_global'.tr(),
                selected: lb.enabled,
                color: Colors.green,
              ),
              const SizedBox(width: 6),
              _ScopeChip(
                label: 'level_character'.tr(),
                selected: charIds.isNotEmpty,
                color: Colors.purple,
              ),
              const SizedBox(width: 6),
              _ScopeChip(
                label: 'level_chat'.tr(),
                selected: chatIds.isNotEmpty,
                color: Colors.orange,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        _Section(
          icon: Icons.public,
          title: 'label_global'.tr(),
          child: _ToggleRow(
            label: 'label_global_enabled'.tr(),
            value: lb.enabled,
            onChanged: (v) {
              final notifier = ref.read(lorebooksProvider.notifier);
              notifier.updateLorebook(lb.copyWith(enabled: v));
            },
          ),
        ),

        _Section(
          icon: Icons.person,
          title: 'lbc_section_characters'.tr(),
          onAdd: () => _addCharacterConnection(lb),
          child: charIds.isEmpty
              ? _EmptyHint('no_char_connections'.tr())
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
          title: 'lbc_section_chats'.tr(),
          onAdd: () => _addChatConnection(lb),
          child: chatIds.isEmpty
              ? _EmptyHint('no_chat_connections'.tr())
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: chatIds
                      .map(
                        (id) => _ConnectionChip(
                          id: id,
                          futureLabel: _chatLabel(id),
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

  Future<String> _chatLabel(String sessionId) async {
    final sessions = ref.read(chatSessionOpsProvider).value ?? [];
    final s = sessions.where((s) => s.id == sessionId).firstOrNull;
    if (s == null) return sessionId;
    final chars = ref.read(charactersProvider).value ?? [];
    final char = chars.where((c) => c.id == s.characterId).firstOrNull;
    return '${char?.name ?? s.characterId} #${s.sessionIndex}';
  }

  void _toggleActivation(String lbId, String scope, String targetId) {
    final current = ref.read(lorebookActivationsProvider);
    final map = scope == 'character'
        ? Map<String, List<String>>.from(current.character)
        : Map<String, List<String>>.from(current.chat);

    final list = List<String>.from(map[targetId] ?? []);
    final wasLinked = list.contains(lbId);
    if (wasLinked) {
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

    final lorebooks = ref.read(lorebooksProvider).value ?? [];
    final lb = lorebooks.where((l) => l.id == lbId).firstOrNull;
    if (lb != null) {
      final allLinked = scope == 'character'
          ? updated.character.entries
                .where((e) => e.value.contains(lbId))
                .map((e) => e.key)
                .toList()
          : updated.chat.entries
                .where((e) => e.value.contains(lbId))
                .map((e) => e.key)
                .toList();
      if (allLinked.isEmpty && !lb.enabled) {
        ref
            .read(lorebooksProvider.notifier)
            .updateLorebook(
              lb.copyWith(activationScope: 'global', activationTargetId: null),
            );
      } else if (allLinked.isNotEmpty) {
        ref
            .read(lorebooksProvider.notifier)
            .updateLorebook(
              lb.copyWith(
                activationScope: scope,
                activationTargetId: allLinked.first,
              ),
            );
      }
    }
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
      GlazeToast.show(context, 'lorebook_all_chars_connected'.tr());
      return;
    }

    final selected = await GlazeBottomSheet.show<Character>(
      context,
      title: 'lbc_add_character'.tr(),
      items: available
          .map(
            (c) => BottomSheetItem(
              label: c.name,
              onTap: () => Navigator.of(context, rootNavigator: true).pop(c),
            ),
          )
          .toList(),
    );

    if (selected != null) {
      _toggleActivation(lb.id, 'character', selected.id);
    }
  }

  void _addChatConnection(Lorebook lb) async {
    final sessions = ref.read(chatSessionOpsProvider).value ?? [];
    final activations = ref.read(lorebookActivationsProvider);
    final existingIds = activations.chat.entries
        .where((e) => e.value.contains(lb.id))
        .map((e) => e.key)
        .toSet();

    final available = sessions
        .where((s) => !existingIds.contains(s.id))
        .toList();
    if (available.isEmpty) {
      GlazeToast.show(context, 'lorebook_no_unbound_chats'.tr());
      return;
    }

    final chars = ref.read(charactersProvider).value ?? [];

    final selected = await GlazeBottomSheet.show<ChatSession>(
      context,
      title: 'lbc_add_chat'.tr(),
      items: available.map((s) {
        final char = chars.where((c) => c.id == s.characterId).firstOrNull;
        return BottomSheetItem(
          label: '${char?.name ?? s.characterId} #${s.sessionIndex}',
          onTap: () => Navigator.of(context, rootNavigator: true).pop(s),
        );
      }).toList(),
    );

    if (selected != null) {
      _toggleActivation(lb.id, 'chat', selected.id);
    }
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
              Icon(icon, size: 16, color: context.cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.cs.onSurfaceVariant,
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
          style: TextStyle(fontSize: 14, color: context.cs.onSurface),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: context.cs.primary,
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
        color: context.cs.onSurfaceVariant.withValues(alpha: 0.6),
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
          color: selected ? color : context.cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

void showLorebookConnections(BuildContext context, String lorebookId) {
  GlazeBottomSheet.show<void>(
    context,
    child: LorebookConnectionsSheet(lorebookId: lorebookId),
  );
}
