import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/preset.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/global_regex_provider.dart';
import '../presets/preset_list_provider.dart';
import '../../core/utils/id_generator.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/sheet_view.dart';
import '../presets/widgets/regex_tile.dart';

class RegexListScreen extends ConsumerWidget {
  final bool startExpanded;
  const RegexListScreen({super.key, this.startExpanded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetsAsync = ref.watch(presetListProvider);
    final globalAsync = ref.watch(globalRegexProvider);
    final activePresetId = ref.watch(activePresetIdProvider);

    return SheetView(
      startExpanded: startExpanded,
      title: 'Regex Scripts',
      showBack: true,
      onBack: startExpanded
          ? () => context.go('/tools')
          : () => Navigator.of(context).maybePop(),
      body: presetsAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (presets) {
          final activePreset = activePresetId != null
              ? presets.where((p) => p.id == activePresetId).firstOrNull
              : (presets.isNotEmpty ? presets.first : null);

          final presetRegexes = activePreset?.regexes ?? <PresetRegex>[];
          final globalRegexes = globalAsync.valueOrNull ?? <PresetRegex>[];

          if (presetRegexes.isEmpty && globalRegexes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.code, size: 64, color: context.cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text('No regex scripts yet'),
                  const SizedBox(height: 8),
                  const Text(
                    'Add regex scripts from presets or globally',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          }

          return Builder(
            builder: (context) => ListView(
              key: const PageStorageKey('regex_list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16).add(
                EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top,
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
              ),
              children: [
                if (presetRegexes.isNotEmpty) ...[
                  _sectionHeader(
                    context,
                    'Preset Regexes',
                    activePreset?.name ?? 'Default',
                    Icons.label,
                  ),
                  for (final r in presetRegexes)
                    _PresetRegexItem(
                      regex: r,
                      presetId: activePreset!.id,
                      preset: activePreset,
                    ),
                  const SizedBox(height: 16),
                ],
                if (globalRegexes.isNotEmpty) ...[
                  _sectionHeader(context, 'Global Regexes', 'Always active', Icons.public),
                  for (final r in globalRegexes)
                    _GlobalRegexItem(regex: r),
                ],
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _showAddMenu(context, ref),
        backgroundColor: context.cs.primary,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.cs.primary),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: context.cs.onSurface)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(subtitle, style: TextStyle(fontSize: 11, color: context.cs.primary)),
          ),
        ],
      ),
    );
  }

  void _showAddMenu(BuildContext context, WidgetRef ref) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'Add Regex',
      items: [
        BottomSheetItem(
          icon: Icons.add_circle_outline,
          label: 'Add New',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _showDestinationMenu(context, ref, isImport: false);
          },
        ),
        BottomSheetItem(
          icon: Icons.file_upload_outlined,
          label: 'Import from File',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _showDestinationMenu(context, ref, isImport: true);
          },
        ),
      ],
    );
  }

  void _showDestinationMenu(BuildContext context, WidgetRef ref, {required bool isImport}) {
    GlazeBottomSheet.show<void>(
      context,
      title: isImport ? 'Import To' : 'Add To',
      items: [
        BottomSheetItem(
          icon: Icons.public,
          iconColor: context.cs.primary,
          label: 'Globally',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            if (isImport) {
              _importRegex(context, ref, globally: true);
            } else {
              _addGlobalRegex(ref);
            }
          },
        ),
        BottomSheetItem(
          icon: Icons.label,
          iconColor: context.cs.primary,
          label: 'To Active Preset',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            if (isImport) {
              _importRegex(context, ref, globally: false);
            } else {
              _addPresetRegex(ref);
            }
          },
        ),
      ],
    );
  }

  Future<void> _importRegex(BuildContext context, WidgetRef ref, {required bool globally}) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: Platform.isIOS ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isIOS ? null : ['json', 'zip'],
        allowMultiple: true,
        withData: true,
      );
    } catch (_) {}
    if (result == null || result.files.isEmpty) return;

    try {
      // Collect all raw regex entries across all picked files.
      final List<dynamic> combinedRaw = [];

      for (final picked in result.files) {
        late Uint8List bytes;
        if (picked.bytes != null && picked.bytes!.isNotEmpty) {
          bytes = picked.bytes!;
        } else if (picked.path != null && picked.path!.isNotEmpty) {
          bytes = await File(picked.path!).readAsBytes();
        } else {
          continue; // skip unreadable file
        }

        final name = (picked.name).toLowerCase();
        if (name.endsWith('.zip')) {
          // Extract all *.json files from the archive and merge their entries.
          final archive = ZipDecoder().decodeBytes(bytes);
          for (final entry in archive) {
            if (!entry.isFile) continue;
            if (!entry.name.toLowerCase().endsWith('.json')) continue;
            final jsonStr = utf8.decode(entry.content as List<int>);
            _appendFromJson(jsonStr, combinedRaw);
          }
        } else {
          // Plain JSON file.
          final jsonStr = utf8.decode(bytes);
          _appendFromJson(jsonStr, combinedRaw);
        }
      }

      if (combinedRaw.isEmpty) {
        if (context.mounted) GlazeToast.show(context, 'No regex scripts found in selected files');
        return;
      }

      if (globally) {
        await ref.read(globalRegexProvider.notifier).importFromJsBackup(combinedRaw);
        if (context.mounted) {
          GlazeToast.show(context, 'Imported ${combinedRaw.length} script(s) globally');
        }
      } else {
        final activePresetId = ref.read(activePresetIdProvider);
        if (activePresetId == null) {
          if (context.mounted) GlazeToast.show(context, 'No active preset');
          return;
        }
        final presets = ref.read(presetListProvider).value ?? [];
        final preset = presets.where((p) => p.id == activePresetId).firstOrNull;
        if (preset == null) {
          if (context.mounted) GlazeToast.show(context, 'Preset not found');
          return;
        }
        final newRegexes = _normalizeRawRegexList(combinedRaw);
        await ref.read(presetListProvider.notifier).updatePreset(
              preset.copyWith(regexes: [...preset.regexes, ...newRegexes]),
            );
        if (context.mounted) {
          GlazeToast.show(context, 'Imported ${newRegexes.length} script(s) to "${preset.name}"');
        }
      }
    } catch (e) {
      if (context.mounted) GlazeToast.error(context, 'Import failed: ', e);
    }
  }

  /// Parses a JSON string and appends found regex entries to [out].
  void _appendFromJson(String jsonStr, List<dynamic> out) {
    try {
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        out.addAll(decoded);
      } else if (decoded is Map<String, dynamic>) {
        out.add(decoded);
      }
    } catch (_) {
      // Skip malformed JSON files silently.
    }
  }

  List<PresetRegex> _normalizeRawRegexList(List<dynamic> rawList) {
    final result = <PresetRegex>[];
    for (int i = 0; i < rawList.length; i++) {
      final r = rawList[i];
      if (r is! Map<String, dynamic>) continue;
      final m = normalizeJsGlobalRegex(Map<String, dynamic>.from(r));
      if (!m.containsKey('id')) m['id'] = generateId();
      if (r['isEnabled'] is bool) m['disabled'] = !(r['isEnabled'] as bool);
      try {
        result.add(PresetRegex.fromJson(m));
      } catch (_) {}
    }
    return result;
  }

  void _addPresetRegex(WidgetRef ref) async {
    final activePresetId = ref.read(activePresetIdProvider);
    if (activePresetId == null) return;
    final presets = ref.read(presetListProvider).value ?? [];
    final preset = presets.where((p) => p.id == activePresetId).firstOrNull;
    if (preset == null) return;
    await ref.read(presetListProvider.notifier).updatePreset(
          preset.copyWith(regexes: [
            ...preset.regexes,
            PresetRegex(id: generateId(), name: 'New Script', regex: ''),
          ]),
        );
  }

  void _addGlobalRegex(WidgetRef ref) {
    ref.read(globalRegexProvider.notifier).addRegex(
          PresetRegex(id: generateId(), name: 'New Global Script', regex: ''),
        );
  }
}

