import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/models/character.dart';
import '../../core/state/db_provider.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/lorebook_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/sheet_view.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/generic_editor.dart';

class CharacterEditorScreen extends ConsumerStatefulWidget {
  final String charId;
  const CharacterEditorScreen({super.key, required this.charId});

  @override
  ConsumerState<CharacterEditorScreen> createState() =>
      _CharacterEditorScreenState();
}

class _CharacterEditorScreenState extends ConsumerState<CharacterEditorScreen> {
  bool _loading = true;
  Character? _original;
  Map<String, dynamic> _item = {};
  List<String> _lorebookNames = [];
  Timer? _saveTimer;
  late final _repo = ref.read(characterRepoProvider);

  @override
  void initState() {
    super.initState();
    _loadCharacter();
  }

  @override
  void dispose() {
    _flushSave();
    super.dispose();
  }

  void _flushSave() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer?.cancel();
      _save();
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
    _flushSave();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/characters');
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.first.path;
    if (filePath == null) return;

    final bytes = await File(filePath).readAsBytes();
    final storage = await ref.read(imageStorageProvider.future);
    final savedPath = await storage.saveAvatar(widget.charId, bytes);
    await FileImage(File(savedPath)).evict();
    if (mounted) {
      setState(() {
        _item['avatarPath'] = savedPath;
        _item = Map.from(_item); // Force update
      });
      _scheduleSave();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _save();
    });
  }

  Future<void> _save() async {
    if ((_item['name'] as String?)?.trim().isEmpty ?? true) {
      return; // Do not auto-save if name is invalid
    }

    try {
      final tags = (_item['tags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [];
      final alternateGreetings = (_item['alternate_greetings'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [];

      final updated = Character(
        id: widget.charId,
        name: (_item['name'] as String).trim(),
        avatarPath: _item['avatarPath'] as String?,
        description: (_item['description'] as String?)?.trim().isEmpty ?? true
            ? null
            : (_item['description'] as String).trim(),
        personality: (_item['personality'] as String?)?.trim().isEmpty ?? true
            ? null
            : (_item['personality'] as String).trim(),
        scenario: (_item['scenario'] as String?)?.trim().isEmpty ?? true
            ? null
            : (_item['scenario'] as String).trim(),
        firstMes: (_item['first_mes'] as String?)?.trim().isEmpty ?? true
            ? null
            : (_item['first_mes'] as String).trim(),
        mesExample: (_item['mes_example'] as String?)?.trim().isEmpty ?? true
            ? null
            : (_item['mes_example'] as String).trim(),
        systemPrompt: (_item['system_prompt'] as String?)?.trim().isEmpty ?? true
            ? null
            : (_item['system_prompt'] as String).trim(),
        postHistoryInstructions:
            (_item['post_history_instructions'] as String?)?.trim().isEmpty ?? true
                ? null
                : (_item['post_history_instructions'] as String).trim(),
        creator: (_item['creator'] as String?)?.trim().isEmpty ?? true
            ? null
            : (_item['creator'] as String).trim(),
        creatorNotes: (_item['creator_notes'] as String?)?.trim().isEmpty ?? true
            ? null
            : (_item['creator_notes'] as String).trim(),
        tags: tags,
        alternateGreetings: alternateGreetings,
        color: _original?.color,
        updatedAt: currentTimestampSeconds(),
        extensions: {
          ...?_original?.extensions,
          'talkativeness': _item['talkativeness'] is num ? (_item['talkativeness'] as num).toDouble() : 1.0,
        },
        fav: _original?.fav ?? false,
        depthPrompt: (_item['depth_prompt'] as String?)?.trim() ?? '',
        depthPromptDepth: _item['depth_prompt_depth'] as int? ?? 4,
        depthPromptRole: _item['depth_prompt_role'] as String? ?? 'system',
        world: _item['world'] as String?,
        characterVersion: _original?.characterVersion ?? '1',
      );

      await _repo.put(updated);
      final avatarPath = _item['avatarPath'] as String?;
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
    // Left empty for now. Can be connected to a full-screen editor if needed.
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
      title: 'Edit Character',
      showBack: true,
      onBack: _goBack,
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
          _scheduleSave();
        },
        onOpenFsEditor: _onOpenFsEditor,
      ),
    );
  }
}

