import 'package:flutter/material.dart';
import '../../../core/models/lorebook.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_scaffold.dart';

class LorebookPerBookSettingsScreen extends StatefulWidget {
  final LorebookSettings? settings;

  const LorebookPerBookSettingsScreen({super.key, this.settings});

  @override
  State<LorebookPerBookSettingsScreen> createState() =>
      _LorebookPerBookSettingsScreenState();
}

class _LorebookPerBookSettingsScreenState
    extends State<LorebookPerBookSettingsScreen> {
  late LorebookSettings _settings;
  bool _hasCustom = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings ?? const LorebookSettings();
    _hasCustom = widget.settings != null;
  }

  @override
  Widget build(BuildContext context) {
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
                leading: BackButton(
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  TextButton(
                    onPressed: _hasCustom ? _resetToGlobal : null,
                    child: Text(
                      'Reset to Global',
                      style: TextStyle(
                        fontSize: 12,
                        color: _hasCustom ? context.cs.primary : context.cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_hasCustom)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.cs.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: context.cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Using global defaults. Change any setting to create per-book overrides.',
                        style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader('Scanning'),
                _NumberField(
                  label: 'Scan Depth',
                  value: _settings.scanDepth ?? 0,
                  min: 0,
                  max: 100,
                  hint: 'Global default',
                  onChanged: (v) => _update(_settings.copyWith(scanDepth: v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Max Injected Entries',
                  value: _settings.maxInjectedEntries ?? 0,
                  min: 0,
                  max: 100,
                  hint: 'Global default',
                  onChanged: (v) => _update(_settings.copyWith(maxInjectedEntries: v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Max Recursion Steps',
                  value: _settings.maxRecursionSteps,
                  min: 0,
                  max: 100,
                  onChanged: (v) => _update(_settings.copyWith(maxRecursionSteps: v)),
                ),
                const SizedBox(height: 24),

                _SectionHeader('Matching'),
                _SwitchField(
                  label: 'Recursive Scan',
                  value: _settings.recursiveScan,
                  onChanged: (v) => _update(_settings.copyWith(recursiveScan: v)),
                ),
                _SwitchField(
                  label: 'Case Sensitive',
                  value: _settings.caseSensitive,
                  onChanged: (v) => _update(_settings.copyWith(caseSensitive: v)),
                ),
                _DropdownField<String>(
                  label: 'Match Whole Words',
                  value: _settings.matchWholeWords ?? '',
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Global default')),
                    DropdownMenuItem(value: 'false', child: Text('No')),
                    DropdownMenuItem(value: 'true', child: Text('Yes')),
                    DropdownMenuItem(value: 'glaze', child: Text('Glaze boundary')),
                  ],
                  onChanged: (v) => _update(_settings.copyWith(matchWholeWords: v.isEmpty ? null : v)),
                ),
                _SwitchField(
                  label: 'Include Names',
                  value: _settings.includeNames,
                  onChanged: (v) => _update(_settings.copyWith(includeNames: v)),
                ),
                _SwitchField(
                  label: 'Use Group Scoring',
                  value: _settings.useGroupScoring,
                  onChanged: (v) => _update(_settings.copyWith(useGroupScoring: v)),
                ),
                _SwitchField(
                  label: 'Alert on Overflow',
                  value: _settings.alertOnOverflow,
                  onChanged: (v) => _update(_settings.copyWith(alertOnOverflow: v)),
                ),
                const SizedBox(height: 24),

                _SectionHeader('Injection'),
                _DropdownField<String>(
                  label: 'Injection Position',
                  value: _settings.injectionPosition,
                  items: const [
                    DropdownMenuItem(value: 'lorebooksMacro', child: Text('{{lorebooks}} Macro')),
                    DropdownMenuItem(value: 'worldInfoBefore', child: Text('Before Chat History')),
                    DropdownMenuItem(value: 'worldInfoAfter', child: Text('After Chat History')),
                  ],
                  onChanged: (v) => _update(_settings.copyWith(injectionPosition: v)),
                ),
                _DropdownField<String>(
                  label: 'Insertion Strategy',
                  value: _settings.insertionStrategy,
                  items: const [
                    DropdownMenuItem(value: 'character_first', child: Text('Character First')),
                    DropdownMenuItem(value: 'evenly_distributed', child: Text('Evenly Distributed')),
                  ],
                  onChanged: (v) => _update(_settings.copyWith(insertionStrategy: v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Context %',
                  value: _settings.contextPercent,
                  min: 0,
                  max: 100,
                  onChanged: (v) => _update(_settings.copyWith(contextPercent: v)),
                ),
                const SizedBox(height: 24),

                _SectionHeader('Token Budget'),
                _DropdownField<String>(
                  label: 'Reserve Mode',
                  value: _settings.reserveMode,
                  items: const [
                    DropdownMenuItem(value: 'tokens', child: Text('Absolute Tokens')),
                    DropdownMenuItem(value: 'percent', child: Text('Percentage')),
                  ],
                  onChanged: (v) => _update(_settings.copyWith(reserveMode: v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: _settings.reserveMode == 'percent' ? 'Reserve %' : 'Reserve Tokens',
                  value: _settings.reserveValue,
                  min: 0,
                  max: _settings.reserveMode == 'percent' ? 100 : 100000,
                  onChanged: (v) => _update(_settings.copyWith(reserveValue: v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Budget Cap',
                  value: _settings.budgetCap,
                  min: 0,
                  max: 100000,
                  hint: '0 = unlimited',
                  onChanged: (v) => _update(_settings.copyWith(budgetCap: v)),
                ),
                const SizedBox(height: 24),

                _SectionHeader('Search Type'),
                _DropdownField<String>(
                  label: 'Search Type',
                  value: _settings.searchType,
                  items: const [
                    DropdownMenuItem(value: 'keyword', child: Text('Keyword')),
                    DropdownMenuItem(value: 'vector', child: Text('Vector')),
                    DropdownMenuItem(value: 'both', child: Text('Both (Hybrid)')),
                  ],
                  onChanged: (v) => _update(_settings.copyWith(searchType: v)),
                ),
                _SwitchField(
                  label: 'Key Search Enabled',
                  value: _settings.keySearchEnabled,
                  onChanged: (v) => _update(_settings.copyWith(keySearchEnabled: v)),
                ),
                _SwitchField(
                  label: 'Vector Search Enabled',
                  value: _settings.vectorSearchEnabled,
                  onChanged: (v) => _update(_settings.copyWith(vectorSearchEnabled: v)),
                ),
                if (_settings.searchType != 'keyword') ...[
                  const SizedBox(height: 12),
                  _DropdownField<String>(
                    label: 'Embedding Target',
                    value: _settings.embeddingTarget,
                    items: const [
                      DropdownMenuItem(value: 'content', child: Text('Content')),
                      DropdownMenuItem(value: 'comment', child: Text('Comment')),
                      DropdownMenuItem(value: 'both', child: Text('Both')),
                    ],
                    onChanged: (v) => _update(_settings.copyWith(embeddingTarget: v)),
                  ),
                  const SizedBox(height: 12),
                  _SliderField(
                    label: 'Similarity Threshold',
                    value: _settings.vectorThreshold,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    displayText: _settings.vectorThreshold.toStringAsFixed(2),
                    onChanged: (v) => _update(_settings.copyWith(vectorThreshold: v)),
                  ),
                  const SizedBox(height: 12),
                  _NumberField(
                    label: 'Vector Top K',
                    value: _settings.vectorTopK,
                    min: 1,
                    max: 50,
                    onChanged: (v) => _update(_settings.copyWith(vectorTopK: v)),
                  ),
                  const SizedBox(height: 12),
                  _NumberField(
                    label: 'Vector Scan Depth',
                    value: _settings.vectorScanDepth,
                    min: 1,
                    max: 100,
                    onChanged: (v) => _update(_settings.copyWith(vectorScanDepth: v)),
                  ),
                  if (_settings.searchType == 'both') ...[
                    const SizedBox(height: 12),
                    _SliderField(
                      label: 'Keyword / Vector Split',
                      value: _settings.keywordVectorSplit.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      displayText: '${_settings.keywordVectorSplit}% key / ${100 - _settings.keywordVectorSplit}% vec',
                      onChanged: (v) => _update(_settings.copyWith(keywordVectorSplit: v.round())),
                    ),
                  ],
                ],
                const SizedBox(height: 24),

                _SectionHeader('Activation Limits'),
                _NumberField(
                  label: 'Min Activations',
                  value: _settings.minActivations,
                  min: 0,
                  max: 100,
                  hint: '0 = disabled',
                  onChanged: (v) => _update(_settings.copyWith(minActivations: v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Max Depth',
                  value: _settings.maxDepth,
                  min: 0,
                  max: 100,
                  hint: '0 = unlimited',
                  onChanged: (v) => _update(_settings.copyWith(maxDepth: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _update(LorebookSettings s) {
    setState(() {
      _settings = s;
      _hasCustom = true;
    });
  }

  void _resetToGlobal() {
    setState(() {
      _settings = const LorebookSettings();
      _hasCustom = false;
    });
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: context.cs.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String? hint;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 99999,
    this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14),
          ),
        ),
        SizedBox(
          width: 80,
          child: TextFormField(
            initialValue: value == 0 && hint != null ? '' : value.toString(),
            keyboardType: TextInputType.number,
            style: TextStyle(color: context.cs.onSurface, fontSize: 14),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              hintText: hint,
              hintStyle: TextStyle(fontSize: 10, color: context.cs.onSurfaceVariant.withValues(alpha: 0.4)),
            ),
            onFieldSubmitted: (v) {
              if (v.isEmpty) {
                onChanged(0);
                return;
              }
              final n = int.tryParse(v);
              if (n != null && n >= min && n <= max) onChanged(n);
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

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<T>(
            value: value,
            items: items,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
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
        Switch(value: value, onChanged: onChanged, activeColor: context.cs.primary),
      ],
    );
  }
}
