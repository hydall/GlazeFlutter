import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/models/preset.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/global_regex_provider.dart';
import '../../core/utils/id_generator.dart';
import '../presets/preset_list_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/sheet_view.dart';

class RegexListScreen extends ConsumerStatefulWidget {
  final bool startExpanded;
  const RegexListScreen({super.key, this.startExpanded = false});

  @override
  ConsumerState<RegexListScreen> createState() => _RegexListScreenState();
}

class _RegexListScreenState extends ConsumerState<RegexListScreen> {
  String _view = 'list';
  PresetRegex? _activeScript;
  bool _isPresetScript = false;
  Timer? _saveTimer;

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _selectScript(PresetRegex script, {required bool isPreset}) {
    setState(() {
      _activeScript = script;
      _isPresetScript = isPreset;
      _view = 'edit';
    });
  }

  void _goBack() {
    if (_view == 'edit') {
      _saveTimer?.cancel();
      final s = _activeScript;
      if (s != null) _saveActiveScript(s);
      setState(() {
        _view = 'list';
        _activeScript = null;
        _isPresetScript = false;
      });
    }
  }

  void _goBackFromList() {
    if (widget.startExpanded) {
      context.go('/tools');
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ── Script changes ───────────────────────────────────────────────────────────

  void _onScriptChanged(PresetRegex updated) {
    setState(() => _activeScript = updated);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _saveActiveScript(updated);
    });
  }

  Future<void> _saveActiveScript(PresetRegex script) async {
    if (_isPresetScript) {
      final activePresetId = ref.read(activePresetIdProvider);
      if (activePresetId == null) return;
      final presets = ref.read(presetListProvider).value ?? [];
      final preset = presets.where((p) => p.id == activePresetId).firstOrNull;
      if (preset == null) return;
      final updated = preset.regexes.map((r) => r.id == script.id ? script : r).toList();
      await ref.read(presetListProvider.notifier).updatePreset(preset.copyWith(regexes: updated));
    } else {
      await ref.read(globalRegexProvider.notifier).updateRegex(script);
    }
  }

  Future<void> _toggleScript(PresetRegex script, bool enabled, {required bool isPreset}) async {
    final updated = script.copyWith(disabled: !enabled);
    if (isPreset) {
      final activePresetId = ref.read(activePresetIdProvider);
      if (activePresetId == null) return;
      final presets = ref.read(presetListProvider).value ?? [];
      final preset = presets.where((p) => p.id == activePresetId).firstOrNull;
      if (preset == null) return;
      final updatedRegexes = preset.regexes.map((r) => r.id == script.id ? updated : r).toList();
      await ref.read(presetListProvider.notifier).updatePreset(preset.copyWith(regexes: updatedRegexes));
    } else {
      await ref.read(globalRegexProvider.notifier).updateRegex(updated);
    }
  }

  Future<void> _deleteScript(PresetRegex script, bool isPreset) async {
    if (isPreset) {
      final activePresetId = ref.read(activePresetIdProvider);
      if (activePresetId == null) return;
      final presets = ref.read(presetListProvider).value ?? [];
      final preset = presets.where((p) => p.id == activePresetId).firstOrNull;
      if (preset == null) return;
      final updatedRegexes = preset.regexes.where((r) => r.id != script.id).toList();
      await ref.read(presetListProvider.notifier).updatePreset(preset.copyWith(regexes: updatedRegexes));
    } else {
      await ref.read(globalRegexProvider.notifier).removeRegex(script.id);
    }
  }

  Future<PresetRegex?> _addPresetRegex() async {
    final activePresetId = ref.read(activePresetIdProvider);
    if (activePresetId == null) return null;
    final presets = ref.read(presetListProvider).value ?? [];
    final preset = presets.where((p) => p.id == activePresetId).firstOrNull;
    if (preset == null) return null;
    final newScript = PresetRegex(id: generateId(), name: 'New Script', regex: '');
    await ref.read(presetListProvider.notifier).updatePreset(
      preset.copyWith(regexes: [...preset.regexes, newScript]),
    );
    return newScript;
  }

