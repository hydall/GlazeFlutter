import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/import/silly_tavern_preset_parser.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import 'preset_editor_screen.dart';
import 'preset_list_provider.dart';
import 'widgets/preset_tile.dart';

class PresetListScreen extends ConsumerWidget {
  const PresetListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetListProvider);

    return GlazeScaffold(
      title: 'Presets',
      onBack: () => context.go('/tools'),
      actions: [
        IconButton(icon: const Icon(Icons.file_upload), color: AppColors.accent, onPressed: () => _importPreset(context, ref)),
        IconButton(icon: const Icon(Icons.add), color: AppColors.accent, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PresetEditorScreen()))),
      ],
      body: presets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    const Text('No presets yet'),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PresetEditorScreen())),
                      child: const Text('Create Preset'),
                    ),
                  ],
                ),
              )
            : ListView.builder(itemCount: list.length, itemBuilder: (_, i) => PresetTile(preset: list[i])),
      ),
    );
  }

  Future<void> _importPreset(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(type: FileType.any, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;

    String jsonString;
    if (picked.bytes != null) {
      jsonString = utf8.decode(picked.bytes!);
    } else if (picked.path != null && picked.path!.isNotEmpty) {
      jsonString = File(picked.path!).readAsStringSync();
    } else {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot read file')));
      return;
    }

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final preset = parseSillyTavernPreset(json, picked.name);
      await ref.read(presetListProvider.notifier).add(preset);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported "${preset.name}" (${preset.blocks.length} blocks)')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}
