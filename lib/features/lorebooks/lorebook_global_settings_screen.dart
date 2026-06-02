import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/lorebook.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import '../../../shared/widgets/help_tip.dart';

class LorebookGlobalSettingsScreen extends ConsumerStatefulWidget {
  const LorebookGlobalSettingsScreen({super.key});

  @override
  ConsumerState<LorebookGlobalSettingsScreen> createState() => _LorebookGlobalSettingsScreenState();
}

class _LorebookGlobalSettingsScreenState extends ConsumerState<LorebookGlobalSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(lorebookSettingsProvider);

    return Scaffold(
      backgroundColor: context.cs.surface,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlazeAppBar(
                title: 'Lorebook Settings',
                leading: BackButton(onPressed: () => Navigator.pop(context)),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader('Search', helpTerm: 'lorebook-keys'),
                _DropdownField<String>(
                  label: 'Key Search Mode',
                  value: settings.keySearchMode,
                  items: const [
                    DropdownMenuItem(value: 'tavern', child: Text('Tavern (substring)')),
                    DropdownMenuItem(value: 'glaze', child: Text('Glaze (word boundary)')),
                  ],
                  onChanged: (v) => _update(settings.copyWith(keySearchMode: v)),
                ),
                const SizedBox(height: 12),
                _DropdownField<String>(
                  label: 'Search Type',
                  value: settings.searchType,
                  items: const [
                    DropdownMenuItem(value: 'keyword', child: Text('Keyword')),
                    DropdownMenuItem(value: 'vector', child: Text('Vector')),
                    DropdownMenuItem(value: 'both', child: Text('Both (Hybrid)')),
                  ],
                  onChanged: (v) => _update(settings.copyWith(searchType: v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: settings.searchType == 'vector' ? 'Vector Scan Depth' : 'Keyword Scan Depth',
                  value: settings.scanDepth,
                  min: 1,
                  max: 100,
                  onChanged: (v) => _update(settings.copyWith(scanDepth: v)),
                ),
                const SizedBox(height: 24),

                _SectionHeader('Injection'),
                _NumberField(
                  label: 'Max Injected Entries',
                  value: settings.maxInjectedEntries,
                  min: 1,
                  max: 100,
                  onChanged: (v) => _update(settings.copyWith(maxInjectedEntries: v)),
                ),
                const SizedBox(height: 12),
                _DropdownField<String>(
                  label: 'Injection Position',
                  value: settings.injectionPosition,
                  items: const [
                    DropdownMenuItem(value: 'worldInfoBefore', child: Text('Before Chat History')),
                    DropdownMenuItem(value: 'worldInfoAfter', child: Text('After Chat History')),
                    DropdownMenuItem(value: 'lorebooksMacro', child: Text('At {{lorebooks}} Macro')),
                  ],
                  onChanged: (v) => _update(settings.copyWith(injectionPosition: v)),
                ),
                const SizedBox(height: 24),

                _SectionHeader('Token Budget', helpTerm: 'lorebook-budget'),
                _DropdownField<String>(
                  label: 'Reserve Mode',
                  value: settings.reserveMode,
                  items: const [
                    DropdownMenuItem(value: 'percent', child: Text('Percentage')),
                    DropdownMenuItem(value: 'tokens', child: Text('Absolute Tokens')),
                  ],
                  onChanged: (v) => _update(settings.copyWith(reserveMode: v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: settings.reserveMode == 'percent' ? 'Reserve %' : 'Reserve Tokens',
                  value: settings.reserveValue,
                  min: 0,
                  max: settings.reserveMode == 'percent' ? 100 : 2147483647,
                  onChanged: (v) => _update(settings.copyWith(reserveValue: v)),
                ),
                const SizedBox(height: 24),

                if (settings.searchType != 'keyword') ...[
                  _SectionHeader('Vector Search'),
                  _SliderField(
                    label: 'Similarity Threshold',
                    value: settings.vectorThreshold,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    displayText: settings.vectorThreshold.toStringAsFixed(2),
                    onChanged: (v) => _update(settings.copyWith(vectorThreshold: v)),
                  ),
                  const SizedBox(height: 12),
                  _NumberField(
                    label: 'Vector Top K',
                    value: settings.vectorTopK,
                    min: 1,
                    max: 50,
                    onChanged: (v) => _update(settings.copyWith(vectorTopK: v)),
                  ),
                  if (settings.searchType == 'both') ...[
                    const SizedBox(height: 12),
                    _SliderField(
                      label: 'Keyword / Vector Split',
                      value: settings.keywordVectorSplit.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      displayText: '${settings.keywordVectorSplit}% key / ${100 - settings.keywordVectorSplit}% vec',
                      onChanged: (v) => _update(settings.copyWith(keywordVectorSplit: v.round())),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],

                _SectionHeader('Matching'),
                _SwitchField(
                  label: 'Case Sensitive',
                  value: settings.caseSensitive,
                  onChanged: (v) => _update(settings.copyWith(caseSensitive: v)),
                ),
                _SwitchField(
                  label: 'Recursive Scan',
                  value: settings.recursiveScan,
                  onChanged: (v) => _update(settings.copyWith(recursiveScan: v)),
                ),
                _SwitchField(
                  label: 'Match Whole Words',
                  value: settings.matchWholeWords,
                  onChanged: (v) => _update(settings.copyWith(matchWholeWords: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _update(LorebookGlobalSettings s) {
    ref.read(lorebookSettingsProvider.notifier).state = s;
    saveLorebookSettings(s);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? helpTerm;
  const _SectionHeader(this.title, {this.helpTerm});

  @override
  Widget build(BuildContext context) {
    final label = Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.cs.primary, letterSpacing: 0.5));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: helpTerm == null
          ? label
          : Row(mainAxisSize: MainAxisSize.min, children: [label, HelpTip(term: helpTerm!)]),
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _NumberField({required this.label, required this.value, this.min = 0, this.max = 2147483647, required this.onChanged});

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    // Sync controller when the external value changes (e.g. reserveMode switch resets value)
    if (old.value != widget.value) {
      final cursor = _ctrl.selection;
      _ctrl.text = widget.value.toString();
      // Restore cursor if still valid
      if (cursor.start <= _ctrl.text.length) {
        _ctrl.selection = cursor;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final n = int.tryParse(_ctrl.text);
    if (n != null && n >= widget.min && n <= widget.max) {
      widget.onChanged(n);
    } else {
      // Reset to last valid value
      _ctrl.text = widget.value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(widget.label, style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14))),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, maxWidth: 100),
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: context.cs.onSurface, fontSize: 14),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) => _commit(),
            onEditingComplete: _commit,
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
              _commit();
            },
          ),
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  const _DropdownField({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14))),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: DropdownButtonFormField<T>(
            initialValue: value,
            items: items,
            isExpanded: true,
            onChanged: (v) { if (v != null) onChanged(v); },
            style: TextStyle(color: context.cs.onSurface, fontSize: 13),
            dropdownColor: context.cs.surface,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayText;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.label,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions = 10,
    required this.displayText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14)),
            Text(displayText, style: TextStyle(color: context.cs.onSurface, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: context.cs.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SwitchField extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
