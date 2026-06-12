import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/tokenizer.dart';
import '../../core/models/preset.dart';
import '../../core/services/preset_defaults.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/generic_editor.dart';
import '../../shared/widgets/help_tip.dart';
import 'preset_list_provider.dart';
import 'preset_export.dart';
import 'widgets/preset_block_row.dart';
import '../../core/llm/summary_service.dart';
import '../chat/chat_provider.dart';
import '../chat/widgets/authors_note_sheet.dart';
import '../chat/widgets/summary_sheet.dart';
import '../regex/regex_sheet.dart';

/// Standalone screen wrapper around [PresetEditorBody].
class PresetEditorScreen extends StatefulWidget {
  final Preset? preset;
  final String? charId;
  const PresetEditorScreen({super.key, this.preset, this.charId});

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
            charId: widget.charId,
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

  /// Active chat used to edit the session-scoped Author's Note block. Null when
  /// the editor is opened outside a chat (the note editor then shows a hint).
  final String? charId;
  final VoidCallback? onDeleted;
  final ValueChanged<bool>? onEditingBlockChanged;

  const PresetEditorBody({
    super.key,
    this.preset,
    this.charId,
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
    _reconcileAuthorsNoteEnabled();
    _reconcileSummaryEnabled();

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
      final expanded = _blocks[_expandedBlockIndex!];
      // Author's Note edits per-preset role/depth/insertion here; its content
      // (session-scoped) is shown and edited via the linked chat note sheet.
      if (expanded.id == 'authors_note') {
        return _AuthorsNoteBlockEditor(
          key: ValueKey(expanded.id),
          block: expanded,
          charId: widget.charId,
          onSave: (updated) {
            setState(() => _blocks[_expandedBlockIndex!] = updated);
            _scheduleSave();
          },
        );
      }
      // Summary: per-preset role/depth/insertion/prefix here; content (session-
      // scoped, in the summary repo) is shown and edited via the chat sheet.
      if (expanded.id == 'summary') {
        return _SummaryBlockEditor(
          key: ValueKey(expanded.id),
          block: expanded,
          charId: widget.charId,
          onSave: (updated) {
            setState(() => _blocks[_expandedBlockIndex!] = updated);
            _scheduleSave();
          },
        );
      }
      return _BlockEditorInline(
        key: ValueKey(expanded.id),
        block: expanded,
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
                _BlocksBadge(
                  count: _blocks
                      .where((b) => b.enabled && !b.isStashed && b.content.isNotEmpty)
                      .fold(0, (sum, b) => sum + estimateTokens(b.content)),
                ),
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
      // TODO: migrate to onReorderItem (newIndex semantics differ — see Flutter changelog).
      // ignore: deprecated_member_use
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
      itemBuilder: (_, i) => PresetBlockRow(
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
          // Author's Note enable is one entity for the chat — mirror it onto
          // the session note and every other preset's block.
          if (_blocks[i].id == 'authors_note') {
            syncAuthorsNoteEnabled(ref, charId: widget.charId, enabled: v);
          } else if (_blocks[i].id == 'summary') {
            syncSummaryEnabled(ref, charId: widget.charId, enabled: v);
          }
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
          const _SectionLabel('Reasoning', helpTerm: 'preset-reasoning'),
          const SizedBox(height: 8),
          _SettingsToggle(
            label: 'Parse Inline Reasoning',
            description: 'Extract reasoning tags from model output',
            value: _parseInlineReasoning,
            helpTerm: 'preset-reasoning-inline',
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
            helpTerm: 'preset-merge',
            onChanged: (v) {
              setState(() => _mergePrompts = v);
              _scheduleSave();
            },
          ),
        ],
      ),
    );
  }

  // ─── Author's Note (content session-scoped; role/depth per-preset) ────────

  /// On open, make the local authors_note block enable mirror the session note
  /// (the note's on/off is one entity for the chat). Persisted via [_scheduleSave].
  void _reconcileAuthorsNoteEnabled() {
    final charId = widget.charId;
    if (charId == null) return;
    final note = ref.read(chatProvider(charId)).value?.session?.authorsNote;
    if (note == null) return;
    final idx = _blocks.indexWhere((b) => b.id == 'authors_note');
    if (idx == -1 || _blocks[idx].enabled == note.enabled) return;
    _blocks[idx] = _blocks[idx].copyWith(enabled: note.enabled);
    _scheduleSave();
  }

