import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/preset.dart';
import '../../core/services/preset_defaults.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import 'preset_list_provider.dart';
import 'widgets/widgets.dart';

/// Standalone screen wrapper around [PresetEditorBody].
class PresetEditorScreen extends StatefulWidget {
  final Preset? preset;
  const PresetEditorScreen({super.key, this.preset});

  @override
  State<PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends State<PresetEditorScreen> {
  final _editorKey = GlobalKey<PresetEditorBodyState>();

  @override
  Widget build(BuildContext context) {
    return GlazeScaffold(
      title: widget.preset != null ? 'Edit Preset' : 'New Preset',
      onBack: () => Navigator.of(context).pop(),
      actions: [
        TextButton(
          onPressed: () => _editorKey.currentState?.save(),
          child: const Text(
            'Save',
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      body: PresetEditorBody(
        key: _editorKey,
        preset: widget.preset,
        onSaved: (_) => Navigator.of(context).pop(),
        onDeleted: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// Embeddable preset editor body — no scaffold, no navigation chrome.
/// Expose [PresetEditorBodyState.save] via a [GlobalKey] to trigger save
/// from an outer widget (e.g. a [SheetView] header action).
class PresetEditorBody extends ConsumerStatefulWidget {
  final Preset? preset;
  final void Function(Preset) onSaved;
  final VoidCallback? onDeleted;

  const PresetEditorBody({
    super.key,
    this.preset,
    required this.onSaved,
    this.onDeleted,
  });

  @override
  ConsumerState<PresetEditorBody> createState() => PresetEditorBodyState();
}

class PresetEditorBodyState extends ConsumerState<PresetEditorBody> {
  late final _nameCtrl =
      TextEditingController(text: widget.preset?.name ?? '');
  late String _author = widget.preset?.author ?? '';
  late List<PresetBlock> _blocks;
  late List<PresetRegex> _regexes;
  late bool _parseInlineReasoning = widget.preset?.reasoningEnabled ?? false;
  late final _reasoningStartCtrl =
      TextEditingController(text: widget.preset?.reasoningStart ?? '');
  late final _reasoningEndCtrl =
      TextEditingController(text: widget.preset?.reasoningEnd ?? '');
  late bool _mergePrompts = widget.preset?.mergePrompts ?? false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _blocks = List.from(widget.preset?.blocks ?? defaultPresetBlocks());
    _regexes = List.from(widget.preset?.regexes ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _reasoningStartCtrl.dispose();
    _reasoningEndCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDashboard(),
          _buildAdvancedToggle(),
          if (_showAdvanced) _buildAdvancedPanel(),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  // ─── Dashboard card ──────────────────────────────────────────────────────

  Widget _buildDashboard() {
    final displayName =
        _nameCtrl.text.trim().isEmpty ? 'New Preset' : _nameCtrl.text.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: name + author + three-dot menu
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showRenameDialog,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (_author.isNotEmpty)
                            Text(
                              'by $_author',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color:
                                    AppColors.accent.withValues(alpha: 0.8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                _DotsButton(onTap: _showOptionsMenu),
              ],
            ),
          ),
          // Utils row: regex button | spacer | block count badge
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Row(
              children: [
                _UtilButton(
                  icon: Icons.code,
                  count: _regexes.length,
                  onTap: _showRegexSheet,
                ),
                const Spacer(),
                _BlocksBadge(count: _blocks.length),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Reorderable block list
          if (_blocks.isNotEmpty) _buildBlockList(),
          // Add block row
          _AddBlockRow(onTap: _addBlock),
        ],
      ),
    );
  }

  Widget _buildBlockList() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: _blocks.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _blocks.removeAt(oldIndex);
          _blocks.insert(newIndex, item);
        });
      },
      itemBuilder: (_, i) => _BlockRow(
        key: ValueKey(_blocks[i].id),
        block: _blocks[i],
        index: i,
        isLast: i == _blocks.length - 1,
        onEdit: () => _editBlockAt(i),
        onToggle: (v) =>
            setState(() => _blocks[i] = _blocks[i].copyWith(enabled: v)),
      ),
    );
  }

  // ─── Advanced settings ───────────────────────────────────────────────────

  Widget _buildAdvancedToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Text(
              'Advanced Settings',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: _showAdvanced ? 0.5 : 0,
              duration: const Duration(milliseconds: 300),
              child: const Icon(
                Icons.expand_more,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Preset Name'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration('Name'),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Author'),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: _author,
            onChanged: (v) => _author = v,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _inputDecoration('Author (optional)'),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Reasoning'),
          const SizedBox(height: 8),
          _SettingsToggle(
            label: 'Parse Inline Reasoning',
            description: 'Extract reasoning tags from model output',
            value: _parseInlineReasoning,
            onChanged: (v) =>
                setState(() => _parseInlineReasoning = v),
          ),
          if (_parseInlineReasoning) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reasoningStartCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: _inputDecoration('<think>'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _reasoningEndCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: _inputDecoration('</think>'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          const _SectionLabel('Post-processing'),
          const SizedBox(height: 8),
          _SettingsToggle(
            label: 'Merge Prompts',
            description: 'Combine adjacent blocks into one message',
            value: _mergePrompts,
            onChanged: (v) => setState(() => _mergePrompts = v),
          ),
        ],
      ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  void _addBlock() {
    setState(() {
      _blocks.add(PresetBlock(
        id: generateId(),
        name: 'Block ${_blocks.length + 1}',
        role: 'system',
        content: '',
      ));
    });
  }

  void _editBlockAt(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => _BlockEditorSheet(
          block: _blocks[index],
          scrollController: scrollCtrl,
          onSave: (updated) {
            setState(() => _blocks[index] = updated);
            Navigator.pop(ctx);
          },
          onDelete: () {
            setState(() => _blocks.removeAt(index));
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _nameCtrl.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Rename Preset',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: _inputDecoration('Preset name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _nameCtrl.text = ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text(
              'Rename',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  size: 20, color: AppColors.textPrimary),
              title: const Text('Rename',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog();
              },
            ),
            if (widget.preset != null)
              ListTile(
                leading: const Icon(Icons.delete_outlined,
                    size: 20, color: Color(0xFFFF4444)),
                title: const Text('Delete',
                    style: TextStyle(color: Color(0xFFFF4444))),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(presetListProvider.notifier)
                      .remove(widget.preset!.id);
                  widget.onDeleted?.call();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRegexSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => _RegexSheet(
          regexes: _regexes,
          scrollController: scrollCtrl,
          onChanged: (list) => setState(() => _regexes = list),
        ),
      ),
    );
  }

  Future<void> save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a preset name')),
      );
      return;
    }
    final preset = Preset(
      id: widget.preset?.id ??
          generateId(),
      name: name,
      author: _author.trim().isEmpty ? null : _author.trim(),
      blocks: _blocks,
      regexes: _regexes,
      reasoningEnabled: _parseInlineReasoning,
      reasoningStart: _parseInlineReasoning ? _reasoningStartCtrl.text : null,
      reasoningEnd: _parseInlineReasoning ? _reasoningEndCtrl.text : null,
      mergePrompts: _mergePrompts,
      mergeRole: widget.preset?.mergeRole ?? 'system',
      guidedGenerationPrompt: widget.preset?.guidedGenerationPrompt,
      guidedImpersonationPrompt: widget.preset?.guidedImpersonationPrompt,
      summaryPrompt: widget.preset?.summaryPrompt,
      createdAt: widget.preset?.createdAt ??
          currentTimestampSeconds(),
    );
    await ref.read(presetRepoProvider).put(preset);
    ref.invalidate(presetListProvider);
    if (mounted) widget.onSaved(preset);
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}

// ─── _BlockRow ────────────────────────────────────────────────────────────────

class _BlockRow extends StatelessWidget {
  final PresetBlock block;
  final int index;
  final bool isLast;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  const _BlockRow({
    super.key,
    required this.block,
    required this.index,
    required this.isLast,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: const Color(0x33808080),
            width: isLast ? 0 : 1,
          ),
        ),
      ),
      child: Opacity(
        opacity: block.enabled ? 1.0 : 0.5,
        child: Row(
          children: [
            // Drag handle
            ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 30,
                height: 44,
                child: Center(
                  child: Text(
                    '≡',
                    style: TextStyle(
                      fontSize: 20,
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            // Role icon
            Icon(
              _roleIcon(block.role),
              size: 16,
              color: AppColors.textPrimary.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            // Name + token estimate
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        block.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (block.content.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '~${(block.content.length / 4).round()}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Edit button
            SizedBox(
              width: 36,
              height: 44,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onEdit,
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            // Enable toggle
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Transform.scale(
                scale: 0.8,
                alignment: Alignment.centerRight,
                child: Switch(
                  value: block.enabled,
                  onChanged: onToggle,
                  activeThumbColor: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _roleIcon(String role) {
    return switch (role) {
      'user' => Icons.person_outline,
      'assistant' => Icons.smart_toy_outlined,
      _ => Icons.storage_outlined,
    };
  }
}

// ─── _AddBlockRow ─────────────────────────────────────────────────────────────

class _AddBlockRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AddBlockRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0x33808080), width: 1),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 30), // align with drag handle column
              const Icon(Icons.add, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text(
                'Add Block',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── _DotsButton ──────────────────────────────────────────────────────────────

class _DotsButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DotsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent.withValues(alpha: 0.1),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            Icons.more_vert,
            size: 20,
            color: AppColors.accent.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

// ─── _UtilButton ──────────────────────────────────────────────────────────────

class _UtilButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;
  const _UtilButton(
      {required this.icon, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 14,
              color: AppColors.accent.withValues(alpha: 0.7),
            ),
          ),
          if (count > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4444),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.background, width: 1),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── _BlocksBadge ─────────────────────────────────────────────────────────────

class _BlocksBadge extends StatelessWidget {
  final int count;
  const _BlocksBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            '$count blocks',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _SectionLabel ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ─── _SettingsToggle ─────────────────────────────────────────────────────────

class _SettingsToggle extends StatelessWidget {
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.accent),
      ],
    );
  }
}

// ─── _BlockEditorSheet ───────────────────────────────────────────────────────

class _BlockEditorSheet extends StatefulWidget {
  final PresetBlock block;
  final ScrollController scrollController;
  final ValueChanged<PresetBlock> onSave;
  final VoidCallback onDelete;

  const _BlockEditorSheet({
    required this.block,
    required this.scrollController,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_BlockEditorSheet> createState() => _BlockEditorSheetState();
}

class _BlockEditorSheetState extends State<_BlockEditorSheet> {
  late final _nameCtrl = TextEditingController(text: widget.block.name);
  late final _contentCtrl = TextEditingController(text: widget.block.content);
  late String _role = widget.block.role;
  late String _insertionMode = widget.block.insertionMode;
  late int? _depth = widget.block.depth;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Drag handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Edit Block',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => widget.onSave(widget.block.copyWith(
                  name: _nameCtrl.text.trim().isEmpty
                      ? widget.block.name
                      : _nameCtrl.text.trim(),
                  content: _contentCtrl.text,
                  role: _role,
                  insertionMode: _insertionMode,
                  depth: _insertionMode == 'depth' ? _depth : null,
                )),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(color: AppColors.border, height: 1),
        // Scrollable fields
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              _fieldLabel('Block Name'),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: _inputDecoration('Block Name'),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Role'),
              const SizedBox(height: 6),
              _RoleSelector(
                value: _role,
                onChanged: (v) => setState(() => _role = v),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Insertion'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _InsertionModeSelector(
                      value: _insertionMode,
                      onChanged: (v) => setState(() => _insertionMode = v),
                    ),
                  ),
                  if (_insertionMode == 'depth') ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        initialValue: _depth?.toString() ?? '4',
                        decoration: _inputDecoration('Depth'),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        onChanged: (v) => _depth = int.tryParse(v),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _fieldLabel('Content'),
              const SizedBox(height: 6),
              TextField(
                controller: _contentCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                maxLines: null,
                minLines: 5,
                decoration: _inputDecoration('Block content...'),
              ),
              const SizedBox(height: 24),
              // Delete button
              Material(
                color: const Color(0xFFFF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: widget.onDelete,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outlined,
                            size: 20, color: Color(0xFFFF4444)),
                        SizedBox(width: 8),
                        Text(
                          'Delete Block',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}

// ─── _RoleSelector ───────────────────────────────────────────────────────────

class _RoleSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _RoleSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      ('system', 'System'),
      ('user', 'User'),
      ('assistant', 'Assistant'),
    ];
    return Row(
      children: options.map((opt) {
        final (val, label) = opt;
        final active = value == val;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => onChanged(val),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── _InsertionModeSelector ───────────────────────────────────────────────────

class _InsertionModeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _InsertionModeSelector(
      {required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      ('relative', 'Relative'),
      ('depth', 'Depth'),
    ];
    return Row(
      children: options.map((opt) {
        final (val, label) = opt;
        final active = value == val;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => onChanged(val),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── _RegexSheet ──────────────────────────────────────────────────────────────

class _RegexSheet extends StatefulWidget {
  final List<PresetRegex> regexes;
  final ScrollController scrollController;
  final ValueChanged<List<PresetRegex>> onChanged;

  const _RegexSheet({
    required this.regexes,
    required this.scrollController,
    required this.onChanged,
  });

  @override
  State<_RegexSheet> createState() => _RegexSheetState();
}

class _RegexSheetState extends State<_RegexSheet> {
  late final List<PresetRegex> _regexes = List.from(widget.regexes);

  void _addRegex() {
    setState(() {
      _regexes.add(PresetRegex(
        id: generateId(),
        name: 'Regex ${_regexes.length + 1}',
        regex: '',
      ));
    });
    widget.onChanged(_regexes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.code, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text(
                'Regex Scripts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (_regexes.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_regexes.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(color: AppColors.border, height: 1),
        // List
        Expanded(
          child: _regexes.isEmpty
              ? Center(
                  child: Text(
                    'No regex scripts',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                      fontSize: 15,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: _regexes.length,
                  itemBuilder: (_, i) => Dismissible(
                    key: ValueKey(_regexes[i].id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: const Color(0xFFFF4444).withValues(alpha: 0.15),
                      child: const Icon(Icons.delete,
                          color: Color(0xFFFF4444)),
                    ),
                    onDismissed: (_) {
                      setState(() => _regexes.removeAt(i));
                      widget.onChanged(_regexes);
                    },
                    child: RegexTile(
                      regex: _regexes[i],
                      onChanged: (r) {
                        setState(() => _regexes[i] = r);
                        widget.onChanged(_regexes);
                      },
                    ),
                  ),
                ),
        ),
        // Add regex button
        Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _addRegex,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 20, color: AppColors.accent),
                    SizedBox(width: 8),
                    Text(
                      'Add Regex',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
