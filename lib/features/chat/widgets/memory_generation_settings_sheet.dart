import 'package:flutter/material.dart';

import '../../../core/models/memory_book.dart';
import '../../../core/services/memory_prompt_presets.dart';
import '../../../shared/theme/app_colors.dart';

class MemoryGenerationSettingsSheet extends StatefulWidget {
  final MemoryBookSettings settings;

  const MemoryGenerationSettingsSheet({super.key, required this.settings});

  @override
  State<MemoryGenerationSettingsSheet> createState() => _MemoryGenerationSettingsSheetState();
}

class _MemoryGenerationSettingsSheetState extends State<MemoryGenerationSettingsSheet> {
  late bool _enabled;
  late bool _autoCreate;
  late bool _autoGenerate;
  late int _maxInjected;
  late int _autoCreateInterval;
  late int _batchSize;
  late bool _useDelayedAutomation;
  late String _injectionTarget;
  late String _generationSource;
  late String _generationModel;
  late String _generationEndpoint;
  late String _generationApiKey;
  late double _generationTemperature;
  late int _generationMaxTokens;
  late String _promptPreset;
  late String _keyMatchMode;
  late bool _vectorSearchEnabled;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _enabled = s.enabled;
    _autoCreate = s.autoCreateEnabled;
    _autoGenerate = s.autoGenerateEnabled;
    _maxInjected = s.maxInjectedEntries;
    _autoCreateInterval = s.autoCreateInterval;
    _batchSize = s.batchSize;
    _useDelayedAutomation = s.useDelayedAutomation;
    _injectionTarget = s.injectionTarget;
    _generationSource = s.generationSource;
    _generationModel = s.generationModel;
    _generationEndpoint = s.generationEndpoint;
    _generationApiKey = s.generationApiKey;
    _generationTemperature = s.generationTemperature ?? 0.0;
    _generationMaxTokens = s.generationMaxTokens ?? 0;
    _promptPreset = s.promptPreset;
    _keyMatchMode = s.keyMatchMode;
    _vectorSearchEnabled = s.vectorSearchEnabled;
  }

  void _save() {
    final settings = widget.settings.copyWith(
      enabled: _enabled,
      autoCreateEnabled: _autoCreate,
      autoGenerateEnabled: _autoGenerate,
      maxInjectedEntries: _maxInjected,
      autoCreateInterval: _autoCreateInterval,
      batchSize: _batchSize,
      useDelayedAutomation: _useDelayedAutomation,
      injectionTarget: _injectionTarget,
      generationSource: _generationSource,
      generationModel: _generationModel,
      generationEndpoint: _generationEndpoint,
      generationApiKey: _generationApiKey,
      generationTemperature: _generationTemperature > 0 ? _generationTemperature : null,
      generationMaxTokens: _generationMaxTokens > 0 ? _generationMaxTokens : null,
      promptPreset: _promptPreset,
      keyMatchMode: _keyMatchMode,
      vectorSearchEnabled: _vectorSearchEnabled,
    );
    Navigator.pop(context, settings);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _switchTile('Enabled', _enabled, (v) => setState(() => _enabled = v)),
          _switchTile('Auto-Create Drafts', _autoCreate, (v) => setState(() => _autoCreate = v),
              subtitle: 'Automatically create draft placeholders after enough messages'),
          _switchTile('Auto-Generate Text', _autoGenerate, (v) => setState(() => _autoGenerate = v),
              subtitle: 'Immediately generate text for auto-created drafts'),
          if (_autoCreate) ...[
            _switchTile('Delayed Automation', _useDelayedAutomation, (v) => setState(() => _useDelayedAutomation = v),
                subtitle: 'Wait for extra turns before creating drafts'),
            _numberField('Create Memory Every N Messages', _autoCreateInterval, (v) => setState(() => _autoCreateInterval = v), min: 1, max: 200),
          ],
          _numberField('Max Generate Batch', _batchSize, (v) => setState(() => _batchSize = v), min: 1, max: 50),
          _numberField('Memory Entries In Prompt', _maxInjected, (v) => setState(() => _maxInjected = v), min: 1, max: 20),
          const SizedBox(height: 12),
          _sectionLabel('Injection Target'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'summary_block', label: Text('worldinfo')),
              ButtonSegment(value: 'summary_macro', label: Text('{{summary}}')),
            ],
            selected: {_injectionTarget},
            onSelectionChanged: (s) => setState(() => _injectionTarget = s.first),
            style: ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 12),
          _sectionLabel('Generation Rules'),
          _promptPresetSelector(),
          const SizedBox(height: 12),
          _sectionLabel('Generation API'),
          _switchTile('Use LLM API', _generationSource != 'custom', (v) => setState(() => _generationSource = v ? 'current' : 'custom'),
              subtitle: 'Use the same endpoint as LLM for memory generation'),
          if (_generationSource == 'custom') ...[
            const SizedBox(height: 8),
            _textField('Endpoint', _generationEndpoint, (v) => setState(() => _generationEndpoint = v), hint: 'https://...'),
            const SizedBox(height: 8),
            _textField('Model', _generationModel, (v) => setState(() => _generationModel = v), hint: 'gpt-4o-mini'),
            const SizedBox(height: 8),
            _textField('API Key', _generationApiKey, (v) => setState(() => _generationApiKey = v), hint: 'sk-...', obscure: true),
          ] else ...[
            const SizedBox(height: 8),
            _textField('Model Override (optional)', _generationModel, (v) => setState(() => _generationModel = v), hint: 'Leave blank for current LLM model'),
          ],
          const SizedBox(height: 8),
          _numberField('Temperature Override', _generationTemperature.round(), (v) => setState(() => _generationTemperature = v.toDouble()), min: 0, max: 200,
              hint: '0 = use API default'),
          _numberField('Output Token Limit', _generationMaxTokens, (v) => setState(() => _generationMaxTokens = v), min: 0, max: 32000,
              hint: '0 = auto (recommended 2000-4000)'),
          const SizedBox(height: 12),
          _sectionLabel('Search'),
          _switchTile('Vector Search', _vectorSearchEnabled, (v) => setState(() => _vectorSearchEnabled = v)),
          if (_vectorSearchEnabled) ...[
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'plain', label: Text('Plain')),
                ButtonSegment(value: 'glaze', label: Text('Glaze')),
                ButtonSegment(value: 'both', label: Text('Both')),
              ],
              selected: {_keyMatchMode},
              onSelectionChanged: (s) => setState(() => _keyMatchMode = s.first),
              style: ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged, {String? subtitle}) {
    return SwitchListTile(
      title: Text(label, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)) : null,
      value: value,
      onChanged: onChanged,
      dense: true,
      activeThumbColor: AppColors.accent,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _numberField(String label, int value, ValueChanged<int> onChanged, {int min = 0, int max = 99999, String? hint}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.textPrimary))),
        SizedBox(
          width: 80,
          child: DropdownButton<int>(
            value: value.clamp(min, max),
            items: List.generate(max - min + 1, (i) => DropdownMenuItem(value: min + i, child: Text('${min + i}'))),
            onChanged: (v) => onChanged(v ?? value),
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 14, color: AppColors.accent),
          ),
        ),
      ],
    );
  }

  Widget _textField(String label, String value, ValueChanged<String> onChanged, {String? hint, bool obscure = false}) {
    return TextField(
      onChanged: onChanged,
      controller: TextEditingController(text: value)..selection = TextSelection.collapsed(offset: value.length),
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _promptPresetSelector() {
    final presets = MemoryPromptPresets.builtIn;
    return GestureDetector(
      onTap: () async {
        final result = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: presets.map((p) => ListTile(
                title: Text(p.label, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                trailing: p.key == _promptPreset ? Icon(Icons.check, color: AppColors.accent, size: 20) : null,
                onTap: () => Navigator.pop(ctx, p.key),
              )).toList(),
            ),
          ),
        );
        if (result != null) setState(() => _promptPreset = result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(MemoryPromptPresets.label(_promptPreset), style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
            Icon(Icons.arrow_drop_down, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
    );
  }
}
