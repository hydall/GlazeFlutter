import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/preset.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
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
      leading: Icon(isActive ? Icons.tune : Icons.tune_outlined, color: isActive ? AppColors.accent : null),
      title: Text(preset.name, style: isActive ? const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600) : null),
      subtitle: Text('${preset.blocks.length} blocks · ${preset.regexes.length} regex', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: isActive ? AppColors.accent.withValues(alpha: 0.2) : null,
              foregroundColor: isActive ? AppColors.accent : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
            onPressed: () => setActivePreset(ref, isActive ? null : preset.id),
            child: Text(isActive ? 'Active' : 'Set Active', style: const TextStyle(fontSize: 12)),
          ),
          IconButton(icon: const Icon(Icons.upload_file, size: 20), tooltip: 'Export', onPressed: () => _exportPreset(ref, context, preset)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => PresetEditorScreen(preset: preset)));
              } else if (value == 'duplicate') {
                final dup = preset.copyWith(id: generateId(), name: '${preset.name} (copy)');
                ref.read(presetListProvider.notifier).add(dup);
              } else if (value == 'export') {
                _exportPreset(ref, context, preset);
              } else if (value == 'delete') {
                if (isActive) setActivePreset(ref, null);
                ref.read(presetListProvider.notifier).remove(preset.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              const PopupMenuItem(value: 'export', child: Text('Export')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
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
          'scriptName': r.name, 'findRegex': r.regex, 'replaceString': r.replacement,
          'placement': r.placement, 'isEnabled': !r.disabled,
        }).toList(),
        'reasoning': preset.reasoningEnabled,
      };

      final encoded = const JsonEncoder.withIndent('  ').convert(exportJson);
      final safeName = preset.name.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final desktop = Platform.environment['USERPROFILE'] ?? '.';
      final exportDir = Directory(p.join(desktop, 'Desktop'));
      final file = File(p.join(exportDir.path, '$safeName.json'));
      file.writeAsStringSync(encoded);

      if (context.mounted) {
        GlazeBottomSheet.show(
          context,
          title: 'Export Complete',
          bigInfo: BottomSheetBigInfo(
            icon: Icons.check_circle_outline,
            description: 'Saved to:\n${file.path}',
          ),
          items: [
            BottomSheetItem(
              label: 'Open File Location',
              centered: true,
              onTap: () {
                Process.run('explorer', ['/select,', file.path]);
                Navigator.pop(context);
              },
            ),
            BottomSheetItem(
              label: 'OK',
              centered: true,
              onTap: () => Navigator.pop(context),
            ),
          ],
        );
      }
    } catch (e) {
      if (context.mounted) {
        GlazeBottomSheet.show(
          context,
          title: 'Export Failed',
          bigInfo: BottomSheetBigInfo(
            icon: Icons.error_outline,
            description: '$e',
          ),
          items: [
            BottomSheetItem(
              label: 'OK',
              centered: true,
              onTap: () => Navigator.pop(context),
            ),
          ],
        );
      }
    }
  }
}
