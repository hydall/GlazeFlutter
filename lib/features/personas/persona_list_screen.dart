import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/persona.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';

final personaListProvider =
    AsyncNotifierProvider<PersonaListNotifier, List<Persona>>(
      PersonaListNotifier.new,
    );

class PersonaListNotifier extends AsyncNotifier<List<Persona>> {
  @override
  Future<List<Persona>> build() async {
    return ref.watch(personaRepoProvider).getAll();
  }

  Future<void> add(Persona persona) async {
    await ref.read(personaRepoProvider).put(persona);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(personaRepoProvider).delete(id);
    ref.invalidateSelf();
  }
}

class PersonaListScreen extends ConsumerWidget {
  const PersonaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personaListProvider);

    return GlazeScaffold(
      title: 'Personas',
      onBack: () => context.go('/tools'),
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          color: AppColors.accent,
          onPressed: () => _showEditor(context, ref),
        ),
      ],
      body: personas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No personas yet'),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => _showEditor(context, ref),
                      child: const Text('Create Persona'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _PersonaTile(persona: list[i]),
              ),
      ),
    );
  }

  void _showEditor(BuildContext context, WidgetRef ref, [Persona? existing]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PersonaEditorScreen(existing: existing),
      ),
    );
  }
}

class _PersonaTile extends ConsumerWidget {
  final Persona persona;
  const _PersonaTile({required this.persona});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      visualDensity: VisualDensity.compact,
      leading: CircleAvatar(
        radius: 14,
        child: Text(
          persona.name.isNotEmpty ? persona.name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      title: Text(persona.name),
      subtitle: persona.prompt != null && persona.prompt!.isNotEmpty
          ? Text(persona.prompt!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _PersonaEditorScreen(existing: persona),
              ),
            );
          } else if (value == 'delete') {
            ref.read(personaListProvider.notifier).remove(persona.id);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

class _PersonaEditorScreen extends ConsumerStatefulWidget {
  final Persona? existing;
  const _PersonaEditorScreen({this.existing});

  @override
  ConsumerState<_PersonaEditorScreen> createState() =>
      _PersonaEditorScreenState();
}

class _PersonaEditorScreenState extends ConsumerState<_PersonaEditorScreen> {
  late final _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _promptCtrl = TextEditingController(
    text: widget.existing?.prompt ?? '',
  );
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _avatarPath = widget.existing?.avatarPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.first.path;
    if (filePath == null) return;

    final id = widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final imageStorage = await ref.read(imageStorageProvider.future);
    final bytes = await File(filePath).readAsBytes();
    final savedPath = await imageStorage.saveAvatar('persona_$id', bytes);
    if (mounted) setState(() => _avatarPath = savedPath);
  }

  @override
  Widget build(BuildContext context) {
    return GlazeScaffold(
      title: widget.existing != null ? 'Edit Persona' : 'New Persona',
      onBack: () => Navigator.of(context).pop(),
      actions: [
        TextButton(
          onPressed: _save,
          child: const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                    backgroundImage: _avatarPath != null
                        ? FileImage(File(_avatarPath!))
                        : null,
                    child: _avatarPath == null
                        ? Icon(Icons.person, size: 40, color: AppColors.accent.withValues(alpha: 0.5))
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.background, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, size: 14, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Your persona name',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _promptCtrl,
            decoration: const InputDecoration(
              labelText: 'Persona Prompt',
              hintText:
                  'Describe your persona — this gets injected into the prompt',
              alignLabelWithHint: true,
            ),
            maxLines: 12,
            minLines: 4,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final persona = Persona(
      id:
          widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      name: name,
      prompt: _promptCtrl.text.trim().isEmpty ? null : _promptCtrl.text.trim(),
      avatarPath: _avatarPath,
    );

    await ref.read(personaRepoProvider).put(persona);
    ref.invalidate(personaListProvider);

    if (mounted) Navigator.of(context).pop();
  }
}
