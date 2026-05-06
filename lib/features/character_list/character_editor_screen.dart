import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/models/character.dart';
import '../../core/services/character_exporter.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
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
        PopupMenuButton<String>(
          icon: const Icon(Icons.share_outlined, color: AppColors.accent),
          onSelected: (value) => _export(value),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'png', child: Text('Export as PNG')),
            const PopupMenuItem(value: 'json', child: Text('Export as JSON')),
          ],
        ),
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

    final storage = await ref.read(imageStorageProvider.future);
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

  Future<void> _export(String format) async {
    final char = _original;
    if (char == null) return;

    try {
      final desktop = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
      final outputDir = p.join(desktop, 'Desktop');

      if (format == 'png') {
        Uint8List? avatarBytes;
        if (char.avatarPath != null && File(char.avatarPath!).existsSync()) {
          avatarBytes = await File(char.avatarPath!).readAsBytes();
        } else {
          avatarBytes = _generatePlaceholderAvatar(char.name);
        }

        final result = await exportCharacterAsPng(
          character: char,
          avatarBytes: avatarBytes,
          outputDir: outputDir,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported PNG to ${result.filePath}')),
          );
        }
      } else {
        final result = await exportCharacterAsJson(
          character: char,
          outputDir: outputDir,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported JSON to ${result.filePath}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Uint8List _generatePlaceholderAvatar(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final width = 400, height = 600;

    final pngHeader = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ];

    final ihdrData = ByteData(13);
    ihdrData.setUint32(0, width, Endian.big);
    ihdrData.setUint32(4, height, Endian.big);
    ihdrData.setUint8(8, 8);
    ihdrData.setUint8(9, 2);
    ihdrData.setUint8(10, 0);
    ihdrData.setUint8(11, 0);
    ihdrData.setUint8(12, 0);

    final ihdrChunk = _buildPngChunk('IHDR', ihdrData.buffer.asUint8List());

    final rawRow = Uint8List(1 + width * 3);
    for (int x = 0; x < width; x++) {
      rawRow[1 + x * 3] = 0x40;
      rawRow[1 + x * 3 + 1] = 0xCC;
      rawRow[1 + x * 3 + 2] = 0xFF;
    }

    final rawData = Uint8List(height * rawRow.length);
    for (int y = 0; y < height; y++) {
      rawData.setRange(y * rawRow.length, (y + 1) * rawRow.length, rawRow);
    }

    final iendChunk = _buildPngChunk('IEND', Uint8List(0));

    final totalLen = pngHeader.length + ihdrChunk.length + iendChunk.length + 100;
    final result = BytesBuilder();
    result.add(pngHeader);
    result.add(ihdrChunk);
    result.add(iendChunk);
    return result.toBytes();
  }

  Uint8List _buildPngChunk(String type, Uint8List data) {
    final typeBytes = Uint8List.fromList(utf8.encode(type));
    final chunk = ByteData(4 + 4 + data.length + 4);
    chunk.setUint32(0, data.length, Endian.big);
    for (int i = 0; i < 4; i++) chunk.setUint8(4 + i, typeBytes[i]);
    for (int i = 0; i < data.length; i++) chunk.setUint8(8 + i, data[i]);

    final crcInput = Uint8List(4 + data.length);
    for (int i = 0; i < 4; i++) crcInput[i] = typeBytes[i];
    crcInput.setRange(4, crcInput.length, data);
    final crc = _crc32(crcInput);
    chunk.setUint32(8 + data.length, crc, Endian.big);

    return chunk.buffer.asUint8List();
  }
}

int _crc32(Uint8List data) {
  int crc = 0xFFFFFFFF;
  for (int i = 0; i < data.length; i++) {
    crc ^= data[i];
    for (int j = 0; j < 8; j++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
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
