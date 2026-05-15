import 'package:flutter/material.dart';
import '../../../core/models/lorebook.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_scaffold.dart';

class LorebookPerBookSettingsScreen extends StatefulWidget {
  final LorebookSettings? settings;
  final LorebookGlobalSettings? globalSettings;

  const LorebookPerBookSettingsScreen({super.key, this.settings, this.globalSettings});

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
                leading: BackButton(onPressed: () => _pop(context)),
                actions: [
                  TextButton(
                    onPressed: _hasCustom ? _resetToGlobal : null,
                    child: Text(
                      'Reset to Global',
                      style: TextStyle(
                        fontSize: 12,
                        color: _hasCustom
                            ? context.cs.primary
                            : context.cs.onSurfaceVariant,
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
                  border:
                      Border.all(color: context.cs.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: context.cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Using global defaults. Change any setting to create per-book overrides.',
                        style: TextStyle(
                            fontSize: 12, color: context.cs.onSurfaceVariant),
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
                // ── Scanning ──────────────────────────────────────────────
                _SectionHeader('Scanning'),
                _NumberField(
                  label: 'Scan Depth',
                  value: _settings.scanDepth ?? 0,
                  min: 0,
                  max: 100,
                  hint: '0 = global default',
                  onChanged: (v) =>
                      _update(_settings.copyWith(scanDepth: v == 0 ? null : v)),
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Max Injected Entries',
                  value: _settings.maxInjectedEntries ?? 0,
                  min: 0,
                  max: 100,
                  hint: '0 = global default',
                  onChanged: (v) => _update(
                      _settings.copyWith(maxInjectedEntries: v == 0 ? null : v)),
                ),
                const SizedBox(height: 24),

                // ── Matching ──────────────────────────────────────────────
                _SectionHeader('Matching'),
                _SwitchField(
                  label: 'Recursive Scan',
                  value: _settings.recursiveScan,
                  onChanged: (v) => _update(_settings.copyWith(recursiveScan: v)),
                ),
                const SizedBox(height: 4),
                _SwitchField(
                  label: 'Case Sensitive',
                  value: _settings.caseSensitive,
                  onChanged: (v) => _update(_settings.copyWith(caseSensitive: v)),
                ),
                const SizedBox(height: 8),
                _DropdownField<String>(
                  label: 'Match Whole Words',
                  value: _settings.matchWholeWords ?? '',
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Global default')),
                    DropdownMenuItem(value: 'false', child: Text('No')),
                    DropdownMenuItem(value: 'true', child: Text('Yes')),
                    DropdownMenuItem(
                        value: 'glaze', child: Text('Glaze boundary')),
                  ],
                  onChanged: (v) => _update(
                      _settings.copyWith(matchWholeWords: v.isEmpty ? null : v)),
                ),
                const SizedBox(height: 24),

                // ── Vector Search ─────────────────────────────────────────
                _SectionHeader('Vector Search'),
                _SwitchField(
                  label: 'Vector Search Enabled',
                  value: _settings.vectorSearchEnabled,
                  onChanged: (v) =>
                      _update(_settings.copyWith(vectorSearchEnabled: v)),
                ),
                if (_settings.vectorSearchEnabled) ...[
                  const SizedBox(height: 8),
                  _DropdownField<String>(
                    label: 'Embedding Target',
                    value: _settings.embeddingTarget,
                    items: const [
                      DropdownMenuItem(value: 'content', child: Text('Content')),
                      DropdownMenuItem(value: 'comment', child: Text('Comment')),
                      DropdownMenuItem(value: 'both', child: Text('Both')),
                    ],
                    onChanged: (v) =>
                        _update(_settings.copyWith(embeddingTarget: v)),
                  ),
                  const SizedBox(height: 12),
                  _SliderField(
                    label: 'Similarity Threshold',
                    value: _settings.vectorThreshold,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    displayText: _settings.vectorThreshold.toStringAsFixed(2),
                    onChanged: (v) =>
                        _update(_settings.copyWith(vectorThreshold: v)),
                  ),
                  const SizedBox(height: 12),
                  _NumberField(
                    label: 'Vector Top K',
                    value: _settings.vectorTopK,
                    min: 1,
                    max: 50,
                    onChanged: (v) => _update(_settings.copyWith(vectorTopK: v)),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pop(BuildContext context) {
    if (_hasCustom) {
      Navigator.pop(context, {'settings': _settings.toJson()});
    } else {
      Navigator.pop(context, {'reset': true});
    }
  }

  void _update(LorebookSettings s) {
    setState(() {
      _settings = s;
      _hasCustom = true;
    });
  }

  void _resetToGlobal() {
    final g = widget.globalSettings;
    setState(() {
      _settings = g == null
          ? const LorebookSettings()
          : LorebookSettings(
              scanDepth: null,
              maxInjectedEntries: null,
              recursiveScan: g.recursiveScan,
              caseSensitive: g.caseSensitive,
              matchWholeWords: g.matchWholeWords ? 'true' : 'false',
              vectorSearchEnabled: true,
              embeddingTarget: 'content',
              vectorThreshold: g.vectorThreshold,
              vectorTopK: g.vectorTopK,
            );
      _hasCustom = false;
    });
  }
}

// ── Reusable widgets (same style as global settings screen) ────────────────

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

class _NumberField extends StatefulWidget {
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
    this.max = 2147483647,
    this.hint,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.value == 0 && widget.hint != null ? '' : widget.value.toString(),
    );
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      final newText =
          widget.value == 0 && widget.hint != null ? '' : widget.value.toString();
      if (_ctrl.text != newText) _ctrl.text = newText;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _ctrl.text;
    if (text.isEmpty) {
      widget.onChanged(0);
      return;
    }
    final n = int.tryParse(text);
    if (n != null && n >= widget.min && n <= widget.max) {
      widget.onChanged(n);
    } else {
      _ctrl.text =
          widget.value == 0 && widget.hint != null ? '' : widget.value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(widget.label,
              style:
                  TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14)),
        ),
        SizedBox(
          width: 80,
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
              hintText: widget.hint,
              hintStyle: TextStyle(
                  fontSize: 10,
                  color: context.cs.onSurfaceVariant.withValues(alpha: 0.4)),
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
          child: Text(label,
              style:
                  TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14)),
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            Text(label,
                style:
                    TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14)),
            Text(displayText,
                style: TextStyle(
                    color: context.cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
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

  const _SwitchField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14)),
        Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.cs.primary),
      ],
    );
  }
}
