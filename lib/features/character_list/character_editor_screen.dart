import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/models/character.dart';
import '../../core/state/db_provider.dart';
import '../../shared/widgets/glaze_scaffold.dart';

class CharacterEditorScreen extends ConsumerStatefulWidget {
  final String charId;
  const CharacterEditorScreen({super.key, required this.charId});

  @override
  ConsumerState<CharacterEditorScreen> createState() =>
      _CharacterEditorScreenState();
}

class _CharacterEditorScreenState extends ConsumerState<CharacterEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _nameCtrl = TextEditingController();
  late final _descCtrl = TextEditingController();
  late final _personalityCtrl = TextEditingController();
  late final _scenarioCtrl = TextEditingController();
  late final _firstMesCtrl = TextEditingController();
  late final _mesExampleCtrl = TextEditingController();
  late final _sysPromptCtrl = TextEditingController();
  late final _postHistoryCtrl = TextEditingController();
  late final _creatorCtrl = TextEditingController();
  late final _creatorNotesCtrl = TextEditingController();
  late final _tagsCtrl = TextEditingController();

  String? _avatarPath;
  bool _loading = true;
  bool _saving = false;
  Character? _original;

  @override
  void initState() {
    super.initState();
    _loadCharacter();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _personalityCtrl.dispose();
    _scenarioCtrl.dispose();
    _firstMesCtrl.dispose();
    _mesExampleCtrl.dispose();
    _sysPromptCtrl.dispose();
    _postHistoryCtrl.dispose();
    _creatorCtrl.dispose();
    _creatorNotesCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCharacter() async {
    final char = await ref.read(characterRepoProvider).getById(widget.charId);
    if (char != null && mounted) {
      _original = char;
      _nameCtrl.text = char.name;
      _descCtrl.text = char.description ?? '';
      _personalityCtrl.text = char.personality ?? '';
      _scenarioCtrl.text = char.scenario ?? '';
      _firstMesCtrl.text = char.firstMes ?? '';
      _mesExampleCtrl.text = char.mesExample ?? '';
      _sysPromptCtrl.text = char.systemPrompt ?? '';
      _postHistoryCtrl.text = char.postHistoryInstructions ?? '';
      _creatorCtrl.text = char.creator ?? '';
      _creatorNotesCtrl.text = char.creatorNotes ?? '';
      _tagsCtrl.text = char.tags.join(', ');
      _avatarPath = char.avatarPath;
      setState(() => _loading = false);
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const GlazeScaffold(
        title: 'Edit Character',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return GlazeScaffold(
      title: 'Edit Character',
      onBack: () => context.go('/character/${widget.charId}'),
      actions: [
        if (_saving)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
      ],
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: _buildAvatarPicker()),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.label),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _creatorCtrl,
              decoration: const InputDecoration(
                labelText: 'Creator',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tagsCtrl,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'tag1, tag2, tag3',
                prefixIcon: Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: 20),
            _SectionHeader('Character'),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 4,
              minLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _personalityCtrl,
              decoration: const InputDecoration(labelText: 'Personality'),
              maxLines: 4,
              minLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _scenarioCtrl,
              decoration: const InputDecoration(labelText: 'Scenario'),
              maxLines: 4,
              minLines: 2,
            ),
            const SizedBox(height: 20),
            _SectionHeader('First Message & Examples'),
            TextFormField(
              controller: _firstMesCtrl,
              decoration: const InputDecoration(labelText: 'First Message'),
              maxLines: 6,
              minLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mesExampleCtrl,
              decoration: const InputDecoration(labelText: 'Example Messages'),
              maxLines: 6,
              minLines: 2,
            ),
            const SizedBox(height: 20),
            _SectionHeader('Prompts'),
            TextFormField(
              controller: _sysPromptCtrl,
              decoration: const InputDecoration(labelText: 'System Prompt'),
              maxLines: 6,
              minLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _postHistoryCtrl,
              decoration: const InputDecoration(
                labelText: 'Post-History Instructions',
              ),
              maxLines: 4,
              minLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _creatorNotesCtrl,
              decoration: const InputDecoration(labelText: 'Creator Notes'),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return GestureDetector(
      onTap: _pickAvatar,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 56,
            backgroundImage: _avatarPath != null && _avatarPath!.isNotEmpty
                ? FileImage(File(_avatarPath!))
                : null,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: _avatarPath == null || _avatarPath!.isEmpty
                ? Text(
                    _nameCtrl.text.isNotEmpty
                        ? _nameCtrl.text[0].toUpperCase()
                        : '?',
                    style: const TextStyle(fontSize: 36),
                  )
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt,
                size: 20,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    final storage = ref.read(imageStorageProvider);
    final savedPath = await storage.saveAvatar(widget.charId, file.bytes!);
    if (mounted) {
      setState(() => _avatarPath = savedPath);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final tags = _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final updated = Character(
        id: widget.charId,
        name: _nameCtrl.text.trim(),
        avatarPath: _avatarPath,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        personality: _personalityCtrl.text.trim().isEmpty
            ? null
            : _personalityCtrl.text.trim(),
        scenario: _scenarioCtrl.text.trim().isEmpty
            ? null
            : _scenarioCtrl.text.trim(),
        firstMes: _firstMesCtrl.text.trim().isEmpty
            ? null
            : _firstMesCtrl.text.trim(),
        mesExample: _mesExampleCtrl.text.trim().isEmpty
            ? null
            : _mesExampleCtrl.text.trim(),
        systemPrompt: _sysPromptCtrl.text.trim().isEmpty
            ? null
            : _sysPromptCtrl.text.trim(),
        postHistoryInstructions: _postHistoryCtrl.text.trim().isEmpty
            ? null
            : _postHistoryCtrl.text.trim(),
        creator: _creatorCtrl.text.trim().isEmpty
            ? null
            : _creatorCtrl.text.trim(),
        creatorNotes: _creatorNotesCtrl.text.trim().isEmpty
            ? null
            : _creatorNotesCtrl.text.trim(),
        tags: tags,
        alternateGreetings: _original?.alternateGreetings ?? [],
        color: _original?.color,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await ref.read(characterRepoProvider).put(updated);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Character saved')));
        context.go('/character/${widget.charId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
