import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/theme_preset.dart';
import '../../shared/theme/theme_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/menu_group.dart';
import 'theme_preview.dart';
import 'widgets/chat_layout_picker.dart';

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

Future<void> _pickCustomFont(
  BuildContext context,
  void Function(ThemePreset Function(ThemePreset)) onUpdate, {
  required bool isUi,
  required ThemePreset preset,
}) async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf', 'woff', 'woff2'],
      dialogTitle: 'Select Font File',
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return;
    final fontName = file.name.replaceAll(RegExp(r'\.(ttf|otf|woff2?)$', caseSensitive: false), '');
    final dataUri = 'data:font/ttf;base64,${base64Encode(bytes)}';
    if (isUi) {
      onUpdate((p) => p.copyWith(
        uiFontMode: 'custom',
        customFont: dataUri,
        customFontName: fontName,
      ));
    } else {
      onUpdate((p) => p.copyWith(
        chatFontMode: 'custom',
        chatFont: dataUri,
        chatFontName: fontName,
      ));
    }
  } catch (e) {
    if (context.mounted) {
      GlazeToast.error(context, 'Failed to load font: ', e);
    }
  }
}

// ─── Main screen ──────────────────────────────────────────────────────────────

class ThemeEditorScreen extends ConsumerStatefulWidget {
  const ThemeEditorScreen({super.key});

