import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/models/character.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/lorebook_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/sheet_view.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/generic_editor.dart';

class CharacterEditorScreen extends ConsumerStatefulWidget {
  final String charId;
  final bool isNew;
  const CharacterEditorScreen({super.key, required this.charId, this.isNew = false});

  @override
  ConsumerState<CharacterEditorScreen> createState() =>
      _CharacterEditorScreenState();
}

class _CharacterEditorScreenState extends ConsumerState<CharacterEditorScreen> {
  bool _loading = true;
  Character? _original;
  Map<String, dynamic> _item = {};
  List<String> _lorebookNames = [];
  late final _repo = ref.read(characterRepoProvider);
  late final String _effectiveId = widget.isNew ? generateId() : widget.charId;

  @override
  void initState() {
    super.initState();
    if (widget.isNew) {
      _item = {
        'name': '',
        'description': '',
        'personality': '',
        'scenario': '',
        'first_mes': '',
        'alternate_greetings': <String>[],
        'mes_example': '',
        'system_prompt': '',
        'post_history_instructions': '',
        'creator': '',
        'creator_notes': '',
        'tags': <String>[],
        'avatarPath': null,
        'depth_prompt': '',
        'depth_prompt_depth': 4,
        'depth_prompt_role': 'system',
        'world': null,
        'talkativeness': 1.0,
      };
      _loading = false;
    } else {
      _loadCharacter();
    }
  }

  Future<void> _loadLorebookNames() async {
    final lorebooks = await ref.read(lorebooksProvider.future);
    if (mounted) {
      setState(() {
        _lorebookNames = lorebooks.map((lb) => lb.name).toList()..sort();
      });
    }
  }

  Future<void> _loadCharacter() async {
    final char = await _repo.getById(widget.charId);
    if (char != null && mounted) {
      _original = char;
      _item = {
        'name': char.name,
        'description': char.description ?? '',
        'personality': char.personality ?? '',
        'scenario': char.scenario ?? '',
        'first_mes': char.firstMes ?? '',
        'alternate_greetings': List<String>.from(char.alternateGreetings),
        'mes_example': char.mesExample ?? '',
        'system_prompt': char.systemPrompt ?? '',
        'post_history_instructions': char.postHistoryInstructions ?? '',
        'creator': char.creator ?? '',
        'creator_notes': char.creatorNotes ?? '',
        'tags': List<String>.from(char.tags),
        'avatarPath': char.avatarPath,
        'depth_prompt': char.depthPrompt,
        'depth_prompt_depth': char.depthPromptDepth,
        'depth_prompt_role': char.depthPromptRole,
        'world': char.world,
        'talkativeness': char.extensions['talkativeness'] ?? 1.0,
      };
      setState(() => _loading = false);
      _loadLorebookNames();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/characters');
    }
  }

  void _saveAndClose() {
    if ((_item['name'] as String?)?.trim().isEmpty ?? true) {
      GlazeToast.show(context, 'Enter a character name first');
      return;
    }
    _save(_item);
    _goBack();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.first.path;
    if (filePath == null) return;

    final bytes = await File(filePath).readAsBytes();
    final storage = await ref.read(imageStorageProvider.future);
    final savedPath = await storage.saveAvatar(_effectiveId, bytes);
    await FileImage(File(savedPath)).evict();
    if (mounted) {
      setState(() {
        _item['avatarPath'] = savedPath;
        _item = Map.from(_item); // Force update
      });
      _save(_item);
    }
  }

