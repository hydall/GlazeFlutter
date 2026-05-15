import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/theme_preset.dart';
import '../../shared/theme/theme_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';

// ─── Palette (mirrors Glaze JS PRESET_COLORS / PRESET_UI_COLORS) ──────────────

const _presetColors = [
  '#7996CE', '#E0555D', '#4BB34B', '#FFA000',
  '#8858C9', '#333333', '#007AFF', '#FF2D55',
  '#FFFFFF', '#000000', '#19191A', '#B0B8C1',
];

const _presetUiColors = [
  '#FFFFFF', '#19191A', '#7996CE', '#E0555D',
  '#4BB34B', '#FFA000', '#8858C9', '#333333',
];

// ─── Color helpers ────────────────────────────────────────────────────────────

Color _hex(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
  if (clean.length == 8) return Color(int.parse(clean, radix: 16));
  return const Color(0xFF7996CE);
}

String _toHex(Color c) {
  final r = (c.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b'.toUpperCase();
}

// ─── Main screen ──────────────────────────────────────────────────────────────

class ThemeEditorScreen extends ConsumerStatefulWidget {
  const ThemeEditorScreen({super.key});

  @override
  ConsumerState<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends ConsumerState<ThemeEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  ThemePreset get _preset => ref.read(themeProvider).activePreset;

  /// Live-update: apply immediately to state, debounce disk write.
  void _update(ThemePreset Function(ThemePreset) fn) {
    final next = fn(_preset);
    ref.read(themeProvider.notifier).updatePreset(next);
  }

  @override
  Widget build(BuildContext context) {
    final preset = ref.watch(themeProvider).activePreset;
    final isDefault = preset.id == 'default';

    return GlazeScaffold(
      title: preset.name,
      onBack: () => Navigator.pop(context),
      body: Column(
        children: [
          if (isDefault)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: context.cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Default theme cannot be edited. Import or create a new theme to customise.',
                        style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          TabBar(
            controller: _tabCtrl,
            tabs: const [Tab(text: 'General'), Tab(text: 'Chat')],
          ),
          Expanded(
            child: AbsorbPointer(
              absorbing: isDefault,
              child: Opacity(
                opacity: isDefault ? 0.45 : 1.0,
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _GeneralTab(preset: preset, onUpdate: _update),
                    _ChatTab(preset: preset, onUpdate: _update),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── General Tab ─────────────────────────────────────────────────────────────

class _GeneralTab extends StatelessWidget {
  final ThemePreset preset;
  final void Function(ThemePreset Function(ThemePreset)) onUpdate;

  const _GeneralTab({required this.preset, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── Accent Color ──
        _SectionHeader('Accent Color'),
        _ColorRow(
          label: 'Accent',
          value: preset.accentColor,
          palette: _presetColors,
          allowNull: false,
          onChanged: (v) => onUpdate((p) => p.copyWith(accentColor: v ?? '#7996CE')),
        ),
        const _Divider(),

        // ── App Interface Font ──
        _SectionHeader('App Interface Font'),
        _FontModeRow(
          label: 'Font',
          mode: preset.uiFontMode,
          modes: const ['glaze', 'system'],
          modeLabels: const ['Glaze (Inter)', 'System'],
          onChanged: (v) => onUpdate((p) => p.copyWith(uiFontMode: v)),
        ),
        _ColorRow(
          label: 'Text Color',
          value: preset.uiTextColor,
          palette: _presetUiColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(uiTextColor: v)),
        ),
        _ColorRow(
          label: 'Secondary Text',
          value: preset.uiTextGrayColor,
          palette: _presetUiColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(uiTextGrayColor: v)),
        ),
        _FontSizeRow(
          label: 'Font Size',
          value: preset.uiFontSize,
          min: 12,
          max: 20,
          onChanged: (v) => onUpdate((p) => p.copyWith(uiFontSize: v)),
        ),
        _SliderRow(
          label: 'Letter Spacing',
          value: preset.uiLetterSpacing,
          min: -1,
          max: 3,
          divisions: 8,
          unit: 'px',
          onChanged: (v) => onUpdate((p) => p.copyWith(uiLetterSpacing: v)),
        ),
        const _Divider(),

        // ── UI Effects ──
        _SectionHeader('UI Effects'),
        _ColorRow(
          label: 'UI Color',
          value: preset.uiColor,
          palette: _presetUiColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(uiColor: v)),
        ),
        _SliderRow(
          label: 'Opacity',
          value: preset.elementOpacity,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          unit: '%',
          displayMultiplier: 100,
          onChanged: (v) => onUpdate((p) => p.copyWith(elementOpacity: v)),
        ),
        _SliderRow(
          label: 'Blur',
          value: preset.elementBlur,
          min: 0,
          max: 40,
          divisions: 40,
          unit: 'px',
          onChanged: (v) => onUpdate((p) => p.copyWith(elementBlur: v)),
        ),
        const _Divider(),

        // ── Border ──
        _SectionHeader('Border'),
        _ColorRow(
          label: 'Border Color',
          value: preset.borderColor,
          palette: _presetUiColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(borderColor: v)),
        ),
        _SliderRow(
          label: 'Border Width',
          value: preset.borderWidth,
          min: 0,
          max: 5,
          divisions: 10,
          unit: 'px',
          onChanged: (v) => onUpdate((p) => p.copyWith(borderWidth: v)),
        ),
        _SliderRow(
          label: 'Border Opacity',
          value: preset.borderOpacity,
          min: 0,
          max: 1,
          divisions: 20,
          unit: '%',
          displayMultiplier: 100,
          onChanged: (v) => onUpdate((p) => p.copyWith(borderOpacity: v)),
        ),
        const _Divider(),

        // ── Noise Texture ──
        _SectionHeader('Noise Texture'),
        _SliderRow(
          label: 'Noise Opacity',
          value: preset.noiseOpacity,
          min: 0,
          max: 0.15,
          divisions: 30,
          unit: '%',
          displayMultiplier: 100,
          onChanged: (v) => onUpdate((p) => p.copyWith(noiseOpacity: v)),
        ),
        _SliderRow(
          label: 'Noise Intensity',
          value: preset.noiseIntensity,
          min: 0.1,
          max: 2,
          divisions: 19,
          unit: '',
          onChanged: (v) => onUpdate((p) => p.copyWith(noiseIntensity: v)),
        ),
        const _Divider(),

        // ── Background ──
        _SectionHeader('Background'),
        _SliderRow(
          label: 'Background Dimming',
          value: preset.bgOpacity,
          min: 0,
          max: 1,
          divisions: 20,
          unit: '%',
          displayMultiplier: 100,
          onChanged: (v) => onUpdate((p) => p.copyWith(bgOpacity: v)),
        ),
        _SliderRow(
          label: 'Background Blur',
          value: preset.bgBlur,
          min: 0,
          max: 20,
          divisions: 20,
          unit: 'px',
          onChanged: (v) => onUpdate((p) => p.copyWith(bgBlur: v)),
        ),
        _SliderRow(
          label: 'BG Noise Opacity',
          value: preset.bgNoiseOpacity,
          min: 0,
          max: 0.2,
          divisions: 40,
          unit: '%',
          displayMultiplier: 100,
          onChanged: (v) => onUpdate((p) => p.copyWith(bgNoiseOpacity: v)),
        ),
        _SliderRow(
          label: 'BG Noise Intensity',
          value: preset.bgNoiseIntensity,
          min: 0.1,
          max: 2,
          divisions: 19,
          unit: '',
          onChanged: (v) => onUpdate((p) => p.copyWith(bgNoiseIntensity: v)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Chat Tab ─────────────────────────────────────────────────────────────────

class _ChatTab extends StatefulWidget {
  final ThemePreset preset;
  final void Function(ThemePreset Function(ThemePreset)) onUpdate;

  const _ChatTab({required this.preset, required this.onUpdate});

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> with SingleTickerProviderStateMixin {
  late TabController _subCtrl;

  @override
  void initState() {
    super.initState();
    _subCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _subCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _subCtrl,
          tabs: const [Tab(text: 'Font'), Tab(text: 'Colors')],
          tabAlignment: TabAlignment.start,
          isScrollable: true,
        ),
        Expanded(
          child: TabBarView(
            controller: _subCtrl,
            children: [
              _ChatFontTab(preset: widget.preset, onUpdate: widget.onUpdate),
              _ChatColorsTab(preset: widget.preset, onUpdate: widget.onUpdate),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Chat → Font ──────────────────────────────────────────────────────────────

class _ChatFontTab extends StatelessWidget {
  final ThemePreset preset;
  final void Function(ThemePreset Function(ThemePreset)) onUpdate;

  const _ChatFontTab({required this.preset, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionHeader('Chat Messages Font'),
        _FontModeRow(
          label: 'Font',
          mode: preset.chatFontMode,
          modes: const ['ui', 'glaze', 'system'],
          modeLabels: const ['Same as UI', 'Glaze (Inter)', 'System'],
          onChanged: (v) => onUpdate((p) => p.copyWith(chatFontMode: v)),
        ),
        _FontSizeRow(
          label: 'Font Size',
          value: preset.chatFontSize,
          min: 12,
          max: 24,
          onChanged: (v) => onUpdate((p) => p.copyWith(chatFontSize: v)),
        ),
        _SliderRow(
          label: 'Letter Spacing',
          value: preset.chatLetterSpacing,
          min: -1,
          max: 3,
          divisions: 8,
          unit: 'px',
          onChanged: (v) => onUpdate((p) => p.copyWith(chatLetterSpacing: v)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Chat → Colors ────────────────────────────────────────────────────────────

class _ChatColorsTab extends StatelessWidget {
  final ThemePreset preset;
  final void Function(ThemePreset Function(ThemePreset)) onUpdate;

  const _ChatColorsTab({required this.preset, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final isBubble = preset.chatLayout == 'bubble';
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── Bubble Colors ──
        _SectionHeader('Bubble Colors'),
        if (!isBubble)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Switch to Bubble layout to configure bubble colors.',
              style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
            ),
          )
        else ...[
          _ColorRow(
            label: 'User Bubble',
            value: preset.userBubbleColor,
            palette: _presetColors,
            allowNull: true,
            nullLabel: 'Auto',
            onChanged: (v) => onUpdate((p) => p.copyWith(userBubbleColor: v)),
          ),
          _ColorRow(
            label: 'Char Bubble',
            value: preset.charBubbleColor,
            palette: _presetColors,
            allowNull: true,
            nullLabel: 'Auto',
            onChanged: (v) => onUpdate((p) => p.copyWith(charBubbleColor: v)),
          ),
        ],
        const _Divider(),

        // ── Reply (Quote) Colors ──
        _SectionHeader('Reply Colors'),
        _ColorRow(
          label: 'User Quote',
          value: preset.userQuoteColor,
          palette: _presetColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(userQuoteColor: v)),
        ),
        _ColorRow(
          label: 'Char Quote',
          value: preset.charQuoteColor,
          palette: _presetColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(charQuoteColor: v)),
        ),
        const _Divider(),

        // ── Text Colors ──
        _SectionHeader('Text Colors'),
        _ColorRow(
          label: 'User Text',
          value: preset.userTextColor,
          palette: _presetColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(userTextColor: v)),
        ),
        _ColorRow(
          label: 'Char Text',
          value: preset.charTextColor,
          palette: _presetColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(charTextColor: v)),
        ),
        const _Divider(),

        // ── Italic Colors ──
        _SectionHeader('Italic (Action) Colors'),
        _ColorRow(
          label: 'User Italic',
          value: preset.userItalicColor,
          palette: _presetColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(userItalicColor: v)),
        ),
        _ColorRow(
          label: 'Char Italic',
          value: preset.charItalicColor,
          palette: _presetColors,
          allowNull: true,
          nullLabel: 'Auto',
          onChanged: (v) => onUpdate((p) => p.copyWith(charItalicColor: v)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Shared row widgets ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 16, endIndent: 16, color: context.cs.outlineVariant);
  }
}

// ─── Slider row ───────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final double displayMultiplier;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChanged,
    this.displayMultiplier = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final display = (value * displayMultiplier);
    final displayStr = display == display.roundToDouble()
        ? display.toInt().toString()
        : display.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 14, color: context.cs.onSurface)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              unit == '%' ? '$displayStr%' : unit.isEmpty ? displayStr : '$displayStr$unit',
              style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Font size row (System / Custom toggle + slider) ─────────────────────────

class _FontSizeRow extends StatelessWidget {
  final String label;
  final dynamic value; // 'system' or num
  final double min;
  final double max;
  final ValueChanged<dynamic> onChanged;

  const _FontSizeRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  bool get _isSystem => value is String;
  double get _numVal => _isSystem ? 14.0 : (value as num).toDouble();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(label, style: TextStyle(fontSize: 14, color: context.cs.onSurface)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => onChanged(_isSystem ? 14.0 : 'system'),
                child: Text(
                  _isSystem ? 'System' : '${_numVal.toInt()}px',
                  style: TextStyle(color: context.cs.primary),
                ),
              ),
            ],
          ),
        ),
        if (!_isSystem)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 130),
                Expanded(
                  child: Slider(
                    value: _numVal.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: (max - min).toInt(),
                    onChanged: (v) => onChanged(v),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${_numVal.toInt()}px',
                    style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Font mode row ───────────────────────────────────────────────────────────

class _FontModeRow extends StatelessWidget {
  final String label;
  final String mode;
  final List<String> modes;
  final List<String> modeLabels;
  final ValueChanged<String> onChanged;

  const _FontModeRow({
    required this.label,
    required this.mode,
    required this.modes,
    required this.modeLabels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 14, color: context.cs.onSurface)),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: mode,
            onSelected: onChanged,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  modeLabels[modes.indexOf(mode).clamp(0, modeLabels.length - 1)],
                  style: TextStyle(color: context.cs.primary, fontSize: 14),
                ),
                Icon(Icons.arrow_drop_down, color: context.cs.primary),
              ],
            ),
            itemBuilder: (_) => List.generate(
              modes.length,
              (i) => PopupMenuItem(value: modes[i], child: Text(modeLabels[i])),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Color row ───────────────────────────────────────────────────────────────

class _ColorRow extends StatelessWidget {
  final String label;
  final String? value; // null = auto
  final List<String> palette;
  final bool allowNull;
  final String nullLabel;
  final ValueChanged<String?> onChanged;

  const _ColorRow({
    required this.label,
    required this.value,
    required this.palette,
    required this.allowNull,
    required this.onChanged,
    this.nullLabel = 'Auto',
  });

  @override
  Widget build(BuildContext context) {
    final current = value != null && value!.isNotEmpty ? _hex(value!) : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      title: Text(label, style: TextStyle(fontSize: 14, color: context.cs.onSurface)),
      trailing: GestureDetector(
        onTap: () => _openPicker(context),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: current ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: context.cs.outlineVariant,
              width: current == null ? 1.5 : 1,
            ),
          ),
          child: current == null
              ? Icon(Icons.auto_awesome, size: 16, color: context.cs.onSurfaceVariant)
              : null,
        ),
      ),
      onTap: () => _openPicker(context),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ColorPickerSheet(
        current: value,
        palette: palette,
        allowNull: allowNull,
        nullLabel: nullLabel,
      ),
    );
    if (result == '' && allowNull) {
      onChanged(null);
    } else if (result != null) {
      onChanged(result);
    }
  }
}

// ─── Color picker bottom sheet ────────────────────────────────────────────────

class _ColorPickerSheet extends StatefulWidget {
  final String? current;
  final List<String> palette;
  final bool allowNull;
  final String nullLabel;

  const _ColorPickerSheet({
    required this.current,
    required this.palette,
    required this.allowNull,
    required this.nullLabel,
  });

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late TextEditingController _hexCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(text: widget.current ?? '');
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _submit(String hex) {
    final clean = hex.trim();
    if (clean.isEmpty) {
      if (widget.allowNull) Navigator.pop(context, '');
      return;
    }
    final h = clean.startsWith('#') ? clean : '#$clean';
    final parsed = _parseHexSafe(h);
    if (parsed == null) {
      setState(() => _error = 'Invalid hex color');
      return;
    }
    Navigator.pop(context, _toHex(parsed));
  }

  Color? _parseHexSafe(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
      if (clean.length == 8) return Color(int.parse(clean, radix: 16));
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Palette
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (widget.allowNull)
                    GestureDetector(
                      onTap: () => Navigator.pop(context, ''),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant, width: 1.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.auto_awesome, size: 18, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ...widget.palette.map((hex) {
                    final color = _hex(hex);
                    final isSelected = widget.current?.toUpperCase() == hex.toUpperCase();
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, hex.toUpperCase()),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? cs.primary : cs.outlineVariant,
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                size: 20,
                                color: color.computeLuminance() > 0.4 ? Colors.black : Colors.white,
                              )
                            : null,
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),
              // Hex input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hexCtrl,
                      decoration: InputDecoration(
                        hintText: '#7996CE',
                        labelText: 'Hex Color',
                        errorText: _error,
                        prefixText: _hexCtrl.text.startsWith('#') ? null : '#',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: _submit,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => _submit(_hexCtrl.text),
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