  /// Summary enable is session-scoped and mirrored onto every preset's block.
  /// On open, sync the local block with the current chat summary flag.
  void _reconcileSummaryEnabled() {
    final charId = widget.charId;
    if (charId == null) return;
    final session = ref.read(chatProvider(charId)).value?.session;
    if (session == null) return;
    final idx = _blocks.indexWhere((b) => b.id == 'summary');
    if (idx == -1) return;
    ref.read(summaryEnabledProvider(session.id).future).then((enabled) {
      if (!mounted || _blocks[idx].enabled == enabled) return;
      setState(() {
        _blocks[idx] = _blocks[idx].copyWith(enabled: enabled);
      });
      _scheduleSave();
    });
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  void _addBlock() {
    final hasMemoryBlock = _blocks.any((b) => b.id == 'memory');
    GlazeBottomSheet.show<void>(
      context,
      title: 'Add Block',
      items: [
        if (!hasMemoryBlock)
          BottomSheetItem(
            icon: Icons.psychology_alt_outlined,
            label: 'Memory Book',
            onTap: () {
              Navigator.pop(context);
              _addMemoryBlock();
            },
          ),
        BottomSheetItem(
          icon: Icons.add,
          label: 'Custom Block',
          onTap: () {
            Navigator.pop(context);
            _addCustomBlock();
          },
        ),
      ],
    );
  }

  void _addCustomBlock() {
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

  void _addMemoryBlock() {
    if (_blocks.any((b) => b.id == 'memory')) return;
    setState(() {
      // Insert the Memory Book block just before Chat History so injected
      // memories sit with the other system context, not after the dialogue.
      final chatHistoryIdx = _blocks.indexWhere((b) => b.id == 'chat_history');
      const memoryBlock = PresetBlock(
        id: 'memory',
        name: 'Memory Book',
        role: 'system',
        content: '',
        enabled: true,
        isStatic: true,
      );
      if (chatHistoryIdx != -1) {
        _blocks.insert(chatHistoryIdx, memoryBlock);
      } else {
        _blocks.add(memoryBlock);
      }
    });
    _scheduleSave();
  }



  void _showRenameDialog() {
    GlazeBottomSheet.show<void>(
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
    GlazeBottomSheet.show<void>(
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
    GlazeBottomSheet.show<void>(
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
        BottomSheetItem(
          icon: Icons.upload_file_outlined,
          label: 'Export',
          onTap: () {
            Navigator.pop(context);
            final name = _nameCtrl.text.trim().isEmpty
                ? 'New Preset'
                : _nameCtrl.text.trim();
            final snapshot = Preset(
              id: _currentId,
              name: name,
              author: _author.trim().isEmpty ? null : _author.trim(),
              blocks: _blocks,
              regexes: _regexes,
              reasoningEnabled: _parseInlineReasoning,
              reasoningStart:
                  _parseInlineReasoning ? _reasoningStartCtrl.text : null,
              reasoningEnd:
                  _parseInlineReasoning ? _reasoningEndCtrl.text : null,
              mergePrompts: _mergePrompts,
              mergeRole: widget.preset?.mergeRole ?? 'system',
              guidedGenerationPrompt:
                  widget.preset?.guidedGenerationPrompt,
              guidedImpersonationPrompt:
                  widget.preset?.guidedImpersonationPrompt,
              summaryPrompt: widget.preset?.summaryPrompt,
              createdAt: _createdAt,
            );
            exportPreset(context, snapshot);
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

  Future<void> _showRegexSheet() async {
    _saveTimer?.cancel();
    await _performSave();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (_) => RegexSheet(presetId: _currentId),
    );
    if (!mounted) return;
    final presets = ref.read(presetListProvider).value ?? [];
    final preset = presets.where((p) => p.id == _currentId).firstOrNull;
    if (preset != null) setState(() => _regexes = List.from(preset.regexes));
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
            '${count}t',
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
  final String? helpTerm;
  const _SectionLabel(this.text, {this.helpTerm});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: context.cs.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
    if (helpTerm == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [label, HelpTip(term: helpTerm!)],
    );
  }
}

// ─── _SettingsToggle ─────────────────────────────────────────────────────────

class _SettingsToggle extends StatelessWidget {
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? helpTerm;

  const _SettingsToggle({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.helpTerm,
  });

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      style: TextStyle(
        fontSize: 14,
        color: context.cs.onSurface,
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (helpTerm != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [labelWidget, HelpTip(term: helpTerm!)],
                )
              else
                labelWidget,
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
            key: 'appendToLastMessage',
            label: 'Append to last user message',
            type: 'select',
            options: [
              {'label': 'No', 'value': false},
              {'label': 'Yes', 'value': true},
            ],
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

// ─── _AuthorsNoteBlockEditor ────────────────────────────────────────────────────

/// Inline editor for the `authors_note` block. Edits the per-preset settings
/// (role / insertion mode / depth) on the block itself, while the note's
/// content + enabled are session-scoped: shown here read-only and edited via the
/// linked chat note sheet. Outside a chat ([charId] == null) a hint is shown.
class _AuthorsNoteBlockEditor extends ConsumerWidget {
  final PresetBlock block;
  final String? charId;
  final ValueChanged<PresetBlock> onSave;

  const _AuthorsNoteBlockEditor({
    super.key,
    required this.block,
    required this.charId,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = charId == null
        ? null
        : ref.watch(chatProvider(charId!)).value?.session?.authorsNote;
    final content = note?.content ?? '';

    final config = [
      GenericEditorSection(
        title: null,
        fields: [
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
        ],
      ),
    ];

    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 16,
          bottom: MediaQuery.paddingOf(context).bottom + 60,
        ),
        children: [
          _linkedSessionContentCard(
            context,
            charId: charId,
            content: content,
            hint:
                "Author's note content is tied to a chat. Open a chat to edit it.",
            onEdit: () => showAuthorsNoteSheet(context, charId),
          ),
          GenericEditor(
            item: block.toJson(),
            config: config,
            scrollable: false,
            onChanged: (values) => onSave(PresetBlock.fromJson(values)),
          ),
        ],
      ),
    );
  }
}

// ─── _SummaryBlockEditor ────────────────────────────────────────────────────────

/// Inline editor for the `summary` block. Edits per-preset settings (role /
/// insertion mode / depth / prefix) on the block; the summary content is
/// session-scoped (stored in the summary repo), shown here and edited via the
/// linked chat summary sheet. Outside a chat ([charId] == null) a hint is shown.
class _SummaryBlockEditor extends ConsumerWidget {
  final PresetBlock block;
  final String? charId;
  final ValueChanged<PresetBlock> onSave;

  const _SummaryBlockEditor({
    super.key,
    required this.block,
    required this.charId,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = charId == null
        ? null
        : ref.watch(chatProvider(charId!)).value?.session?.id;
    final content = sessionId == null
        ? ''
        : (ref.watch(summaryContentProvider(sessionId)).value ?? '');

    final config = [
      GenericEditorSection(
        title: null,
        fields: [
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
            key: 'prefix',
            label: 'Prefix',
            type: 'text',
            placeholder: 'Summary: ',
          ),
        ],
      ),
    ];

    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 16,
          bottom: MediaQuery.paddingOf(context).bottom + 60,
        ),
        children: [
          _linkedSessionContentCard(
            context,
            charId: charId,
            content: content,
            hint: 'Summary content is tied to a chat. Open a chat to edit it.',
            onEdit: () => showSummarySheet(context, charId!),
          ),
          GenericEditor(
            item: block.toJson(),
            config: config,
            scrollable: false,
            onChanged: (values) => onSave(PresetBlock.fromJson(values)),
          ),
        ],
      ),
    );
  }
}

// ─── shared content card ─────────────────────────────────────────────────────

/// Card showing the chat-scoped content of a linked block (Author's Note /
/// Summary) with an "Edit content" action, or a hint when no chat is active.
Widget _linkedSessionContentCard(
  BuildContext context, {
  required String? charId,
  required String content,
  required String hint,
  required VoidCallback onEdit,
}) {
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.cs.primary.withValues(alpha: 0.05),
      border: Border.all(color: context.cs.outline),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Content',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cs.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              'from current chat',
              style: TextStyle(
                fontSize: 11,
                color: context.cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (charId == null)
          Text(
            hint,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: context.cs.onSurfaceVariant,
            ),
          )
        else ...[
          Text(
            content.isEmpty ? 'Empty' : content,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: content.isEmpty
                  ? context.cs.onSurfaceVariant
                  : context.cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: context.cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: context.cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Edit content',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

