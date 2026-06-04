import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/import/silly_tavern_preset_parser.dart';
import '../../core/llm/preset_macro_attribution.dart';
import '../../core/models/preset.dart';
import '../../core/state/active_selection_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/sheet_view.dart';
import '../../shared/widgets/glaze_toast.dart';
import 'preset_connections_sheet.dart';
import 'preset_editor_screen.dart';
import 'preset_export.dart';
import 'preset_list_provider.dart';

class PresetListScreen extends ConsumerStatefulWidget {
  final bool startExpanded;
  const PresetListScreen({super.key, this.startExpanded = false});

  @override
  ConsumerState<PresetListScreen> createState() => _PresetListScreenState();
}

class _PresetListScreenState extends ConsumerState<PresetListScreen> {
  Preset? _editingPreset;
  bool _isCreating = false;
  final _editorKey = GlobalKey<PresetEditorBodyState>();

  bool get _inEditor => _isCreating || _editingPreset != null;

  void _openEditor(Preset? preset) {
    setState(() {
      _editingPreset = preset;
      _isCreating = preset == null;
    });
  }

  void _closeEditor() {
    setState(() {
      _editingPreset = null;
      _isCreating = false;
    });
  }

  void _handleBack() {
    if (_inEditor) {
      final handled = _editorKey.currentState?.handleBack() ?? false;
      if (!handled) {
        _closeEditor();
      }
    } else {
      if (widget.startExpanded) {
        context.go('/tools');
      } else {
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetListProvider);
    final activeId = ref.watch(activePresetIdProvider);

    return SheetView(
      startExpanded: widget.startExpanded,
      showRouteBackground: false,
      title: _inEditor
          ? (_editingPreset != null ? 'Edit Preset' : 'New Preset')
          : 'Presets',
      showBack: true,
      onBack: _handleBack,
      body: _inEditor
          ? PresetEditorBody(
              key: _editorKey,
              preset: _editingPreset,
              onDeleted: _closeEditor,
            )
          : presets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => _buildBody(context, ref, list, activeId),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<Preset> list,
    String? activeId,
  ) {
    return Builder(
      builder: (context) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16,
        ).add(EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top,
          bottom: MediaQuery.paddingOf(context).bottom,
        )),
        itemCount: list.length + 1,
        itemBuilder: (_, i) {
          if (i == list.length) return _buildAddButton(context, ref);
          final preset = list[i];
          final isActive = activeId == preset.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PsCard(
              preset: preset,
              isActive: isActive,
              onActivate: () {
                if (!isActive) {
                  setActivePreset(ref, preset.id);
                }
              },
              onConnections: () => showPresetConnections(context, preset.id),
              onEdit: () => _openEditor(preset),
              onDuplicate: () => ref
                  .read(presetListProvider.notifier)
                  .add(
                    preset.copyWith(
                      id: DateTime.now().millisecondsSinceEpoch.toRadixString(
                        36,
                      ),
                      name: '${preset.name} (copy)',
                    ),
                  ),
              onDelete: () {
                if (isActive) {
                  final nextPreset = list.cast<Preset?>().firstWhere(
                        (p) => p?.id != preset.id,
                        orElse: () => null,
                      );
                  setActivePreset(ref, nextPreset?.id);
                }
                ref.read(presetListProvider.notifier).remove(preset.id);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: context.cs.primary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _showAddSheet(context, ref),
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.1),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Add / Import',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'Add Preset',
      items: [
        BottomSheetItem(
          icon: Icons.add_circle_outline,
          label: 'Create New Preset',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _openEditor(null);
          },
        ),
        BottomSheetItem(
          icon: Icons.file_upload_outlined,
          label: 'Import from File',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _importPreset();
          },
        ),
      ],
    );
  }