class _PresetRegexItem extends ConsumerWidget {
  final PresetRegex regex;
  final String presetId;
  final Preset preset;

  const _PresetRegexItem({
    required this.regex,
    required this.presetId,
    required this.preset,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Icon(
                    regex.disabled ? Icons.code_off : Icons.code,
                    size: 16,
                    color: regex.disabled ? context.cs.onSurfaceVariant : context.cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'From: ${preset.name}',
                      style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
                    ),
                  ),
                  Switch(
                    value: !regex.disabled,
                    onChanged: (v) => _updateRegex(ref, regex.copyWith(disabled: !v)),
                    activeThumbColor: context.cs.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
            RegexTile(
              regex: regex,
              onChanged: (updated) => _updateRegex(ref, updated),
            ),
          ],
        ),
      ),
    );
  }

  void _updateRegex(WidgetRef ref, PresetRegex updated) async {
    final updatedRegexes = preset.regexes.map((r) {
      if (r.id == regex.id) return updated;
      return r;
    }).toList();
    await ref.read(presetListProvider.notifier).updatePreset(preset.copyWith(regexes: updatedRegexes));
  }
}

class _GlobalRegexItem extends ConsumerWidget {
  final PresetRegex regex;

  const _GlobalRegexItem({required this.regex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.cs.primary.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Icon(
                    regex.disabled ? Icons.public_off : Icons.public,
                    size: 16,
                    color: regex.disabled ? context.cs.onSurfaceVariant : context.cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Global', style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant))),
                  Switch(
                    value: !regex.disabled,
                    onChanged: (v) => ref.read(globalRegexProvider.notifier).updateRegex(regex.copyWith(disabled: !v)),
                    activeThumbColor: context.cs.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent.withValues(alpha: 0.7)),
                    onPressed: () => ref.read(globalRegexProvider.notifier).removeRegex(regex.id),
                  ),
                ],
              ),
            ),
            RegexTile(
              regex: regex,
              onChanged: (updated) => ref.read(globalRegexProvider.notifier).updateRegex(updated),
            ),
          ],
        ),
      ),
    );
  }
}