  PresetRegex _addGlobalRegex() {
    final newScript = PresetRegex(id: generateId(), name: 'New Global Script', regex: '');
    ref.read(globalRegexProvider.notifier).addRegex(newScript);
    return newScript;
  }

  // ── Menus ────────────────────────────────────────────────────────────────────

  void _showScriptMenu(BuildContext context, PresetRegex script, bool isPreset) {
    GlazeBottomSheet.show<void>(
      context,
      title: script.name,
      items: [
        BottomSheetItem(
          icon: Icons.download_outlined,
          label: 'action_export'.tr(),
          onTap: () async {
            Navigator.of(context, rootNavigator: true).pop();
            await _exportScript(context, script);
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          iconColor: const Color(0xFFFF4444),
          label: 'action_delete_msg'.tr(),
          isDestructive: true,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _deleteScript(script, isPreset);
          },
        ),
      ],
    );
  }

  void _showAddMenu(BuildContext context) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'menu_regex'.tr(),
      items: [
        BottomSheetItem(
          icon: Icons.label_outline,
          label: 'regex_add_to_preset'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _showDestinationMenu(context, toPreset: true);
          },
        ),
        BottomSheetItem(
          icon: Icons.public,
          label: 'regex_add_globally'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _showDestinationMenu(context, toPreset: false);
          },
        ),
      ],
    );
  }

  void _showDestinationMenu(BuildContext context, {required bool toPreset}) {
    String title;
    if (toPreset) {
      final activePresetId = ref.read(activePresetIdProvider);
      final presets = ref.read(presetListProvider).value ?? [];
      final preset = activePresetId != null
          ? presets.where((p) => p.id == activePresetId).firstOrNull
          : presets.firstOrNull;
      title = preset?.name ?? 'label_active_preset'.tr();
    } else {
      title = 'regex_global_scripts'.tr();
    }

    GlazeBottomSheet.show<void>(
      context,
      title: title,
      items: [
        BottomSheetItem(
          icon: Icons.add,
          label: 'action_create_new'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            if (toPreset) {
              _addPresetRegex().then((s) {
                if (s != null && mounted) _selectScript(s, isPreset: true);
              });
            } else {
              final s = _addGlobalRegex();
              _selectScript(s, isPreset: false);
            }
          },
        ),
        BottomSheetItem(
          icon: Icons.upload_file_outlined,
          label: 'action_import'.tr(),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _importRegex(context, globally: !toPreset);
          },
        ),
      ],
    );
  }

  // ── Export / Import ──────────────────────────────────────────────────────────

  Future<void> _exportScript(BuildContext context, PresetRegex script) async {
    final json = const JsonEncoder.withIndent('  ').convert(script.toJson());
    final safe = script.name.replaceAll(RegExp(r'[^\w\-]'), '_');
    final filename = 'regex-$safe.json';
    try {
      await FileExportService.export(data: json, filename: filename, subfolder: 'regexes');
      if (context.mounted) GlazeToast.show(context, 'export_success'.tr());
    } catch (e) {
      if (context.mounted) GlazeToast.error(context, '${'settings_err_failed'.tr()} ', e);
    }
  }

  Future<void> _importRegex(BuildContext context, {required bool globally}) async {
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
      final List<dynamic> combinedRaw = [];
      for (final picked in result.files) {
        late Uint8List bytes;
        if (picked.bytes != null && picked.bytes!.isNotEmpty) {
          bytes = picked.bytes!;
        } else if (picked.path != null && picked.path!.isNotEmpty) {
          bytes = await File(picked.path!).readAsBytes();
        } else {
          continue;
        }
        if (picked.name.toLowerCase().endsWith('.zip')) {
          final archive = ZipDecoder().decodeBytes(bytes);
          for (final entry in archive) {
            if (!entry.isFile || !entry.name.toLowerCase().endsWith('.json')) continue;
            _appendFromJson(utf8.decode(entry.content as List<int>), combinedRaw);
          }
        } else {
          _appendFromJson(utf8.decode(bytes), combinedRaw);
        }
      }

      if (combinedRaw.isEmpty) {
        if (context.mounted) GlazeToast.show(context, 'no_results'.tr());
        return;
      }

      if (globally) {
        await ref.read(globalRegexProvider.notifier).importFromJsBackup(combinedRaw);
        if (context.mounted) GlazeToast.show(context, 'import_success'.tr());
      } else {
        final activePresetId = ref.read(activePresetIdProvider);
        if (activePresetId == null) {
          if (context.mounted) GlazeToast.show(context, 'label_active_preset'.tr());
          return;
        }
        final presets = ref.read(presetListProvider).value ?? [];
        final preset = presets.where((p) => p.id == activePresetId).firstOrNull;
        if (preset == null) {
          if (context.mounted) GlazeToast.show(context, 'no_results'.tr());
          return;
        }
        final newRegexes = _normalizeRawRegexList(combinedRaw);
        await ref.read(presetListProvider.notifier).updatePreset(
          preset.copyWith(regexes: [...preset.regexes, ...newRegexes]),
        );
        if (context.mounted) {
          GlazeToast.show(context, 'import_success'.tr());
        }
      }
    } catch (e) {
      if (context.mounted) GlazeToast.error(context, '${'settings_err_failed'.tr()} ', e);
    }
  }

  void _appendFromJson(String jsonStr, List<dynamic> out) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        out.addAll(decoded);
      } else if (decoded is Map<String, dynamic>) {
        out.add(decoded);
      }
    } catch (_) {}
  }

  List<PresetRegex> _normalizeRawRegexList(List<dynamic> rawList) {
    final result = <PresetRegex>[];
    for (final r in rawList) {
      if (r is! Map<String, dynamic>) continue;
      final m = normalizeJsGlobalRegex(Map<String, dynamic>.from(r));
      if (!m.containsKey('id')) m['id'] = generateId();
      if (r['isEnabled'] is bool) m['disabled'] = !(r['isEnabled'] as bool);
      try { result.add(PresetRegex.fromJson(m)); } catch (_) {}
    }
    return result;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final presetsAsync = ref.watch(presetListProvider);
    final globalAsync = ref.watch(globalRegexProvider);
    final activePresetId = ref.watch(activePresetIdProvider);

    final presets = presetsAsync.valueOrNull ?? [];
    final activePreset = activePresetId != null
        ? presets.where((p) => p.id == activePresetId).firstOrNull
        : presets.firstOrNull;
    final presetRegexes = activePreset?.regexes ?? <PresetRegex>[];
    final globalRegexes = globalAsync.valueOrNull ?? <PresetRegex>[];

    final isEdit = _view == 'edit';

    return SheetView(
      startExpanded: widget.startExpanded,
      title: isEdit ? 'regex_editor'.tr() : 'menu_regex'.tr(),
      showBack: isEdit || widget.startExpanded,
      onBack: isEdit ? _goBack : _goBackFromList,
      body: isEdit && _activeScript != null
          ? _RegexEditView(
              key: ValueKey(_activeScript!.id),
              script: _activeScript!,
              onChanged: _onScriptChanged,
            )
          : _buildListView(context, activePreset, presetRegexes, globalRegexes),
      floatingActionButton: isEdit
          ? null
          : FloatingActionButton.small(
              onPressed: () => _showAddMenu(context),
              backgroundColor: context.cs.primary,
              foregroundColor: Colors.black,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildListView(
    BuildContext context,
    Preset? activePreset,
    List<PresetRegex> presetRegexes,
    List<PresetRegex> globalRegexes,
  ) {
    return Builder(
      builder: (innerContext) => ListView(
      key: const PageStorageKey('regex_list'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16).add(
        EdgeInsets.only(
          top: MediaQuery.paddingOf(innerContext).top,
          bottom: MediaQuery.paddingOf(innerContext).bottom,
        ),
      ),
      children: [
        if (presetRegexes.isNotEmpty) ...[
          _SectionTitle('regex_preset_scripts'.tr()),
          if (activePreset != null)
            _PresetChip(
              presetName: activePreset.name,
              onTap: () => context.go('/tools/presets'),
            ),
          for (final r in presetRegexes)
            _ScriptListItem(
              script: r,
              onTap: () => _selectScript(r, isPreset: true),
              onToggle: (v) => _toggleScript(r, v, isPreset: true),
              onMore: () => _showScriptMenu(context, r, true),
            ),
          const SizedBox(height: 16),
        ],
        _SectionTitle('regex_global_scripts'.tr()),
        if (globalRegexes.isEmpty)
          const _EmptyState()
        else
          for (final r in globalRegexes)
            _ScriptListItem(
              script: r,
              onTap: () => _selectScript(r, isPreset: false),
              onToggle: (v) => _toggleScript(r, v, isPreset: false),
              onMore: () => _showScriptMenu(context, r, false),
            ),
        const SizedBox(height: 80),
      ],
    ));
  }
}

// ── List UI widgets ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.cs.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String presetName;
  final VoidCallback onTap;
  const _PresetChip({required this.presetName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            color: context.cs.primary.withValues(alpha: 0.12),
            border: Border.all(color: context.cs.primary.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 14, color: context.cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  presetName,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.cs.primary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: context.cs.primary.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptListItem extends StatelessWidget {
  final PresetRegex script;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMore;

  const _ScriptListItem({
    required this.script,
    required this.onTap,
    required this.onToggle,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        script.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: script.disabled ? context.cs.onSurfaceVariant : context.cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (script.regex.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          script.regex,
                          style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: !script.disabled,
                  onChanged: onToggle,
                  activeTrackColor: context.cs.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMore,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
                    child: Icon(Icons.more_vert, size: 20, color: context.cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          'no_results'.tr(),
          style: TextStyle(color: context.cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ── Edit view ──────────────────────────────────────────────────────────────────

class _RegexEditView extends StatefulWidget {
  final PresetRegex script;
  final ValueChanged<PresetRegex> onChanged;

  const _RegexEditView({super.key, required this.script, required this.onChanged});

  @override
  State<_RegexEditView> createState() => _RegexEditViewState();
}

class _RegexEditViewState extends State<_RegexEditView> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _regexCtrl;
  late final TextEditingController _replacementCtrl;
  late final TextEditingController _trimOutCtrl;
  late final TextEditingController _minDepthCtrl;
  late final TextEditingController _maxDepthCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.script;
    _nameCtrl = TextEditingController(text: s.name);
    _regexCtrl = TextEditingController(text: s.regex);
    _replacementCtrl = TextEditingController(text: s.replacement);
    _trimOutCtrl = TextEditingController(text: s.trimOut);
    _minDepthCtrl = TextEditingController(text: s.minDepth?.toString() ?? '');
    _maxDepthCtrl = TextEditingController(text: s.maxDepth?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _regexCtrl.dispose();
    _replacementCtrl.dispose();
    _trimOutCtrl.dispose();
    _minDepthCtrl.dispose();
    _maxDepthCtrl.dispose();
    super.dispose();
  }

  void _update(PresetRegex updated) => widget.onChanged(updated);

  void _openMacroSelector() {
    final options = [
      ('0', "regex_macro_none".tr()),
      ('1', 'regex_macro_raw'.tr()),
      ('2', 'regex_macro_escaped'.tr()),
    ];
    GlazeBottomSheet.show<void>(
      context,
      title: 'regex_macros_find'.tr(),
      items: options.map((o) {
        return BottomSheetItem(
          label: o.$2,
          icon: widget.script.macroRules == o.$1 ? Icons.check : null,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _update(widget.script.copyWith(macroRules: o.$1));
          },
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.script;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80).add(
        EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top,
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
      ),
      children: [
        _MenuGroup(
          title: 'regex_script_settings'.tr(),
          children: [
            _SettingsTextField(label: 'regex_script_name'.tr(), controller: _nameCtrl, onChanged: (v) => _update(s.copyWith(name: v))),
            _SettingsTextField(label: 'regex_find'.tr(), controller: _regexCtrl, onChanged: (v) => _update(s.copyWith(regex: v))),
            _SettingsTextField(label: 'regex_replace_with'.tr(), controller: _replacementCtrl, onChanged: (v) => _update(s.copyWith(replacement: v)), maxLines: 3),
            _SettingsTextField(label: 'regex_trim_out'.tr(), controller: _trimOutCtrl, onChanged: (v) => _update(s.copyWith(trimOut: v)), maxLines: 2),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 500;
            final col1 = _buildCol1(context, s);
            final col2 = _buildCol2(context, s);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: col1), const SizedBox(width: 12), Expanded(child: col2)],
              );
            }
            return Column(children: [col1, const SizedBox(height: 12), col2]);
          },
        ),
      ],
    );
  }

  Widget _buildCol1(BuildContext context, PresetRegex s) {
    final placements = [
      (1, 'regex_user_input'.tr()),
      (2, 'regex_ai_output'.tr()),
      (3, 'regex_slash_commands'.tr()),
      (5, 'regex_world_info'.tr()),
      (6, 'regex_reasoning'.tr()),
    ];
    return Column(
      children: [
        _MenuGroup(
          title: 'regex_affects'.tr(),
          compact: true,
          children: placements.map((opt) {
            return _CheckboxOption(
              label: opt.$2,
              value: s.placement.contains(opt.$1),
              onChanged: (v) {
                final list = List<int>.from(s.placement);
                v ? list.add(opt.$1) : list.remove(opt.$1);
                _update(s.copyWith(placement: list));
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DepthInput(
                label: 'regex_min_depth'.tr(),
                controller: _minDepthCtrl,
                onChanged: (v) => _update(s.copyWith(minDepth: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DepthInput(
                label: 'regex_max_depth'.tr(),
                controller: _maxDepthCtrl,
                onChanged: (v) => _update(s.copyWith(maxDepth: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCol2(BuildContext context, PresetRegex s) {
    final ephemeralities = [
      (1, 'regex_alter_display'.tr()),
      (2, 'regex_alter_prompt'.tr()),
    ];
    final macroLabel = switch (s.macroRules) {
      '1' => 'regex_macro_raw'.tr(),
      '2' => 'regex_macro_escaped'.tr(),
      _ => "regex_macro_none".tr(),
    };
    return Column(
      children: [
        _MenuGroup(
          title: 'regex_other_options'.tr(),
          compact: true,
          children: [
            _CheckboxOption(
              label: 'regex_run_on_edit'.tr(),
              value: s.runOnEdit,
              onChanged: (v) => _update(s.copyWith(runOnEdit: v)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MenuGroup(
          title: 'regex_macros_find'.tr(),
          compact: true,
          children: [_MacroSelector(label: macroLabel, onTap: _openMacroSelector)],
        ),
        const SizedBox(height: 12),
        _MenuGroup(
          title: 'regex_ephemerality'.tr(),
          compact: true,
          children: ephemeralities.map((opt) {
            return _CheckboxOption(
              label: opt.$2,
              value: s.ephemerality.contains(opt.$1),
              onChanged: (v) {
                final list = List<int>.from(s.ephemerality);
                v ? list.add(opt.$1) : list.remove(opt.$1);
                _update(s.copyWith(ephemerality: list));
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Edit sub-widgets ────────────────────────────────────────────────────────────

class _MenuGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool compact;

  const _MenuGroup({required this.title, required this.children, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, compact ? 8 : 12, 16, compact ? 4 : 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.cs.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: Colors.white.withValues(alpha: 0.04)),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  const _SettingsTextField({
    required this.label,
    required this.controller,
    this.onChanged,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onChanged: onChanged,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckboxOption extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckboxOption({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: context.cs.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _DepthInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<int?> onChanged;

  const _DepthInput({required this.label, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 15),
            onChanged: (v) => onChanged(int.tryParse(v)),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'regex_unlimited_placeholder'.tr(),
              hintStyle: TextStyle(color: context.cs.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroSelector extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MacroSelector({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              Icon(Icons.expand_more, size: 20, color: context.cs.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
