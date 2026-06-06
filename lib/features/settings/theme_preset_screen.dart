import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/file_export_service.dart';
import '../../../shared/theme/theme_preset.dart';
import '../../../shared/theme/theme_preset_storage.dart';
import '../../../shared/theme/theme_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glass_surface.dart';
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

  // Decoded bg-image bytes keyed by `preset.id`, paired with the bgImage's
  // hash so edits invalidate the cache. Reusing the same `Uint8List` instance
  // across rebuilds keeps `MemoryImage` cached in the global ImageCache and
  // prevents the flicker that happens when the preset list rebuilds (e.g.
  // after applying a preset).
  final Map<String, ({int hash, Uint8List? bytes})> _bgBytesCache = {};

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
              ...presets.map(
                (p) => _buildPresetTile(
                  context,
                  p,
                  p.id == activeId,
                  theme.activePreset,
                ),
              ),
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

  Uint8List? _decodeBgImage(ThemePreset preset) {
    if (!preset.hasBgImage) return null;
    final data = preset.bgImage!;
    final hash = data.hashCode;
    final cached = _bgBytesCache[preset.id];
    if (cached != null && cached.hash == hash) return cached.bytes;
    Uint8List? bytes;
    try {
      final commaIdx = data.indexOf(',');
      if (commaIdx != -1) {
        bytes = base64Decode(data.substring(commaIdx + 1));
      }
    } catch (_) {
      bytes = null;
    }
    _bgBytesCache[preset.id] = (hash: hash, bytes: bytes);
    return bytes;
  }

  Widget _buildPresetTile(
    BuildContext context,
    ThemePreset preset,
    bool isActive,
    ThemePreset activePreset,
  ) {
    final cs = context.cs;
    final accent = preset.accent;
    final bgBytes = _decodeBgImage(preset);
    final hasImage = bgBytes != null;

    final sublabelParts = <String>[];
    if (preset.author.isNotEmpty) sublabelParts.add('by ${preset.author}');
    if (isActive) sublabelParts.add('Active');
    final sublabel = sublabelParts.join(' • ');

    final borderBase = activePreset.borderParsed ?? cs.onSurface;
    final borderOpacity = activePreset.borderOpacity.clamp(0.0, 1.0);
    final borderWidth = activePreset.borderWidth;
    // Base border is always the active preset's UI Element border. The
    // active-state highlight is painted on top via an `AnimatedContainer`
    // so the transition between presets fades smoothly.
    final baseBorder = Border.all(
      color: borderBase.withValues(alpha: borderOpacity),
      width: borderWidth,
    );
    final highlightWidth = borderWidth < 1 ? 1.0 : borderWidth;

    final tint = activePreset.uiColorParsed ?? cs.surfaceContainerHighest;

    final labelColor = hasImage ? Colors.white : cs.onSurface;
    final sublabelColor =
        hasImage ? Colors.white.withAlpha(178) : cs.onSurfaceVariant;
    final textShadows = hasImage
        ? const [
            Shadow(
              color: Color(0xCC000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ]
        : null;

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: hasImage ? 160 : 0),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: hasImage ? 16 : 12,
          vertical: hasImage ? 12 : 10,
        ),
        child: Align(
          alignment:
              hasImage ? Alignment.bottomLeft : Alignment.centerLeft,
          child: Row(
            children: [
              if (!hasImage) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: hasImage ? 16 : 15,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                        shadows: textShadows,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sublabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sublabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: sublabelColor,
                          shadows: textShadows,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (preset.id != 'default')
                IconButton(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: hasImage ? Colors.white : cs.onSurfaceVariant,
                  ),
                  tooltip: 'Menu',
                  onPressed: () =>
                      _showPresetActions(context, preset, isActive),
                ),
            ],
          ),
        ),
      ),
    );

    final Widget base;
    if (hasImage) {
      base = Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(bgBytes, fit: BoxFit.cover, gaplessPlayback: true),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x4D000000), Color(0xCC000000)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: baseBorder,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      );
    } else {
      base = GlassSurface(
        borderRadius: BorderRadius.circular(12),
        border: baseBorder,
        tint: tint,
        child: const SizedBox.expand(),
      );
    }

    final activeHighlight = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isActive ? accent.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? accent.withValues(alpha: 0.5) : Colors.transparent,
          width: highlightWidth,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(child: IgnorePointer(child: base)),
            Positioned.fill(child: IgnorePointer(child: activeHighlight)),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isActive ? null : () => _applyPreset(preset),
                child: content,
              ),
            ),
          ],
        ),
      ),
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
    GlazeBottomSheet.show<void>(
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
