import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/preset.dart';
import '../../core/services/preset_defaults.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/generic_editor.dart';
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

  void _onBack() {
    final handled = _editorKey.currentState?.handleBack() ?? false;
    if (!handled) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBack();
      },
      child: GlazeScaffold(
        title: widget.preset != null ? 'Edit Preset' : 'New Preset',
        onBack: _onBack,
        body: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: PresetEditorBody(
            key: _editorKey,
            preset: widget.preset,
            onDeleted: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

/// Embeddable preset editor body — no scaffold, no navigation chrome.
/// Expose [PresetEditorBodyState.save] via a [GlobalKey] to trigger save
/// from an outer widget (e.g. a [SheetView] header action).
class PresetEditorBody extends ConsumerStatefulWidget {
  final Preset? preset;
  final VoidCallback? onDeleted;
  final ValueChanged<bool>? onEditingBlockChanged;

  const PresetEditorBody({
    super.key,
    this.preset,
    this.onDeleted,
    this.onEditingBlockChanged,
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
  int? _expandedBlockIndex;

  double? _savedScrollOffset;
  late final ScrollController _scrollController = ScrollController();

  Timer? _saveTimer;
  late final String _currentId = widget.preset?.id ?? generateId();
  late final int _createdAt = widget.preset?.createdAt ?? currentTimestampSeconds();

  @override
  void initState() {
    super.initState();
    _blocks = List.from(widget.preset?.blocks ?? defaultPresetBlocks());
    _regexes = List.from(widget.preset?.regexes ?? []);
    
    _nameCtrl.addListener(_scheduleSave);
    _reasoningStartCtrl.addListener(_scheduleSave);
    _reasoningEndCtrl.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    if (_saveTimer != null && _saveTimer!.isActive) {
      _saveTimer!.cancel();
      _performSave();
    }
    _nameCtrl.dispose();
    _reasoningStartCtrl.dispose();
    _reasoningEndCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _performSave);
  }

  Future<void> _performSave() async {
    final name = _nameCtrl.text.trim().isEmpty ? 'New Preset' : _nameCtrl.text.trim();
    final presetToSave = Preset(
      id: _currentId,
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
      createdAt: _createdAt,
    );
    await ref.read(presetListProvider.notifier).updatePreset(presetToSave);
  }

  bool handleBack() {
    if (_expandedBlockIndex != null) {
      _saveScrollOffset();
      setState(() => _expandedBlockIndex = null);
      widget.onEditingBlockChanged?.call(false);
      _restoreScrollAfterFrame();
      return true;
    }
    return false;
  }

  void _saveScrollOffset() {
    if (_scrollController.hasClients) {
      _savedScrollOffset = _scrollController.offset;
    }
  }

  void _restoreScrollAfterFrame() {
    if (_savedScrollOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _savedScrollOffset != null &&
          _scrollController.hasClients) {
        final target = _savedScrollOffset!.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
        _savedScrollOffset = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_expandedBlockIndex != null) {
      return _BlockEditorInline(
        key: ValueKey(_blocks[_expandedBlockIndex!].id),
        block: _blocks[_expandedBlockIndex!],
        onSave: (updated) {
          setState(() => _blocks[_expandedBlockIndex!] = updated);
          _scheduleSave();
        },
        onDelete: () {
          _saveScrollOffset();
          setState(() {
            _blocks.removeAt(_expandedBlockIndex!);
            _expandedBlockIndex = null;
          });
          widget.onEditingBlockChanged?.call(false);
          _restoreScrollAfterFrame();
          _scheduleSave();
        },
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      key: const ValueKey('dashboard'),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: MediaQuery.paddingOf(context).bottom +
            MediaQuery.viewInsetsOf(context).bottom,
      ),
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
        color: context.cs.primary.withValues(alpha: 0.05),
        border: Border.all(color: context.cs.outline),
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
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.cs.onSurface,
                            ),
                          ),
                          if (_author.isNotEmpty)
                            Text(
                              'by $_author',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color:
                                    context.cs.primary.withValues(alpha: 0.8),
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
          if (_expandedBlockIndex == oldIndex) {
            _expandedBlockIndex = newIndex;
          } else if (_expandedBlockIndex != null) {
            if (oldIndex < _expandedBlockIndex! && newIndex >= _expandedBlockIndex!) {
              _expandedBlockIndex = _expandedBlockIndex! - 1;
            } else if (oldIndex > _expandedBlockIndex! && newIndex <= _expandedBlockIndex!) {
              _expandedBlockIndex = _expandedBlockIndex! + 1;
            }
          }
        });
        _scheduleSave();
      },
      itemBuilder: (_, i) => _BlockRow(
        key: ValueKey(_blocks[i].id),
        block: _blocks[i],
        index: i,
        isLast: i == _blocks.length - 1,
        onEdit: () {
          _saveScrollOffset();
          setState(() {
            _expandedBlockIndex = i;
          });
          widget.onEditingBlockChanged?.call(true);
        },
        onToggle: (v) {
          setState(() => _blocks[i] = _blocks[i].copyWith(enabled: v));
          _scheduleSave();
        },
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
            Text(
              'Advanced Settings',
               style: TextStyle(
                 fontSize: 14,
                 fontWeight: FontWeight.w600,
                 color: context.cs.onSurfaceVariant,
               ),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: _showAdvanced ? 0.5 : 0,
              duration: const Duration(milliseconds: 300),
               child: Icon(
                 Icons.expand_more,
                 color: context.cs.onSurfaceVariant,
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
        border: Border.all(color: context.cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Reasoning'),
          const SizedBox(height: 8),
          _SettingsToggle(
            label: 'Parse Inline Reasoning',
            description: 'Extract reasoning tags from model output',
            value: _parseInlineReasoning,
            onChanged: (v) {
              setState(() => _parseInlineReasoning = v);
              _scheduleSave();
            },
          ),
          if (_parseInlineReasoning) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reasoningStartCtrl,
                    style: TextStyle(color: context.cs.onSurface),
                    decoration: _inputDecoration('<think>'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _reasoningEndCtrl,
                    style: TextStyle(color: context.cs.onSurface),
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
            onChanged: (v) {
              setState(() => _mergePrompts = v);
              _scheduleSave();
            },
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
    _scheduleSave();
  }



  void _showRenameDialog() {
    GlazeBottomSheet.show(
      context,
      title: 'Rename Preset',
      input: BottomSheetInput(
        placeholder: 'Preset name',
        value: _nameCtrl.text,
        confirmLabel: 'Rename',
        onConfirm: (val) {
          Navigator.pop(context);
          setState(() => _nameCtrl.text = val);
          _scheduleSave();
        },
      ),
    );
  }

  void _showAuthorDialog() {
    GlazeBottomSheet.show(
      context,
      title: 'Set Author',
      input: BottomSheetInput(
        placeholder: 'Author (optional)',
        value: _author,
        confirmLabel: 'Save',
        onConfirm: (val) {
          Navigator.pop(context);
          setState(() => _author = val.trim());
          _scheduleSave();
        },
      ),
    );
  }

  void _showOptionsMenu() {
    GlazeBottomSheet.show(
      context,
      title: 'Options',
      items: [
        BottomSheetItem(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () {
            Navigator.pop(context);
            _showRenameDialog();
          },
        ),
        BottomSheetItem(
          icon: Icons.person_outline,
          label: 'Set Author',
          onTap: () {
            Navigator.pop(context);
            _showAuthorDialog();
          },
        ),
        if (widget.preset != null)
          BottomSheetItem(
            icon: Icons.delete_outlined,
            iconColor: const Color(0xFFFF4444),
            label: 'Delete',
            isDestructive: true,
            onTap: () async {
              Navigator.pop(context);
              await ref
                  .read(presetListProvider.notifier)
                  .remove(widget.preset!.id);
              widget.onDeleted?.call();
            },
          ),
      ],
    );
  }

  void _showRegexSheet() {
    GlazeBottomSheet.show(
      context,
      child: _RegexSheet(
        regexes: _regexes,
        onChanged: (list) {
          setState(() => _regexes = list);
          _scheduleSave();
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: context.cs.onSurfaceVariant.withValues(alpha: 0.5)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.cs.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.cs.primary),
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
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            // Role icon
            Icon(
              _roleIcon(block.role),
              size: 16,
              color: context.cs.onSurface.withValues(alpha: 0.6),
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
                         style: TextStyle(
                           fontSize: 15,
                           fontWeight: FontWeight.w500,
                           color: context.cs.onSurface,
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
                           style: TextStyle(
                             fontSize: 11,
                             color: context.cs.onSurfaceVariant,
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
                   child: Icon(
                     Icons.edit_outlined,
                     size: 20,
                     color: context.cs.onSurfaceVariant,
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
                  activeThumbColor: context.cs.primary,
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
              Icon(Icons.add, size: 16, color: context.cs.primary),
              const SizedBox(width: 8),
              Text(
                'Add Block',
                 style: TextStyle(
                   fontSize: 15,
                   fontWeight: FontWeight.w600,
                   color: context.cs.primary,
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
            color: context.cs.primary.withValues(alpha: 0.1),
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
            color: context.cs.primary.withValues(alpha: 0.8),
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
              color: context.cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 14,
              color: context.cs.primary.withValues(alpha: 0.7),
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
                  border: Border.all(color: context.cs.surface, width: 1),
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
          Icon(Icons.description, size: 14, color: context.cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '$count blocks',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.cs.onSurfaceVariant,
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
      style: TextStyle(
        fontSize: 13,
        color: context.cs.onSurfaceVariant,
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
                style: TextStyle(
                  fontSize: 14,
                  color: context.cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: context.cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

// ─── _BlockEditorInline ─────────────────────────────────────────────────────────

class _BlockEditorInline extends StatelessWidget {
  final PresetBlock block;
  final ValueChanged<PresetBlock> onSave;
  final VoidCallback onDelete;

  const _BlockEditorInline({
    super.key,
    required this.block,
    required this.onSave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final config = [
      GenericEditorSection(
        title: null,
        fields: [
          const GenericEditorField(key: 'name', label: 'Block Name', type: 'text'),
          const GenericEditorField(
            key: 'role',
            label: 'Role',
            type: 'select',
            options: [
              {'label': 'System', 'value': 'system'},
              {'label': 'User', 'value': 'user'},
              {'label': 'Assistant', 'value': 'assistant'},
            ],
          ),
          const GenericEditorField(
            key: 'insertionMode',
            label: 'Insertion',
            type: 'select',
            options: [
              {'label': 'Relative', 'value': 'relative'},
              {'label': 'Depth', 'value': 'depth'},
            ],
          ),
          GenericEditorField(
            key: 'depth',
            label: 'Depth',
            type: 'select',
            options: List.generate(20, (i) => {'label': '${i + 1}', 'value': i + 1}),
            showIf: (item) => item['insertionMode'] == 'depth',
          ),
          const GenericEditorField(
            key: 'content',
            label: 'Content',
            type: 'textarea',
            rows: 5,
            expandable: true,
          ),
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GenericEditor(
            item: block.toJson(),
            config: config,
            scrollable: true,
            onChanged: (values) {
              onSave(PresetBlock.fromJson(values));
            },
          ),
        ),
        // Delete button
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 16),
          child: Material(
            color: const Color(0xFFFF4444).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outlined, size: 20, color: Color(0xFFFF4444)),
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
        ),
      ],
    );
  }
}

// ─── _RegexSheet ──────────────────────────────────────────────────────────────

class _RegexSheet extends StatefulWidget {
  final List<PresetRegex> regexes;
  final ValueChanged<List<PresetRegex>> onChanged;

  const _RegexSheet({
    required this.regexes,
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Icon(Icons.code, size: 18, color: context.cs.primary),
              const SizedBox(width: 8),
               Text(
                'Regex Scripts',
                 style: TextStyle(
                   fontSize: 18,
                   fontWeight: FontWeight.w700,
                   color: context.cs.onSurface,
                 ),
               ),
              if (_regexes.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
      color: context.cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_regexes.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.cs.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(color: context.cs.outline, height: 1),
        // List
        if (_regexes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No regex scripts',
                style: TextStyle(
                  color: context.cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 15,
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
        // Add regex button
        Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
                    color: context.cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _addRegex,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 20, color: context.cs.primary),
                    SizedBox(width: 8),
                    Text(
                      'Add Regex',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.cs.primary,
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
