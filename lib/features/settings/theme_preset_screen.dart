import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/theme_preset.dart';
import '../../../shared/theme/theme_preset_storage.dart';
import '../../../shared/theme/theme_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_scaffold.dart';

class ThemePresetScreen extends ConsumerStatefulWidget {
  const ThemePresetScreen({super.key});

  @override
  ConsumerState<ThemePresetScreen> createState() => _ThemePresetScreenState();
}

class _ThemePresetScreenState extends ConsumerState<ThemePresetScreen> {
  final _storage = ThemePresetStorage();

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final presets = theme.presets;
    final activeId = theme.activePreset.id;

    return GlazeScaffold(
      title: 'Themes',
      onBack: () => Navigator.pop(context),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _buildActivePreview(context, theme.activePreset),
          const SizedBox(height: 16),
          _buildImportButton(context),
          const SizedBox(height: 16),
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
    );
  }

  Widget _buildActivePreview(BuildContext context, ThemePreset preset) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: context.cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cs.outlineVariant),
        ),
        child: Column(
          children: [
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: preset.accent.withAlpha(30),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: preset.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (preset.userBubbleParsed != null)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: preset.userBubbleParsed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (preset.charBubbleParsed != null)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: preset.charBubbleParsed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.cs.onSurface,
                          ),
                        ),
                        if (preset.author.isNotEmpty)
                          Text(
                            'by ${preset.author}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _contrastColor(context.colors.accent, context.cs.surfaceContainerHighest),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportButton(BuildContext context) {
    final btnBg = _contrastColor(context.colors.accent, context.cs.surface);
    final btnFg = btnBg.computeLuminance() > 0.35
        ? const Color(0xFF1A1A1B)
        : const Color(0xFFE1E3E6);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton.icon(
        onPressed: _importTheme,
        icon: Icon(Icons.file_download_outlined, color: btnFg),
        label: Text(
          'Import Theme',
          style: TextStyle(color: btnFg, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: btnBg,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static Color _contrastColor(Color accent, Color surface) {
    if (_contrastRatio(accent, surface) >= 4.5) return accent;
    final hsl = HSLColor.fromColor(accent);
    double l = hsl.lightness;
    for (int i = 0; i < 20; i++) {
      l = surface.computeLuminance() < 0.5 ? l + 0.04 : l - 0.04;
      final c = HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, l.clamp(0.0, 1.0)).toColor();
      if (_contrastRatio(c, surface) >= 4.5) return c;
    }
    return surface.computeLuminance() < 0.5
        ? HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, 0.6).toColor()
        : HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, 0.4).toColor();
  }

  static double _contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  Widget _buildPresetTile(BuildContext context, ThemePreset preset, bool isActive) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: preset.accent.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: preset.accent, width: isActive ? 2 : 0),
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
          if (!isActive)
            IconButton(
              icon: Icon(Icons.play_arrow, color: context.cs.onSurfaceVariant, size: 20),
              onPressed: () => _applyPreset(preset),
              tooltip: 'Apply',
            ),
          if (preset.id != 'default')
            IconButton(
              icon: Icon(Icons.delete_outline, color: context.cs.onSurfaceVariant, size: 18),
              onPressed: () => _deletePreset(preset.id),
              tooltip: 'Delete',
            ),
        ],
      ),
      onTap: isActive ? null : () => _applyPreset(preset),
    );
  }

  Future<void> _importTheme() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Import Theme',
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      final preset = await _storage.importFromFile(file.path!);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Theme'),
        content: const Text('Are you sure you want to delete this theme?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(themeProvider.notifier).deletePreset(id);
    }
  }
}
