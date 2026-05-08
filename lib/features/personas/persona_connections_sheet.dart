import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/persona.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/theme/app_colors.dart';

class PersonaConnectionsSheet extends ConsumerStatefulWidget {
  final String personaId;
  const PersonaConnectionsSheet({super.key, required this.personaId});

  @override
  ConsumerState<PersonaConnectionsSheet> createState() =>
      _PersonaConnectionsSheetState();
}

class _PersonaConnectionsSheetState
    extends ConsumerState<PersonaConnectionsSheet> {
  @override
  Widget build(BuildContext context) {
    final personas = ref.watch(personaRepoProvider);
    final personaAsync = personas.getAll();
    final connections = ref.watch(personaConnectionsProvider);
    final activePersonaId = ref.watch(activePersonaIdProvider);
    final isGlobal = activePersonaId == widget.personaId;

    final charIds = connections.character.entries
        .where((e) => e.value == widget.personaId)
        .map((e) => e.key)
        .toList();
    final chatIds = connections.chat.entries
        .where((e) => e.value == widget.personaId)
        .map((e) => e.key)
        .toList();

    return FutureBuilder<List<Persona>>(
      future: personaAsync,
      builder: (context, snap) {
        final persona = snap.data
                ?.where((p) => p.id == widget.personaId)
                .firstOrNull ??
            Persona(id: widget.personaId, name: 'Persona');

        return Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
                top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Connections: ${persona.name}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              const Divider(height: 1),

              _Section(
                icon: Icons.public,
                title: 'Global',
                child: _ToggleRow(
                  label: 'Active for all chats (fallback)',
                  value: isGlobal,
                  onChanged: (v) {
                    setActivePersona(ref, v ? widget.personaId : null);
                  },
                ),
              ),

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
                                  onRemove: () => setPersonaConnection(
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
                                  onRemove: () => setPersonaConnection(
                                    ref, 'chat', id, null,
                                  ),
                                ))
                            .toList(),
                      ),
              ),

              const SizedBox(height: 24),
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
    final sessions = await ref.read(chatRepoProvider).getAllSessions();
    final s = sessions.where((s) => s.id == sessionId).firstOrNull;
    if (s == null) return sessionId;
    final chars = ref.read(charactersProvider).value ?? [];
    final char = chars.where((c) => c.id == s.characterId).firstOrNull;
    return '${char?.name ?? s.characterId} #${s.sessionIndex}';
  }

  void _addCharacterConnection() async {
    final chars = ref.read(charactersProvider).value ?? [];
    final connections = ref.read(personaConnectionsProvider);
    final existingIds = connections.character.entries
        .where((e) => e.value == widget.personaId)
        .map((e) => e.key)
        .toSet();

    final available =
        chars.where((c) => !existingIds.contains(c.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All characters already connected')));
      return;
    }

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bind to Character'),
        children: available
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text(c.name),
                ))
            .toList(),
      ),
    );

    if (selected != null) {
      setPersonaConnection(ref, 'character', selected.id, widget.personaId);
    }
  }

  void _addChatConnection() async {
    final sessions = await ref.read(chatRepoProvider).getAllSessions();
    final connections = ref.read(personaConnectionsProvider);
    final existingIds = connections.chat.entries
        .where((e) => e.value == widget.personaId)
        .map((e) => e.key)
        .toSet();

    final available =
        sessions.where((s) => !existingIds.contains(s.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No unbound chat sessions')));
      return;
    }

    final chars = ref.read(charactersProvider).value ?? [];

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bind to Chat'),
        children: available
            .map((s) {
          final char = chars.where((c) => c.id == s.characterId).firstOrNull;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, s),
            child:
                Text('${char?.name ?? s.characterId} #${s.sessionIndex}'),
          );
        }).toList(),
      ),
    );

    if (selected != null) {
      setPersonaConnection(ref, 'chat', selected.id, widget.personaId);
    }
  }
}

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
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
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

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary))),
        Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent),
      ],
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
            color: AppColors.textSecondary.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic));
  }
}

void showPersonaConnections(BuildContext context, String personaId) {
  GlazeBottomSheet.show(
    context,
    child: PersonaConnectionsSheet(personaId: personaId),
  );
}
