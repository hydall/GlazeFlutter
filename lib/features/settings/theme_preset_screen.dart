import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/file_export_service.dart';
import '../../../shared/theme/theme_preset.dart';
import '../../../shared/theme/theme_preset_storage.dart';
import '../../../shared/theme/theme_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/color_utils.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import '../../../shared/widgets/glaze_toast.dart';
import 'theme_editor_screen.dart';

class ThemePresetScreen extends ConsumerStatefulWidget {
  const ThemePresetScreen({super.key});

  @override
  ConsumerState<ThemePresetScreen> createState() => _ThemePresetScreenState();
}

class _ThemePresetScreenState extends ConsumerState<ThemePresetScreen> {
  ThemePresetStorage? _storage;

  @override
  void initState() {
    super.initState();
    _initStorage();
  }

  Future<void> _initStorage() async {
    _storage = await ThemePresetStorage.create();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final presets = theme.presets;
    final activeId = theme.activePreset.id;

    return GlazeScaffold(
      title: 'Themes',
      onBack: () => Navigator.pop(context),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 96),
            children: [
              _buildFontToggle(context),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'All Themes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...presets.map((p) => _buildPresetTile(context, p, p.id == activeId)),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: _ThemeFab(onTap: () => _showAddSheet(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildFontToggle(BuildContext context) {
    final ignoreCustomFont = ref.watch(themeProvider).ignoreCustomFont;
    final hasFont = ref.watch(themeProvider).activePreset.hasChatFont ||
        ref.watch(themeProvider).activePreset.hasCustomFont;
    if (!hasFont) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SwitchListTile(
        value: !ignoreCustomFont,
        onChanged: (v) =>
            ref.read(themeProvider.notifier).setIgnoreCustomFont(!v),
        title: Text(
          'Custom Font',
          style: TextStyle(color: context.cs.onSurface),
        ),
        subtitle: Text(
          'Use theme\'s custom font',
          style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
        ),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'Add Theme',
      items: [
        BottomSheetItem(
          icon: Icons.add_rounded,
          label: 'New Theme',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _createNewTheme();
          },
        ),
        BottomSheetItem(
          icon: Icons.file_download_outlined,
          label: 'Import from File',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _importTheme();
          },
        ),
      ],
    );
  }

  static Color _contrastColor(Color accent, Color surface) {
    if (contrastRatio(accent, surface) >= 4.5) return accent;
    final hsl = HSLColor.fromColor(accent);
    double l = hsl.lightness;
    for (int i = 0; i < 20; i++) {
      l = surface.computeLuminance() < 0.5 ? l + 0.04 : l - 0.04;
      final c = HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, l.clamp(0.0, 1.0)).toColor();
      if (contrastRatio(c, surface) >= 4.5) return c;
    }
    return surface.computeLuminance() < 0.5
        ? HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, 0.6).toColor()
        : HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, 0.4).toColor();
  }

  Widget _buildPresetTile(BuildContext context, ThemePreset preset, bool isActive) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: preset.accent.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: preset.accent, width: isActive ? 2 : 1),
        ),
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: preset.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
      title: Text(
        preset.name,
        style: TextStyle(
          color: context.cs.onSurface,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: preset.author.isNotEmpty
          ? Text(
              'by ${preset.author}',
              style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            Icon(Icons.check_circle, color: _contrastColor(context.colors.accent, context.cs.surface), size: 20),
          IconButton(
            icon: Icon(Icons.more_vert, color: context.cs.onSurfaceVariant, size: 18),
            tooltip: 'Menu',
            onPressed: () => _showPresetActions(context, preset, isActive),
          ),
        ],
      ),
      onTap: isActive ? null : () => _applyPreset(preset),
    );
  }

  void _showPresetActions(BuildContext context, ThemePreset preset, bool isActive) {
    GlazeBottomSheet.show<void>(
      context,
      title: preset.name,
      items: [
        BottomSheetItem(
          icon: Icons.tune,
          label: 'Edit Theme',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _openThemeEditor(preset, isActive: isActive);
          },
        ),
        BottomSheetItem(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _renamePreset(preset);
          },
        ),
        BottomSheetItem(
          icon: Icons.upload_file,
          label: 'Export',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _exportPreset(preset);
          },
        ),
        if (preset.id != 'default')
          BottomSheetItem(
            icon: Icons.delete_outline,
            label: 'Delete Theme',
            isDestructive: true,
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              _deletePreset(preset.id);
            },
          ),
      ],
    );
  }

  void _renamePreset(ThemePreset preset) {
    GlazeBottomSheet.show(
      context,
      title: 'Rename Theme',
      input: BottomSheetInput(
        placeholder: 'Theme name',
        value: preset.name,
        confirmLabel: 'Rename',
        onConfirm: (val) async {
          Navigator.of(context, rootNavigator: true).pop();
          if (val.trim().isNotEmpty) {
            final renamed = preset.copyWith(name: val.trim());
            await ref.read(themeProvider.notifier).updatePreset(renamed);
          }
        },
      ),
    );
  }

  Future<void> _exportPreset(ThemePreset preset) async {
    try {
      final json = jsonEncode(preset.toJson());
      final filename = '${preset.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.json';
      final path = await FileExportService.export(
        data: json,
        filename: filename,
        subfolder: 'themes',
      );
      if (!mounted) return;
      GlazeToast.show(context, 'Theme exported to $path');
    } catch (e) {
      if (e.toString().contains('cancelled')) return;
      if (!mounted) return;
      GlazeToast.error(context, 'Export failed: ', e);
    }
  }

  Future<void> _openThemeEditor(ThemePreset preset, {required bool isActive}) async {
    if (!isActive) {
      _applyPreset(preset);
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ThemeEditorScreen()),
    );
  }

  Future<void> _createNewTheme() async {
    final preset = ThemePreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Theme',
    );
    await ref.read(themeProvider.notifier).importPreset(preset);
    await ref.read(themeProvider.notifier).applyPreset(preset);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ThemeEditorScreen()),
    );
  }

  Future<void> _importTheme() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      dialogTitle: 'Import Theme',
      withData: true,
    );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      final preset = await _storage?.importFromFile(file.path!);
      if (preset == null) return;
      await ref.read(themeProvider.notifier).importPreset(preset);
      _applyPreset(preset);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Theme "${preset.name}" imported')),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid theme file: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import: $e')),
        );
      }
    }
  }

  void _applyPreset(ThemePreset preset) {
    ref.read(themeProvider.notifier).applyPreset(preset);
  }

  Future<void> _deletePreset(String id) async {
    final confirmed = await GlazeBottomSheet.show<bool>(
      context,
      title: 'Delete Theme',
      bigInfo: const BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'Are you sure you want to delete this theme?',
      ),
      items: [
        BottomSheetItem(
          label: 'Delete',
          isDestructive: true,
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ],
    );
    if (confirmed == true) {
      await ref.read(themeProvider.notifier).deletePreset(id);
    }
  }
}

class _ThemeFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ThemeFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: context.cs.primary,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'Add',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
