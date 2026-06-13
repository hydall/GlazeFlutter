import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/file_export_service.dart';
import '../../../core/models/preset.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_error_dialog.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../preset_editor_screen.dart';
import '../preset_list_provider.dart';

class PresetTile extends ConsumerWidget {
  final Preset preset;
  const PresetTile({super.key, required this.preset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activePresetIdProvider);
    final isActive = activeId == preset.id;

    return ListTile(
      leading: Icon(isActive ? Icons.tune : Icons.tune_outlined, color: isActive ? context.cs.primary : null),
      title: Text(preset.name, style: isActive ? TextStyle(color: context.cs.primary, fontWeight: FontWeight.w600) : null),
      subtitle: Text('${preset.blocks.length} blocks · ${preset.regexes.length} regex', style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: isActive ? context.cs.primary.withValues(alpha: 0.2) : null,
              foregroundColor: isActive ? context.cs.primary : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
            onPressed: () => setActivePreset(ref, isActive ? null : preset.id),
            child: Text(isActive ? 'Active' : 'Set Active', style: const TextStyle(fontSize: 12)),
          ),
          IconButton(icon: const Icon(Icons.upload_file, size: 20), tooltip: 'Export', onPressed: () => _exportPreset(ref, context, preset)),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'More options',
            onPressed: () {
              GlazeBottomSheet.show<void>(
                context,
                title: 'Preset Options',
                items: [
                  BottomSheetItem(
                    label: 'Edit',
                    icon: Icons.edit,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PresetEditorScreen(preset: preset)));
                    },
                  ),
                  BottomSheetItem(
                    label: 'Duplicate',
                    icon: Icons.copy,
                    onTap: () {
                      Navigator.pop(context);
                      final dup = preset.copyWith(id: generateId(), name: '${preset.name} (copy)');
                      ref.read(presetListProvider.notifier).add(dup);
                    },
                  ),
                  BottomSheetItem(
                    label: 'Export',
                    icon: Icons.upload_file,
                    onTap: () {
                      Navigator.pop(context);
                      _exportPreset(ref, context, preset);
                    },
                  ),
                  BottomSheetItem(
                    label: 'Delete',
                    icon: Icons.delete,
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(context);
                      if (isActive) setActivePreset(ref, null);
                      ref.read(presetListProvider.notifier).remove(preset.id);
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _exportPreset(WidgetRef ref, BuildContext context, Preset preset) async {
    try {
      final exportJson = <String, dynamic>{
        'name': preset.name,
        'prompts': preset.blocks.map((b) => <String, dynamic>{
          'name': b.name, 'role': b.role, 'content': b.content, 'enabled': b.enabled,
          'insertion_mode': b.insertionMode, if (b.depth != null) 'depth': b.depth,
        }).toList(),
        'regexes': preset.regexes.map((r) => <String, dynamic>{
          'scriptName': r.name,
          'findRegex': r.regex,
          'replaceString': r.replacement,
          'trimStrings': r.trimOut.isEmpty
              ? <String>[]
              : r.trimOut.split('\n').where((t) => t.isNotEmpty).toList(),
          'placement': r.placement,
          'isEnabled': !r.disabled,
          'markdownOnly': r.markdownOnly,
          'promptOnly': r.promptOnly,
          'runOnEdit': r.runOnEdit,
          'substituteRegex': r.substituteRegex,
          if (r.minDepth != null) 'minDepth': r.minDepth,
          if (r.maxDepth != null) 'maxDepth': r.maxDepth,
        }).toList(),
        'reasoning': preset.reasoningEnabled,
      };

      final encoded = const JsonEncoder.withIndent('  ').convert(exportJson);
      final safeName = preset.name.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final savedPath = await FileExportService.export(
        data: encoded,
        filename: '$safeName.json',
        subfolder: 'presets',
      );

      if (context.mounted) {
        GlazeToast.show(context, 'Exported to $savedPath');
      }
    } catch (e) {
      if (context.mounted) {
        GlazeErrorDialog.show(context, e, prefix: 'Export failed: ');
      }
    }
  }
}