  Future<void> _save(Map<String, dynamic> item) async {
    if ((item['name'] as String?)?.trim().isEmpty ?? true) {
      return; // Do not auto-save if name is invalid
    }

    try {
      final tags = (item['tags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [];
      final alternateGreetings = (item['alternate_greetings'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [];

      final updated = Character(
        id: _effectiveId,
        name: (item['name'] as String).trim(),
        avatarPath: item['avatarPath'] as String?,
        description: (item['description'] as String?)?.trim().isEmpty ?? true
            ? null
            : (item['description'] as String).trim(),
        personality: (item['personality'] as String?)?.trim().isEmpty ?? true
            ? null
            : (item['personality'] as String).trim(),
        scenario: (item['scenario'] as String?)?.trim().isEmpty ?? true
            ? null
            : (item['scenario'] as String).trim(),
        firstMes: (item['first_mes'] as String?)?.trim().isEmpty ?? true
            ? null
            : (item['first_mes'] as String).trim(),
        mesExample: (item['mes_example'] as String?)?.trim().isEmpty ?? true
            ? null
            : (item['mes_example'] as String).trim(),
        systemPrompt: (item['system_prompt'] as String?)?.trim().isEmpty ?? true
            ? null
            : (item['system_prompt'] as String).trim(),
        postHistoryInstructions:
            (item['post_history_instructions'] as String?)?.trim().isEmpty ?? true
                ? null
                : (item['post_history_instructions'] as String).trim(),
        creator: (item['creator'] as String?)?.trim().isEmpty ?? true
            ? null
            : (item['creator'] as String).trim(),
        creatorNotes: (item['creator_notes'] as String?)?.trim().isEmpty ?? true
            ? null
            : (item['creator_notes'] as String).trim(),
        tags: tags,
        alternateGreetings: alternateGreetings,
        color: _original?.color,
        updatedAt: currentTimestampSeconds(),
        extensions: {
          ...?_original?.extensions,
          'talkativeness': item['talkativeness'] is num ? (item['talkativeness'] as num).toDouble() : 1.0,
        },
        fav: _original?.fav ?? false,
        depthPrompt: (item['depth_prompt'] as String?)?.trim() ?? '',
        depthPromptDepth: item['depth_prompt_depth'] as int? ?? 4,
        depthPromptRole: item['depth_prompt_role'] as String? ?? 'system',
        world: item['world'] as String?,
        characterVersion: _original?.characterVersion ?? '1',
      );

      await _repo.put(updated);
      final avatarPath = item['avatarPath'] as String?;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        await FileImage(File(avatarPath)).evict();
      }
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Save failed: ', e);
      }
    }
  }

  void _onOpenFsEditor(String field, int index) {
    if (field == 'first_mes') {
      _editGreeting(index);
    } else {
      _editExpandableField(field);
    }
  }

  void _editGreeting(int index) {
    final greetings = <String>[];
    final first = (_item['first_mes'] as String?) ?? '';
    greetings.add(first);
    final alt = _item['alternate_greetings'];
    if (alt is List) greetings.addAll(alt.cast<String>());
    if (index < 0 || index >= greetings.length) return;

    final ctrl = TextEditingController(text: greetings[index]);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text('Edit Greeting #${index + 1}'),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width * 0.8,
          child: TextField(
            controller: ctrl,
            maxLines: 12,
            autofocus: true,
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final newText = ctrl.text;
              if (index == 0) {
                _item['first_mes'] = newText;
              } else {
                final altList = (_item['alternate_greetings'] as List?)?.cast<String>().toList() ?? <String>[];
                if (index - 1 < altList.length) altList[index - 1] = newText;
                _item['alternate_greetings'] = altList;
              }
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editExpandableField(String field) {
    final ctrl = TextEditingController(text: (_item[field] as String?) ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text(field.replaceAll('_', ' ').replaceFirstMapped(RegExp(r'[a-z]'), (m) => m.group(0)!.toUpperCase())),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width * 0.8,
          child: TextField(
            controller: ctrl,
            maxLines: 16,
            autofocus: true,
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              _item[field] = ctrl.text;
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SheetView(
        title: 'Edit Character',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final config = [
      GenericEditorSection(
        title: null,
        fields: [
          const GenericEditorField(key: 'name', label: 'Name', type: 'text'),
          const GenericEditorField(key: 'creator', label: 'Creator', type: 'text'),
          const GenericEditorField(key: 'tags', label: 'Tags', type: 'tags', placeholder: 'tag1, tag2, tag3'),
        ],
      ),
      GenericEditorSection(
        title: 'Character',
        fields: [
          const GenericEditorField(key: 'description', label: 'Description', type: 'textarea', rows: 4, expandable: true),
          const GenericEditorField(key: 'personality', label: 'Personality', type: 'textarea', rows: 4, expandable: true),
          const GenericEditorField(key: 'scenario', label: 'Scenario', type: 'textarea', rows: 4, expandable: true),
        ],
      ),
      GenericEditorSection(
        title: 'First Message & Examples',
        fields: [
          const GenericEditorField(key: 'first_mes', label: 'First Message', type: 'greeting_list'),
          const GenericEditorField(key: 'mes_example', label: 'Example Messages', type: 'textarea', rows: 6, expandable: true),
        ],
      ),
      GenericEditorSection(
        title: 'Prompts',
        fields: [
          const GenericEditorField(key: 'system_prompt', label: 'System Prompt', type: 'textarea', rows: 6, expandable: true),
          const GenericEditorField(key: 'post_history_instructions', label: 'Post-History Instructions', type: 'textarea', rows: 4, expandable: true),
          const GenericEditorField(key: 'creator_notes', label: 'Short Description', type: 'textarea', rows: 3),
        ],
      ),
      GenericEditorSection(
        title: 'Advanced',
        fields: [
          const GenericEditorField(key: 'depth_prompt', label: 'Depth Prompt', type: 'textarea', rows: 4, placeholder: 'Injected at a specific depth in the prompt'),
          const GenericEditorField(
            key: 'depth_prompt_role',
            label: 'Depth Role',
            type: 'select',
            options: [
              {'label': 'System', 'value': 'system'},
              {'label': 'User', 'value': 'user'},
              {'label': 'Assistant', 'value': 'assistant'},
            ],
          ),
          GenericEditorField(
            key: 'depth_prompt_depth',
            label: 'Depth',
            type: 'select',
            options: List.generate(20, (i) => {'label': '${i + 1}', 'value': i + 1}),
          ),
          GenericEditorField(
            key: 'world',
            label: 'World Lorebook',
            type: 'select',
            options: [
              {'label': 'None', 'value': null},
              ..._lorebookNames.map((name) => {'label': name, 'value': name}),
            ],
          ),
          const GenericEditorField(key: 'talkativeness', label: 'Talkativeness (0.0 to 1.0)', type: 'number'),
        ],
      ),
    ];

    return SheetView(
      title: widget.isNew ? 'New Character' : 'Edit Character',
      showBack: true,
      onBack: _goBack,
      actions: widget.isNew
          ? [
              SheetViewAction(
                icon: const Icon(Icons.check_rounded, size: 20),
                tooltip: 'Save',
                onPressed: _saveAndClose,
              ),
            ]
          : const [],
      body: GenericEditor(
        item: _item,
        config: config,
        showAvatar: true,
        avatarField: 'avatarPath',
        avatarHint: 'Tap to change avatar',
        avatarPlaceholder: (_item['name']?.toString().isNotEmpty ?? false) ? _item['name'].toString()[0].toUpperCase() : '?',
        onAvatarTap: _pickAvatar,
        onChanged: (values) {
          _item = values;
        },
        onSave: widget.isNew ? null : _save,
        onOpenFsEditor: _onOpenFsEditor,
      ),
    );
  }
}

