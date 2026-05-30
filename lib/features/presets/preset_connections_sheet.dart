import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/preset.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/chat_session_ops_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/sheet_view.dart';
import 'preset_list_provider.dart';

class PresetConnectionsSheet extends ConsumerStatefulWidget {
  final String presetId;
  const PresetConnectionsSheet({super.key, required this.presetId});

  @override
  ConsumerState<PresetConnectionsSheet> createState() =>
      _PresetConnectionsSheetState();
}

class _PresetConnectionsSheetState
    extends ConsumerState<PresetConnectionsSheet> {
  @override
  Widget build(BuildContext context) {
    final presetsAsync = ref.watch(presetListProvider);
    final connections = ref.watch(presetConnectionsProvider);

    final charIds = connections.character.entries
        .where((e) => e.value == widget.presetId)
        .map((e) => e.key)
        .toList();
    final chatIds = connections.chat.entries
        .where((e) => e.value == widget.presetId)
        .map((e) => e.key)
        .toList();

    return presetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (presets) {
        final preset = presets.where((p) => p.id == widget.presetId).firstOrNull
            ?? Preset(id: widget.presetId, name: 'Preset');

        return SheetView(
          title: 'Connections: ${preset.name}',
          showBack: true,
          fitContent: true,
          body: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 4,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _Section(
                icon: Icons.person,
                title: 'Characters',
                onAdd: () => _addCharacterConnection(),
                child: charIds.isEmpty
                    ? const _EmptyHint('Not bound to any character')
                    : Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: charIds
                            .map((id) => _ConnectionChip(
                                  id: id,
                                  futureLabel: _charName(id),
                                  onRemove: () => setPresetConnection(
                                    ref, 'character', id, null,
                                  ),
                                ))
                            .toList(),
                      ),
              ),
              _Section(
                icon: Icons.chat,
                title: 'Chats',
                onAdd: () => _addChatConnection(),
                child: chatIds.isEmpty
                    ? const _EmptyHint('Not bound to any chat')
                    : Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: chatIds
                            .map((id) => _ConnectionChip(
                                  id: id,
                                  futureLabel: _chatLabel(id),
                                  onRemove: () => setPresetConnection(
                                    ref, 'chat', id, null,
                                  ),
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
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

  void _addCharacterConnection() async {
    final chars = ref.read(charactersProvider).value ?? [];
    final connections = ref.read(presetConnectionsProvider);
    final existingIds = connections.character.entries
        .where((e) => e.value == widget.presetId)
        .map((e) => e.key)
        .toSet();

    final available = chars.where((c) => !existingIds.contains(c.id)).toList();
    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All characters already connected')));
      }
      return;
    }

    final selected = await GlazeBottomSheet.show<dynamic>(
      context,
      title: 'Bind to Character',
      items: available
          .map((c) => BottomSheetItem(
                label: c.name,
                onTap: () => Navigator.of(context, rootNavigator: true).pop(c),
              ))
          .toList(),
    );

    if (selected != null) {
      setPresetConnection(ref, 'character', selected.id as String, widget.presetId);
    }
  }

  void _addChatConnection() async {
    final sessions = ref.read(chatSessionOpsProvider).value ?? [];
    final connections = ref.read(presetConnectionsProvider);
    final existingIds = connections.chat.entries
        .where((e) => e.value == widget.presetId)
        .map((e) => e.key)
        .toSet();

    final available = sessions.where((s) => !existingIds.contains(s.id)).toList();
    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No unbound chat sessions')));
      }
      return;
    }

    final chars = ref.read(charactersProvider).value ?? [];

    final selected = await GlazeBottomSheet.show<ChatSession>(
      context,
      title: 'Bind to Chat',
      items: available.map((s) {
        final char = chars.where((c) => c.id == s.characterId).firstOrNull;
        return BottomSheetItem(
          label: '${char?.name ?? s.characterId} #${s.sessionIndex}',
          onTap: () => Navigator.of(context, rootNavigator: true).pop(s),
        );
      }).toList(),
    );

    if (selected != null) {
      setPresetConnection(ref, 'chat', selected.id, widget.presetId);
    }
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onAdd;
  final Widget child;

  const _Section(
      {required this.icon, required this.title, this.onAdd, required this.child});

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
              Text(title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.cs.onSurfaceVariant)),
              const Spacer(),
              if (onAdd != null)
                IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: onAdd,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints()),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final String id;
  final Future<String> futureLabel;
  final VoidCallback onRemove;

  const _ConnectionChip(
      {required this.id, required this.futureLabel, required this.onRemove});

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
    return Text(text,
        style: TextStyle(
            fontSize: 12,
            color: context.cs.onSurfaceVariant.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic));
  }
}

void showPresetConnections(BuildContext context, String presetId) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PresetConnectionsSheet(presetId: presetId),
  );
}