  @override
  ConsumerState<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends ConsumerState<ThemeEditorScreen> {
  int _activeTab = 0;
  Timer? _saveTimer;

  @override
  void dispose() {
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
    final topPad = MediaQuery.of(context).padding.top + 74.0;
    final tabHeight = 68.0;
    final warningHeight = isDefault ? 62.0 : 0.0;
    final totalTopPadding = topPad + warningHeight + tabHeight;

    return GlazeScaffold(
      title: preset.name,
      extendBodyBehindHeader: true,
      onBack: () => Navigator.pop(context),
      body: Stack(
        children: [
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: isDefault,
              child: Opacity(
                opacity: isDefault ? 0.45 : 1.0,
                child: IndexedStack(
                  index: _activeTab,
                  children: [
                    _GeneralTab(
                      preset: preset,
                      onUpdate: _update,
                      topPadding: totalTopPadding,
                    ),
                    _ChatTab(
                      preset: preset,
                      onUpdate: _update,
                      topPadding: totalTopPadding,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: topPad),
                if (isDefault)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: context.cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Default theme cannot be edited. Import or create a new theme to customise.',
                              style: TextStyle(
                                  fontSize: 12, color: context.cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: GlazeTabBar(
                    tabs: const [
                      GlazeTabItem(label: 'General', icon: Icons.tune),
                      GlazeTabItem(
                          label: 'Chat', icon: Icons.chat_bubble_outline),
                    ],
                    activeIndex: _activeTab,
                    onChanged: (i) => setState(() => _activeTab = i),
                  ),
                ),
              ],
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
  final double topPadding;

  const _GeneralTab({
    required this.preset,
    required this.onUpdate,
    required this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(0, topPadding + 8, 0, 8),
      children: [
        MenuGroup(
          header: 'Accent Color',
          items: [
            _ColorRow(
              label: 'Accent',
              value: preset.accentColor,
              palette: _presetColors,
              allowNull: false,
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(accentColor: v ?? '#7996CE')),
            ),
          ],
        ),
        MenuGroup(
          header: 'App Interface Font',
          items: [
            _FontModeRow(
              label: 'Font',
              mode: preset.uiFontMode,
              modes: const ['glaze', 'system', 'custom', 'google'],
              modeLabels: const ['Glaze (Inter)', 'System', 'Custom File', 'Google Fonts'],
              onChanged: (v) async {
                if (v == 'custom') {
                  await _pickCustomFont(context, onUpdate, isUi: true, preset: preset);
                } else if (v == 'google') {
                  await _pickGoogleFont(context, onUpdate, isUi: true, preset: preset);
                } else {
                  onUpdate((p) => p.copyWith(uiFontMode: v));
                }
              },
            ),
            if (preset.uiFontMode == 'google' && preset.googleFontName != null)
              _GoogleFontDisplayRow(
                fontName: preset.googleFontName!,
                onTap: () => _pickGoogleFont(context, onUpdate, isUi: true, preset: preset),
                onClear: () => onUpdate((p) => p.copyWith(uiFontMode: 'glaze', googleFontName: null)),
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
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(uiTextGrayColor: v)),
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
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(uiLetterSpacing: v)),
            ),
            _SliderRow(
              label: 'Font Weight',
              value: preset.uiFontWeight.toDouble(),
              min: 100,
              max: 900,
              divisions: 8,
              unit: '',
              onChanged: (v) => onUpdate(
                (p) => p.copyWith(uiFontWeight: _weightFromSlider(v)),
              ),
            ),
          ],
        ),
        MenuGroup(
          header: 'UI Elements',
          items: [
            const MenuSubHeader('Background'),
            _ColorRow(
              label: 'Color',
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
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(elementOpacity: v)),
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
            _SliderRow(
              label: 'Noise Opacity',
              value: preset.noiseOpacity,
              min: 0,
              max: 0.15,
              divisions: 30,
              unit: '%',
              displayMultiplier: 100,
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(noiseOpacity: v)),
            ),
            _SliderRow(
              label: 'Noise Intensity',
              value: preset.noiseIntensity,
              min: 0.1,
              max: 2,
              divisions: 19,
              unit: '',
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(noiseIntensity: v)),
            ),
            const MenuSubHeader('Border'),
            _ColorRow(
              label: 'Color',
              value: preset.borderColor,
              palette: _presetUiColors,
              allowNull: true,
              nullLabel: 'Auto',
              onChanged: (v) => onUpdate((p) => p.copyWith(borderColor: v)),
            ),
            _SliderRow(
              label: 'Width',
              value: preset.borderWidth,
              min: 0,
              max: 5,
              divisions: 10,
              unit: 'px',
              onChanged: (v) => onUpdate((p) => p.copyWith(borderWidth: v)),
            ),
            _SliderRow(
              label: 'Opacity',
              value: preset.borderOpacity,
              min: 0,
              max: 1,
              divisions: 20,
              unit: '%',
              displayMultiplier: 100,
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(borderOpacity: v)),
            ),
          ],
        ),
        MenuGroup(
          header: 'Background',
          items: [
            if (!preset.hasBgImage)
              _ColorRow(
                label: 'Color',
                value: preset.bgColor,
                palette: _presetUiColors,
                allowNull: true,
                nullLabel: 'Auto',
                onChanged: (v) => onUpdate((p) => p.copyWith(bgColor: v)),
              ),
            _BgImageRow(preset: preset, onUpdate: onUpdate),
            if (preset.hasBgImage) ...[
              _SliderRow(
                label: 'Background Dimming',
                // Slider reads as dimming amount (0 = no dim, 1 = full dim)
                // but `bgOpacity` stores image visibility (1 - dimming).
                value: 1.0 - preset.bgOpacity,
                min: 0,
                max: 1,
                divisions: 20,
                unit: '%',
                displayMultiplier: 100,
                onChanged: (v) =>
                    onUpdate((p) => p.copyWith(bgOpacity: 1.0 - v)),
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
                label: 'Dark Overlay',
                value: preset.bgDim,
                min: 0,
                max: 1,
                divisions: 20,
                unit: '%',
                displayMultiplier: 100,
                onChanged: (v) => onUpdate((p) => p.copyWith(bgDim: v)),
              ),
            ],
            _SliderRow(
              label: 'BG Noise Opacity',
              value: preset.bgNoiseOpacity,
              min: 0,
              max: 0.2,
              divisions: 40,
              unit: '%',
              displayMultiplier: 100,
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(bgNoiseOpacity: v)),
            ),
            _SliderRow(
              label: 'BG Noise Intensity',
              value: preset.bgNoiseIntensity,
              min: 0.1,
              max: 2,
              divisions: 19,
              unit: '',
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(bgNoiseIntensity: v)),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Chat Tab ─────────────────────────────────────────────────────────────────

class _ChatTab extends StatefulWidget {
  final ThemePreset preset;
  final void Function(ThemePreset Function(ThemePreset)) onUpdate;
  final double topPadding;

  const _ChatTab({
    required this.preset,
    required this.onUpdate,
    required this.topPadding,
  });

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  int _activeSubTab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: widget.topPadding),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: ThemeChatPreview(
            preset: widget.preset,
            borderColor: context.cs.outlineVariant,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: _LayoutPickerRow(
            value: widget.preset.chatLayout,
            onTap: () => _showLayoutPicker(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: GlazeTabBar(
            tabs: const [
              GlazeTabItem(label: 'Font', icon: Icons.text_fields),
              GlazeTabItem(label: 'Colors', icon: Icons.palette_outlined),
            ],
            activeIndex: _activeSubTab,
            onChanged: (i) => setState(() => _activeSubTab = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _activeSubTab,
            children: [
              _ChatFontTab(preset: widget.preset, onUpdate: widget.onUpdate),
              _ChatColorsTab(preset: widget.preset, onUpdate: widget.onUpdate),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showLayoutPicker(BuildContext context) {
    return showChatLayoutPicker(
      context,
      current: widget.preset.chatLayout,
      onSelect: (layout) =>
          widget.onUpdate((p) => p.copyWith(chatLayout: layout)),
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
        MenuGroup(
          header: 'Chat Messages Font',
          items: [
            _FontModeRow(
              label: 'Font',
              mode: preset.chatFontMode,
              modes: const ['ui', 'glaze', 'system', 'custom', 'google'],
              modeLabels: const ['Same as UI', 'Glaze (Inter)', 'System', 'Custom File', 'Google Fonts'],
              onChanged: (v) async {
                if (v == 'custom') {
                  await _pickCustomFont(context, onUpdate, isUi: false, preset: preset);
                } else if (v == 'google') {
                  await _pickGoogleFont(context, onUpdate, isUi: false, preset: preset);
                } else {
                  onUpdate((p) => p.copyWith(chatFontMode: v));
                }
              },
            ),
            if (preset.chatFontMode == 'google' && preset.chatGoogleFontName != null)
              _GoogleFontDisplayRow(
                fontName: preset.chatGoogleFontName!,
                onTap: () => _pickGoogleFont(context, onUpdate, isUi: false, preset: preset),
                onClear: () => onUpdate((p) => p.copyWith(chatFontMode: 'ui', chatGoogleFontName: null)),
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
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(chatLetterSpacing: v)),
            ),
            _SliderRow(
              label: 'User Weight',
              value: preset.userMessageFontWeight.toDouble(),
              min: 100,
              max: 900,
              divisions: 8,
              unit: '',
              onChanged: (v) => onUpdate(
                (p) => p.copyWith(userMessageFontWeight: _weightFromSlider(v)),
              ),
            ),
            _SliderRow(
              label: 'Char Weight',
              value: preset.charMessageFontWeight.toDouble(),
              min: 100,
              max: 900,
              divisions: 8,
              unit: '',
              onChanged: (v) => onUpdate(
                (p) => p.copyWith(charMessageFontWeight: _weightFromSlider(v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
        MenuGroup(
          header: 'Bubble Colors',
          items: [
            if (!isBubble)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  'Switch to Bubble layout to configure bubble colors.',
                  style: TextStyle(
                      fontSize: 12, color: context.cs.onSurfaceVariant),
                ),
              )
            else ...[
              _ColorRow(
                label: 'User Bubble',
                value: preset.userBubbleColor,
                palette: _presetColors,
                allowNull: true,
                nullLabel: 'Auto',
                onChanged: (v) =>
                    onUpdate((p) => p.copyWith(userBubbleColor: v)),
              ),
              _ColorRow(
                label: 'Char Bubble',
                value: preset.charBubbleColor,
                palette: _presetColors,
                allowNull: true,
                nullLabel: 'Auto',
                onChanged: (v) =>
                    onUpdate((p) => p.copyWith(charBubbleColor: v)),
              ),
              _SliderRow(
                label: 'User Radius',
                value: preset.userBubbleRadius,
                min: 0,
                max: 36,
                divisions: 36,
                unit: 'px',
                onChanged: (v) =>
                    onUpdate((p) => p.copyWith(userBubbleRadius: v)),
              ),
              _SliderRow(
                label: 'Char Radius',
                value: preset.charBubbleRadius,
                min: 0,
                max: 36,
                divisions: 36,
                unit: 'px',
                onChanged: (v) =>
                    onUpdate((p) => p.copyWith(charBubbleRadius: v)),
              ),
            ],
          ],
        ),
        MenuGroup(
          header: 'Identity',
          items: [
            _SwitchRow(
              label: 'User Avatar',
              value: preset.showUserAvatar,
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(showUserAvatar: v)),
            ),
            _SwitchRow(
              label: 'Char Avatar',
              value: preset.showCharAvatar,
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(showCharAvatar: v)),
            ),
            _SwitchRow(
              label: 'User Name',
              value: preset.showUserName,
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(showUserName: v)),
            ),
            _SwitchRow(
              label: 'Char Name',
              value: preset.showCharName,
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(showCharName: v)),
            ),
          ],
        ),
        MenuGroup(
          header: 'Reply Colors',
          items: [
            _ColorRow(
              label: 'User Quote',
              value: preset.userQuoteColor,
              palette: _presetColors,
              allowNull: true,
              nullLabel: 'Auto',
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(userQuoteColor: v)),
            ),
            _ColorRow(
              label: 'Char Quote',
              value: preset.charQuoteColor,
              palette: _presetColors,
              allowNull: true,
              nullLabel: 'Auto',
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(charQuoteColor: v)),
            ),
          ],
        ),
        MenuGroup(
          header: 'Text Colors',
          items: [
            _ColorRow(
              label: 'User Text',
              value: preset.userTextColor,
              palette: _presetColors,
              allowNull: true,
              nullLabel: 'Auto',
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(userTextColor: v)),
            ),
            _ColorRow(
              label: 'Char Text',
              value: preset.charTextColor,
              palette: _presetColors,
              allowNull: true,
              nullLabel: 'Auto',
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(charTextColor: v)),
            ),
          ],
        ),
        MenuGroup(
          header: 'Italic (Action) Colors',
          items: [
            _ColorRow(
              label: 'User Italic',
              value: preset.userItalicColor,
              palette: _presetColors,
              allowNull: true,
              nullLabel: 'Auto',
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(userItalicColor: v)),
            ),
            _ColorRow(
              label: 'Char Italic',
              value: preset.charItalicColor,
              palette: _presetColors,
              allowNull: true,
              nullLabel: 'Auto',
              onChanged: (v) =>
                  onUpdate((p) => p.copyWith(charItalicColor: v)),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Shared row widgets ───────────────────────────────────────────────────────

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
            child: Text(label, style: TextStyle(fontSize: 15, color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w400)),
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

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: context.cs.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _LayoutPickerRow extends StatelessWidget {
  final String value;
  final VoidCallback onTap;

  const _LayoutPickerRow({
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isBubble = value == 'bubble';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                isBubble ? Icons.chat_bubble_outline : Icons.view_stream_outlined,
                size: 18,
                color: context.cs.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat Layout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isBubble ? 'Bubble' : 'Default',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.cs.onSurfaceVariant),
            ],
          ),
        ),
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
                child: Text(label, style: TextStyle(fontSize: 15, color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w400)),
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

int _weightFromSlider(double value) {
  return (((value / 100).round()) * 100).clamp(100, 900);
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
            child: Text(label, style: TextStyle(fontSize: 15, color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w400)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              GlazeBottomSheet.show<void>(
                context,
                title: label,
                items: List.generate(
                  modes.length,
                  (i) => BottomSheetItem(
                    label: modeLabels[i],
                    icon: modes[i] == mode ? Icons.check : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (modes[i] != mode) onChanged(modes[i]);
                    },
                  ),
                ),
              );
            },
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
    final textOnCurrent = current != null
        ? (current.computeLuminance() > 0.5 ? Colors.black : Colors.white)
        : context.cs.onSurfaceVariant;
    return InkWell(
      onTap: () => _openPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: context.cs.onSurfaceVariant,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 48),
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: current ?? Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.cs.outlineVariant
                      .withValues(alpha: current == null ? 0.6 : 0.3),
                  width: 1,
                ),
              ),
              child: current == null
                  ? Text(
                      nullLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: textOnCurrent,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => _ColorPickerSheet(
        current: value,
        palette: palette,
        allowNull: allowNull,
        nullLabel: nullLabel,
        onChanged: onChanged,
      ),
    );
  }
}

// ─── Background image row ─────────────────────────────────────────────────────

class _BgImageRow extends StatelessWidget {
  final ThemePreset preset;
  final void Function(ThemePreset Function(ThemePreset)) onUpdate;

  const _BgImageRow({required this.preset, required this.onUpdate});

  Future<void> _pick(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
      dialogTitle: 'Select Background Image',
      withData: true,
    );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      final lower = path.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
              ? 'image/webp'
              : lower.endsWith('.gif')
                  ? 'image/gif'
                  : 'image/jpeg';
      final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
      onUpdate((p) => p.copyWith(bgImage: dataUri));
    } catch (e) {
      if (context.mounted) {
        GlazeToast.error(context, 'Failed to load image: ', e);
      }
    }
  }

  void _reset() => onUpdate((p) => p.copyWith(bgImage: null));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _pick(context),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.image_outlined,
                    size: 22, color: const Color(0xFF99A2AD)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    preset.hasBgImage
                        ? 'Replace Background Image'
                        : 'Select Background Image',
                    style: TextStyle(
                      color: context.cs.onSurfaceVariant,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (preset.hasBgImage)
          InkWell(
            onTap: _reset,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.delete_outline,
                      size: 22, color: Color(0xFFFF4444)),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Reset Background',
                      style: TextStyle(
                        color: Color(0xFFFF4444),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Color picker bottom sheet ────────────────────────────────────────────────

class _ColorPickerSheet extends StatefulWidget {
  final String? current;
  final List<String> palette;
  final bool allowNull;
  final String nullLabel;
  final ValueChanged<String?> onChanged;

  const _ColorPickerSheet({
    required this.current,
    required this.palette,
    required this.allowNull,
    required this.nullLabel,
    required this.onChanged,
  });

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late TextEditingController _hexCtrl;
  String? _error;
  bool _isHslMode = true;
  late double _h, _s, _l;
  late int _r, _g, _b;
  bool _suppressSliderSync = false;

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(text: widget.current ?? '');
    final currentColor = widget.current != null ? _hex(widget.current!) : const Color(0xFF7996CE);
    final hsl = HSLColor.fromColor(currentColor);
    _h = hsl.hue;
    _s = hsl.saturation;
    _l = hsl.lightness;
    _r = (currentColor.r * 255).round();
    _g = (currentColor.g * 255).round();
    _b = (currentColor.b * 255).round();
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _applyColor(Color color) {
    final hex = _toHex(color);
    _suppressSliderSync = true;
    final hsl = HSLColor.fromColor(color);
    _h = hsl.hue;
    _s = hsl.saturation;
    _l = hsl.lightness;
    _r = (color.r * 255).round();
    _g = (color.g * 255).round();
    _b = (color.b * 255).round();
    _hexCtrl.text = hex;
    setState(() => _error = null);
    widget.onChanged(hex);
    _suppressSliderSync = false;
  }

  void _onHexChanged(String hex) {
    final clean = hex.trim();
    if (clean.isEmpty) {
      setState(() => _error = null);
      if (widget.allowNull) widget.onChanged(null);
      return;
    }
    final h = clean.startsWith('#') ? clean : '#$clean';
    final parsed = _parseHexSafe(h);
    if (parsed == null) {
      setState(() => _error = clean.length >= 6 ? 'Invalid hex color' : null);
      return;
    }
    setState(() => _error = null);
    _applyColor(parsed);
  }

  void _onHslChanged() {
    if (_suppressSliderSync) return;
    final color = HSLColor.fromAHSL(1.0, _h, _s.clamp(0.0, 1.0), _l.clamp(0.0, 1.0)).toColor();
    _applyColor(color);
  }

  void _onRgbChanged() {
    if (_suppressSliderSync) return;
    final color = Color.fromARGB(255, _r.clamp(0, 255), _g.clamp(0, 255), _b.clamp(0, 255));
    _applyColor(color);
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
    final currentColor = _parseHexSafe(_hexCtrl.text) ?? const Color(0xFF7996CE);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: cs.surface.withValues(alpha: 0.85),
          child: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      // Preview swatch
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: currentColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outlineVariant, width: 1.5),
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (widget.allowNull)
                            GestureDetector(
                              onTap: () {
                                widget.onChanged(null);
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: cs.outlineVariant, width: 1.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.auto_awesome,
                                    size: 18, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ...widget.palette.map((hex) {
                            final color = _hex(hex);
                            final isSelected = widget.current?.toUpperCase() ==
                                hex.toUpperCase();
                            return GestureDetector(
                              onTap: () {
                                _applyColor(color);
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? cs.primary
                                        : cs.outlineVariant,
                                    width: isSelected ? 3 : 1,
                                  ),
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check,
                                        size: 20,
                                        color: color.computeLuminance() > 0.4
                                            ? Colors.black
                                            : Colors.white,
                                      )
                                    : null,
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Mode toggle
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isHslMode = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _isHslMode ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                  border: Border.all(color: cs.outlineVariant),
                                ),
                                child: Text(
                                  'HSL',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _isHslMode ? cs.primary : cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isHslMode = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !_isHslMode ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                  border: Border(
                                    top: BorderSide(color: cs.outlineVariant),
                                    right: BorderSide(color: cs.outlineVariant),
                                    bottom: BorderSide(color: cs.outlineVariant),
                                  ),
                                ),
                                child: Text(
                                  'RGB',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: !_isHslMode ? cs.primary : cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_isHslMode) ...[
                        _PickerSlider(
                          label: 'Hue',
                          value: _h,
                          min: 0,
                          max: 360,
                          divisions: 360,
                          display: '${_h.round()}\u00B0',
                          onChanged: (v) { _h = v; _onHslChanged(); setState(() {}); },
                        ),
                        _PickerSlider(
                          label: 'Saturation',
                          value: _s * 100,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          display: '${(_s * 100).round()}%',
                          onChanged: (v) { _s = v / 100; _onHslChanged(); setState(() {}); },
                        ),
                        _PickerSlider(
                          label: 'Lightness',
                          value: _l * 100,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          display: '${(_l * 100).round()}%',
                          onChanged: (v) { _l = v / 100; _onHslChanged(); setState(() {}); },
                        ),
                      ] else ...[
                        _PickerSlider(
                          label: 'Red',
                          value: _r.toDouble(),
                          min: 0,
                          max: 255,
                          divisions: 255,
                          display: '$_r',
                          activeColor: const Color(0xFFFF4444),
                          onChanged: (v) { _r = v.round(); _onRgbChanged(); setState(() {}); },
                        ),
                        _PickerSlider(
                          label: 'Green',
                          value: _g.toDouble(),
                          min: 0,
                          max: 255,
                          divisions: 255,
                          display: '$_g',
                          activeColor: const Color(0xFF44BB44),
                          onChanged: (v) { _g = v.round(); _onRgbChanged(); setState(() {}); },
                        ),
                        _PickerSlider(
                          label: 'Blue',
                          value: _b.toDouble(),
                          min: 0,
                          max: 255,
                          divisions: 255,
                          display: '$_b',
                          activeColor: const Color(0xFF4488FF),
                          onChanged: (v) { _b = v.round(); _onRgbChanged(); setState(() {}); },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _hexCtrl,
                        decoration: InputDecoration(
                          hintText: '#7996CE',
                          labelText: 'Hex Color',
                          errorText: _error,
                          prefixText:
                              _hexCtrl.text.startsWith('#') ? null : '#',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: _onHexChanged,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final Color? activeColor;
  final ValueChanged<double> onChanged;

  const _PickerSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: activeColor ?? cs.primary,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(display, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

// ─── Google Fonts ─────────────────────────────────────────────────────────────

const _kPopularGoogleFonts = [
  'Roboto', 'Open Sans', 'Lato', 'Montserrat', 'Oswald',
  'Raleway', 'Poppins', 'Nunito', 'Ubuntu', 'Playfair Display',
  'Merriweather', 'PT Sans', 'Source Sans 3', 'Rubik', 'Work Sans',
  'Fira Sans', 'Quicksand', 'Barlow', 'Mulish', 'Karla',
  'Inconsolata', 'Bitter', 'Cabin', 'Lora', 'Josefin Sans',
  'Arimo', 'Dosis', 'Libre Baskerville', 'Oxygen', 'Crimson Text',
  'Exo 2', 'Abel', 'Comfortaa', 'Varela Round', 'Pacifico',
  'Lobster', 'Dancing Script', 'Satisfy', 'Caveat', 'Shadows Into Light',
  'Courier Prime', 'Space Mono', 'IBM Plex Mono', 'JetBrains Mono',
  'Anonymous Pro', 'Roboto Mono', 'Source Code Pro', 'Fira Code',
];

Future<void> _pickGoogleFont(
  BuildContext context,
  void Function(ThemePreset Function(ThemePreset)) onUpdate, {
  required bool isUi,
  required ThemePreset preset,
}) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GoogleFontPickerSheet(),
  );
  if (selected != null && selected.isNotEmpty) {
    if (isUi) {
      onUpdate((p) => p.copyWith(uiFontMode: 'google', googleFontName: selected));
    } else {
      onUpdate((p) => p.copyWith(chatFontMode: 'google', chatGoogleFontName: selected));
    }
  }
}

class _GoogleFontPickerSheet extends StatefulWidget {
  @override
  State<_GoogleFontPickerSheet> createState() => _GoogleFontPickerSheetState();
}

class _GoogleFontPickerSheetState extends State<_GoogleFontPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _kPopularGoogleFonts
        .where((f) => f.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        color: cs.surface.withValues(alpha: 0.95),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Google Fonts',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Search fonts...',
                      prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final font = filtered[i];
                      return ListTile(
                        title: Text(font, style: TextStyle(color: cs.onSurface)),
                        onTap: () => Navigator.pop(context, font),
                      );
                    },
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

class _GoogleFontDisplayRow extends StatelessWidget {
  final String fontName;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _GoogleFontDisplayRow({
    required this.fontName,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 130),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(
                fontName,
                style: TextStyle(color: context.cs.primary, fontSize: 14),
              ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close, size: 18, color: context.cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