  Future<void> _importPreset() async {
    final ctx = context;
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: Platform.isIOS ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isIOS ? null : ['json'],
        allowMultiple: false,
        withData: true,
      );
    } catch (_) {}
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;

    try {
      String jsonString;
      if (picked.bytes != null && picked.bytes!.isNotEmpty) {
        jsonString = utf8.decode(picked.bytes!);
      } else if (picked.path != null && picked.path!.isNotEmpty) {
        jsonString = await File(picked.path!).readAsString();
      } else {
        if (ctx.mounted) GlazeToast.show(ctx, 'Cannot read file');
        return;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final preset = parseSillyTavernPreset(json, picked.name);
      await ref.read(presetListProvider.notifier).add(preset);
      if (ctx.mounted) {
        GlazeToast.show(
          ctx,
          'Imported "${preset.name}" (${preset.blocks.length} blocks)',
        );
      }
    } catch (e) {
      if (ctx.mounted) GlazeToast.error(ctx, 'Import failed: ', e);
    }
  }
}

int _presetTokenCount(Preset preset) => presetOnlyTokenCount(preset);



// ─── ps-card ─────────────────────────────────────────────────────────────────

class _PsCard extends ConsumerWidget {
  final Preset preset;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onConnections;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _PsCard({
    required this.preset,
    required this.isActive,
    required this.onActivate,
    required this.onConnections,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(presetConnectionsProvider);
    final hasCharBinding = connections.character.values.contains(preset.id);
    final hasChatBinding = connections.chat.values.contains(preset.id);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(
          color: isActive ? context.cs.primary : context.cs.outline,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onActivate,
          borderRadius: BorderRadius.circular(10),
          splashColor: context.cs.primary.withValues(alpha: 0.08),
          highlightColor: context.cs.primary.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circular icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.cs.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: context.cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _SmallBadge(
                            icon: Icons.description,
                            label: '${_presetTokenCount(preset)}',
                          ),
                          if (preset.author != null &&
                              preset.author!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'by ${preset.author}',
                                 style: TextStyle(
                                   fontSize: 12,
                                   color: context.cs.onSurfaceVariant,
                                 ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Connection badge — tappable, colour shows binding type
                _ConnBadge(
                  isActive: isActive,
                  hasChatBinding: hasChatBinding,
                  hasCharBinding: hasCharBinding,
                  onTap: onConnections,
                ),
                const SizedBox(width: 8),
                // Edit button
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: onEdit,
                      onLongPress: () => _showContextMenu(context),
                      borderRadius: BorderRadius.circular(8),
                       child: Icon(
                         Icons.edit_outlined,
                         size: 18,
                         color: context.cs.onSurfaceVariant,
                       ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    GlazeBottomSheet.show<void>(
      context,
      title: preset.name,
      items: [
        BottomSheetItem(
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            onEdit();
          },
        ),
        BottomSheetItem(
          icon: Icons.copy_outlined,
          label: 'Duplicate',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            onDuplicate();
          },
        ),
        BottomSheetItem(
          icon: Icons.upload_file_outlined,
          label: 'Export',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            exportPreset(context, preset);
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outlined,
          iconColor: const Color(0xFFFF4444),
          label: 'Delete',
          isDestructive: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            onDelete();
          },
        ),
      ],
    );
  }
}

// ─── shared small widgets ─────────────────────────────────────────────────────

class _SmallBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SmallBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable link badge that shows the preset's binding scope visually.
///
/// Colour logic (mirrors JS Glaze `getPresetConnectionType`):
///   orange  — chat-level binding active
///   purple  — character-level binding active (no chat binding)
///   green   — globally active (no specific bindings)
///   grey    — not active, no bindings
class _ConnBadge extends StatelessWidget {
  final bool isActive;
  final bool hasChatBinding;
  final bool hasCharBinding;
  final VoidCallback onTap;

  const _ConnBadge({
    required this.isActive,
    required this.hasChatBinding,
    required this.hasCharBinding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (hasChatBinding) {
      color = const Color(0xFFFF9500); // orange — chat binding
    } else if (hasCharBinding) {
      color = const Color(0xFFAF52DE); // purple — character binding
    } else if (isActive) {
      color = const Color(0xFF34C759); // green — global active
    } else {
      color = context.cs.onSurfaceVariant.withValues(alpha: 0.5); // grey
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: (hasChatBinding || hasCharBinding || isActive)
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.link, size: 16, color: color),
      ),
    );
  }
}
