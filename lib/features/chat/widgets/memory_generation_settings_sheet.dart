import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/sse_client.dart';
import '../../../core/llm/memory_budget.dart';
import '../../../core/models/memory_book.dart';
import '../../../core/services/memory_prompt_presets.dart';
import '../../../core/state/memory_settings_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../settings/api_list_provider.dart';
import 'custom_prompt_manager_sheet.dart';

class MemoryGenerationSettingsSheet extends ConsumerStatefulWidget {
  final MemoryBookSettings settings;

  const MemoryGenerationSettingsSheet({super.key, required this.settings});

  @override
  ConsumerState<MemoryGenerationSettingsSheet> createState() =>
      _MemoryGenerationSettingsSheetState();
}

class _MemoryGenerationSettingsSheetState
    extends ConsumerState<MemoryGenerationSettingsSheet> {
  late bool _enabled;
  late String _memoryMode;
  late bool _autoCreate;
  late bool _autoGenerate;
  late int _maxInjected;
  late String _memoryBudgetPreset;
  late int? _maxInjectedTokens;
  late int _autoCreateInterval;
  late int _batchSize;
  late bool _useDelayedAutomation;
  late String _injectionTarget;
  late String _generationSource;
  late String _promptPreset;
  late String _keyMatchMode;
  late bool _vectorSearchEnabled;
  late double _vectorThreshold;
  late bool _advancedSelectorOpen;
  late bool _diversityAware;
  late double _diversityPenalty;
  late bool _recencyBoost;
  late double _recencyHalfLifeDays;
  late bool _importanceBoost;
  late double _importanceWeight;
  late bool _sourceWindowExclusion;
  late bool _factualContinuityGuardEnabled;
  late bool _classifierEnabled;
  late String _classifierSource;
  late int _classifierTimeoutMs;
  late bool _sidecarEnabled;
  late String _sidecarSource;
  late int _sidecarTimeoutMs;
  late bool _queryIncludeAssistant;
  late int _queryRecentTurns;
  late int _queryMaxChars;

  late final TextEditingController _generationModelCtrl;
  late final TextEditingController _generationEndpointCtrl;
  late final TextEditingController _generationApiKeyCtrl;
  late final TextEditingController _temperatureCtrl;
  late final TextEditingController _maxTokensCtrl;
  late final TextEditingController _memoryBudgetCtrl;
  late final TextEditingController _classifierModelCtrl;
  late final TextEditingController _classifierEndpointCtrl;
  late final TextEditingController _classifierApiKeyCtrl;
  late final TextEditingController _sidecarModelCtrl;
  late final TextEditingController _sidecarEndpointCtrl;
  late final TextEditingController _sidecarApiKeyCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _enabled = s.enabled;
    _memoryMode = _normalizeMemoryMode(s.memoryMode);
    _autoCreate = s.autoCreateEnabled;
    _autoGenerate = s.autoGenerateEnabled;
    _maxInjected = s.maxInjectedEntries;
    _memoryBudgetPreset = _normalizeMemoryBudgetPreset(
      s.memoryBudgetPreset,
      s.maxInjectedTokens,
    );
    _maxInjectedTokens = _memoryBudgetTokensForPreset(
      _memoryBudgetPreset,
      s.maxInjectedTokens,
    );
    _memoryBudgetCtrl = TextEditingController(
      text: (_maxInjectedTokens ?? 6000).toString(),
    );
    _autoCreateInterval = s.autoCreateInterval;
    _batchSize = s.batchSize;
    _useDelayedAutomation = s.useDelayedAutomation;
    _injectionTarget = _migrateInjectionTarget(s.injectionTarget);
    _generationSource = s.generationSource;
    _promptPreset = s.promptPreset;
    _keyMatchMode = s.keyMatchMode;
    _vectorSearchEnabled = s.vectorSearchEnabled;
    _vectorThreshold = ref.read(memoryGlobalSettingsProvider).vectorThreshold;
    _advancedSelectorOpen = false;
    _diversityAware = s.diversityAware;
    _diversityPenalty = s.diversityPenalty;
    _recencyBoost = s.recencyBoost;
    _recencyHalfLifeDays = s.recencyHalfLifeDays;
    _importanceBoost = s.importanceBoost;
    _importanceWeight = s.importanceWeight;
    _sourceWindowExclusion = s.sourceWindowExclusion;
    _factualContinuityGuardEnabled = s.factualContinuityGuardEnabled;
    _classifierEnabled = s.classifierEnabled;
    _classifierSource = _normalizeClassifierSource(s.classifierSource);
    _classifierTimeoutMs = s.classifierTimeoutMs.clamp(500, 10000);
    _sidecarEnabled = s.sidecarEnabled;
    _sidecarSource = _normalizeClassifierSource(s.sidecarSource);
    _sidecarTimeoutMs = s.sidecarTimeoutMs.clamp(500, 15000);
    _queryIncludeAssistant = s.queryIncludeAssistant;
    _queryRecentTurns = s.queryRecentTurns;
    _queryMaxChars = s.queryMaxChars;

    _generationModelCtrl = TextEditingController(text: s.generationModel);
    _generationEndpointCtrl = TextEditingController(text: s.generationEndpoint);
    _generationApiKeyCtrl = TextEditingController(text: s.generationApiKey);
    _classifierModelCtrl = TextEditingController(text: s.classifierModel);
    _classifierEndpointCtrl = TextEditingController(text: s.classifierEndpoint);
    _classifierApiKeyCtrl = TextEditingController(text: s.classifierApiKey);
    _sidecarModelCtrl = TextEditingController(text: s.sidecarModel);
    _sidecarEndpointCtrl = TextEditingController(text: s.sidecarEndpoint);
    _sidecarApiKeyCtrl = TextEditingController(text: s.sidecarApiKey);
    _temperatureCtrl = TextEditingController(
      text: s.generationTemperature != null && s.generationTemperature! > 0
          ? s.generationTemperature!.round().toString()
          : '',
    );
    _maxTokensCtrl = TextEditingController(
      text: s.generationMaxTokens != null && s.generationMaxTokens! > 0
          ? s.generationMaxTokens.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _generationModelCtrl.dispose();
    _generationEndpointCtrl.dispose();
    _generationApiKeyCtrl.dispose();
    _temperatureCtrl.dispose();
    _maxTokensCtrl.dispose();
    _memoryBudgetCtrl.dispose();
    _classifierModelCtrl.dispose();
    _classifierEndpointCtrl.dispose();
    _classifierApiKeyCtrl.dispose();
    _sidecarModelCtrl.dispose();
    _sidecarEndpointCtrl.dispose();
    _sidecarApiKeyCtrl.dispose();
    super.dispose();
  }

  List<MemoryPromptPreset> get _customPrompts =>
      MemoryPromptPreset.fromJsonList(
        ref.read(memoryGlobalSettingsProvider).customPrompts,
      );

  void _save() {
    final temp = int.tryParse(_temperatureCtrl.text);
    final tokens = int.tryParse(_maxTokensCtrl.text);
    final settings = widget.settings.copyWith(
      enabled: _enabled,
      memoryMode: _memoryMode,
      autoCreateEnabled: _autoCreate,
      autoGenerateEnabled: _autoGenerate,
      maxInjectedEntries: _maxInjected,
      maxInjectedTokens: _maxInjectedTokens,
      memoryBudgetPreset: _memoryBudgetPreset,
      autoCreateInterval: _autoCreateInterval,
      batchSize: _batchSize,
      useDelayedAutomation: _useDelayedAutomation,
      injectionTarget: _injectionTarget,
      generationSource: _generationSource,
      generationModel: _generationModelCtrl.text,
      generationEndpoint: _generationEndpointCtrl.text,
      generationApiKey: _generationApiKeyCtrl.text,
      generationTemperature: temp != null && temp > 0 ? temp.toDouble() : null,
      generationMaxTokens: tokens != null && tokens > 0 ? tokens : null,
      promptPreset: _promptPreset,
      keyMatchMode: _keyMatchMode,
      vectorSearchEnabled: _vectorSearchEnabled,
      diversityAware: _diversityAware,
      diversityPenalty: _diversityPenalty,
      recencyBoost: _recencyBoost,
      recencyHalfLifeDays: _recencyHalfLifeDays,
      importanceBoost: _importanceBoost,
      importanceWeight: _importanceWeight,
      sourceWindowExclusion: _sourceWindowExclusion,
      factualContinuityGuardEnabled: _factualContinuityGuardEnabled,
      classifierEnabled: _classifierEnabled,
      classifierSource: _classifierSource,
      classifierModel: _classifierModelCtrl.text,
      classifierEndpoint: _classifierEndpointCtrl.text,
      classifierApiKey: _classifierApiKeyCtrl.text,
      classifierTimeoutMs: _classifierTimeoutMs,
      sidecarEnabled: _sidecarEnabled,
      sidecarSource: _sidecarSource,
      sidecarModel: _sidecarModelCtrl.text,
      sidecarEndpoint: _sidecarEndpointCtrl.text,
      sidecarApiKey: _sidecarApiKeyCtrl.text,
      sidecarTimeoutMs: _sidecarTimeoutMs,
      queryIncludeAssistant: _queryIncludeAssistant,
      queryRecentTurns: _queryRecentTurns,
      queryMaxChars: _queryMaxChars,
    );
    Navigator.pop(
      context,
      MemorySettingsSheetResult(
        settings: settings,
        vectorThreshold: _vectorThreshold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _switchTile(
              'label_enabled'.tr(),
              _enabled,
              (v) => setState(() => _enabled = v),
            ),
            _memoryModeSelector(),
            const SizedBox(height: 12),
            _switchTile(
              'memory_books_auto_create'.tr(),
              _autoCreate,
              (v) => setState(() => _autoCreate = v),
              subtitle: 'memory_books_auto_create_desc'.tr(),
            ),
            _switchTile(
              'memory_books_auto_generate'.tr(),
              _autoGenerate,
              (v) => setState(() => _autoGenerate = v),
              subtitle: 'memory_books_auto_generate_desc'.tr(),
            ),
            if (_autoCreate) ...[
              _switchTile(
                'memory_books_delayed_automation'.tr(),
                _useDelayedAutomation,
                (v) => setState(() => _useDelayedAutomation = v),
                subtitle: 'memory_books_delayed_automation_desc'.tr(),
              ),
              _numberField(
                'memory_books_auto_create_interval'.tr(),
                _autoCreateInterval,
                (v) => setState(() => _autoCreateInterval = v),
                min: 1,
                max: 200,
              ),
            ],
            _numberField(
              'memory_books_batch_size'.tr(),
              _batchSize,
              (v) => setState(() => _batchSize = v),
              min: 1,
              max: 50,
            ),
            _numberField(
              'memory_books_max_entries_prompt'.tr(),
              _maxInjected,
              (v) => setState(() => _maxInjected = v),
              min: 1,
              max: 20,
            ),
            const SizedBox(height: 12),
            _sectionLabel('Memory budget'),
            _memoryBudgetSelector(),
            const SizedBox(height: 8),
            _effectiveBudgetHint(),
            const SizedBox(height: 12),
            _sectionLabel('label_embedding_target'.tr()),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'hard_block', label: Text('Hard Block')),
                ButtonSegment(value: 'macro', label: Text('{{memory}}')),
              ],
              selected: {_injectionTarget},
              onSelectionChanged: (s) =>
                  setState(() => _injectionTarget = s.first),
              style: ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 12),
            _sectionLabel('regex_script_settings'.tr()),
            _promptPresetSelector(),
            const SizedBox(height: 12),
            _sectionLabel('tab_api'.tr()),
            _switchTile(
              'settings_use_llm_api'.tr(),
              _generationSource != 'custom',
              (v) =>
                  setState(() => _generationSource = v ? 'current' : 'custom'),
              subtitle: 'settings_use_llm_api_desc'.tr(),
            ),
            if (_generationSource == 'custom') ...[
              const SizedBox(height: 8),
              _labeledField(
                'settings_embedding_endpoint'.tr(),
                _generationEndpointCtrl,
                hint: 'https://...',
              ),
              const SizedBox(height: 8),
              _modelField(
                _generationModelCtrl,
                hint: 'gpt-4o-mini',
                isCustom: true,
              ),
              const SizedBox(height: 8),
              _labeledField(
                'label_embedding_key'.tr(),
                _generationApiKeyCtrl,
                hint: 'sk-...',
                obscure: true,
              ),
            ] else ...[
              const SizedBox(height: 8),
              _modelField(
                _generationModelCtrl,
                hint: 'Leave blank for current LLM model',
                isCustom: false,
              ),
            ],
            const SizedBox(height: 8),
            _labeledField(
              'label_temperature'.tr(),
              _temperatureCtrl,
              hint: '0 = use API default',
              inputType: TextInputType.number,
            ),
            _labeledField(
              'label_max_tokens'.tr(),
              _maxTokensCtrl,
              hint: '0 = auto (recommended 2000-4000)',
              inputType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _sectionLabel('search'.tr()),
            _switchTile(
              'label_vector_search'.tr(),
              _vectorSearchEnabled,
              (v) => setState(() => _vectorSearchEnabled = v),
            ),
            if (_vectorSearchEnabled) ...[
              const SizedBox(height: 8),
              _sliderField(
                label: 'label_similarity_threshold'.tr(),
                value: _vectorThreshold,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                display: _vectorThreshold.toStringAsFixed(2),
                onChanged: (v) => setState(() => _vectorThreshold = v),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'plain', label: Text('Plain')),
                  ButtonSegment(value: 'glaze', label: Text('Glaze')),
                  ButtonSegment(value: 'both', label: Text('Both')),
                ],
                selected: {_keyMatchMode},
                onSelectionChanged: (s) =>
                    setState(() => _keyMatchMode = s.first),
                style: ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
            const SizedBox(height: 12),
            _advancedSelectorSettings(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('btn_cancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.cs.primary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _save,
                  child: Text('btn_save'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedSelectorSettings() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('memory_advanced_selector_settings'),
        initiallyExpanded: _advancedSelectorOpen,
        onExpansionChanged: (value) =>
            setState(() => _advancedSelectorOpen = value),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'memory_selector_advanced'.tr(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.cs.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          'memory_selector_advanced_desc'.tr(),
          style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
        ),
        children: [
          _switchTile(
            'memory_selector_diversity'.tr(),
            _diversityAware,
            (v) => setState(() => _diversityAware = v),
            subtitle: 'memory_selector_diversity_desc'.tr(),
          ),
          if (_diversityAware)
            _sliderField(
              label: 'memory_selector_diversity_penalty'.tr(),
              value: _diversityPenalty,
              min: 0,
              max: 1,
              divisions: 20,
              display: _diversityPenalty.toStringAsFixed(2),
              onChanged: (v) => setState(() => _diversityPenalty = v),
            ),
          _switchTile(
            'memory_selector_recency'.tr(),
            _recencyBoost,
            (v) => setState(() => _recencyBoost = v),
            subtitle: 'memory_selector_recency_desc'.tr(),
          ),
          if (_recencyBoost)
            _sliderField(
              label: 'memory_selector_recency_half_life'.tr(),
              value: _recencyHalfLifeDays,
              min: 10,
              max: 1000,
              divisions: 99,
              display: _recencyHalfLifeDays.toStringAsFixed(1),
              onChanged: (v) => setState(() => _recencyHalfLifeDays = v),
              helpTitle: 'memory_selector_recency_half_life'.tr(),
              helpBody: 'memory_selector_recency_half_life_help'.tr(),
            ),
          _switchTile(
            'memory_selector_importance'.tr(),
            _importanceBoost,
            (v) => setState(() => _importanceBoost = v),
            subtitle: 'memory_selector_importance_desc'.tr(),
          ),
          if (_importanceBoost)
            _sliderField(
              label: 'memory_selector_importance_weight'.tr(),
              value: _importanceWeight,
              min: 0,
              max: 2,
              divisions: 40,
              display: _importanceWeight.toStringAsFixed(2),
              onChanged: (v) => setState(() => _importanceWeight = v),
            ),
          _switchTile(
            'memory_selector_exclude_visible'.tr(),
            _sourceWindowExclusion,
            (v) => setState(() => _sourceWindowExclusion = v),
            subtitle: 'memory_selector_exclude_visible_desc'.tr(),
          ),
          _switchTile(
            'memory_selector_continuity_guard'.tr(),
            _factualContinuityGuardEnabled,
            (v) => setState(() => _factualContinuityGuardEnabled = v),
            subtitle: 'memory_selector_continuity_guard_desc'.tr(),
          ),
          _classifierSettings(),
          _sidecarSettings(),
          _switchTile(
            'memory_selector_query_assistant'.tr(),
            _queryIncludeAssistant,
            (v) => setState(() => _queryIncludeAssistant = v),
            subtitle: 'memory_selector_query_assistant_desc'.tr(),
          ),
          _numberField(
            'memory_selector_query_recent_turns'.tr(),
            _queryRecentTurns,
            (v) => setState(() => _queryRecentTurns = v),
            min: 1,
            max: 20,
            helpTitle: 'memory_selector_query_recent_turns'.tr(),
            helpBody: 'memory_selector_query_recent_turns_help'.tr(),
          ),
          _numberField(
            'memory_selector_query_max_chars'.tr(),
            _queryMaxChars,
            (v) => setState(() => _queryMaxChars = v),
            min: 500,
            max: 5000,
            step: 250,
            helpTitle: 'memory_selector_query_max_chars'.tr(),
            helpBody: 'memory_selector_query_max_chars_help'.tr(),
          ),
        ],
      ),
    );
  }

  Widget _memoryModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('memory_mode'.tr()),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'legacy',
              label: Text('Legacy'),
              icon: Icon(Icons.restore_rounded),
            ),
            ButtonSegment(
              value: 'fast',
              label: Text('Fast'),
              icon: Icon(Icons.bolt_rounded),
            ),
            ButtonSegment(
              value: 'balanced',
              label: Text('Balanced'),
              icon: Icon(Icons.tune_rounded),
            ),
            ButtonSegment(
              value: 'deep',
              label: Text('Deep'),
              icon: Icon(Icons.manage_search_rounded),
            ),
          ],
          selected: {_memoryMode},
          onSelectionChanged: (s) => setState(() => _memoryMode = s.first),
          style: ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(height: 6),
        Text(
          _memoryMode == 'legacy'
              ? 'memory_mode_legacy_desc'.tr()
              : _memoryMode == 'balanced'
              ? 'memory_mode_balanced_desc'.tr()
              : _memoryMode == 'deep'
              ? 'memory_mode_deep_desc'.tr()
              : 'memory_mode_fast_desc'.tr(),
          style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _classifierSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switchTile(
          'memory_selector_classifier'.tr(),
          _classifierEnabled,
          (v) => setState(() => _classifierEnabled = v),
          subtitle: 'memory_selector_classifier_desc'.tr(),
        ),
        if (_classifierEnabled) ...[
          Text(
            'memory_selector_classifier_disclosure'.tr(),
            style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'current', label: Text('Current API')),
              ButtonSegment(value: 'custom', label: Text('Custom')),
            ],
            selected: {_classifierSource},
            onSelectionChanged: (s) =>
                setState(() => _classifierSource = s.first),
            style: ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 8),
          if (_classifierSource == 'custom') ...[
            _labeledField(
              'settings_embedding_endpoint'.tr(),
              _classifierEndpointCtrl,
              hint: 'https://...',
            ),
            const SizedBox(height: 8),
          ],
          _labeledField(
            'memory_selector_classifier_model'.tr(),
            _classifierModelCtrl,
            hint: _classifierSource == 'custom'
                ? 'gpt-4o-mini'
                : 'memory_selector_current_model_hint'.tr(),
          ),
          if (_classifierSource == 'custom') ...[
            const SizedBox(height: 8),
            _labeledField(
              'label_embedding_key'.tr(),
              _classifierApiKeyCtrl,
              hint: 'sk-...',
              obscure: true,
            ),
          ],
          _numberField(
            'memory_selector_classifier_timeout'.tr(),
            _classifierTimeoutMs,
            (v) => setState(() => _classifierTimeoutMs = v),
            min: 500,
            max: 10000,
            step: 500,
          ),
        ],
      ],
    );
  }

  Widget _sidecarSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switchTile(
          'memory_selector_sidecar'.tr(),
          _sidecarEnabled,
          (v) => setState(() => _sidecarEnabled = v),
          subtitle: 'memory_selector_sidecar_desc'.tr(),
        ),
        if (_sidecarEnabled) ...[
          Text(
            'memory_selector_sidecar_disclosure'.tr(),
            style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'current', label: Text('Current API')),
              ButtonSegment(value: 'custom', label: Text('Custom')),
            ],
            selected: {_sidecarSource},
            onSelectionChanged: (s) => setState(() => _sidecarSource = s.first),
            style: ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 8),
          if (_sidecarSource == 'custom') ...[
            _labeledField(
              'settings_embedding_endpoint'.tr(),
              _sidecarEndpointCtrl,
              hint: 'https://...',
            ),
            const SizedBox(height: 8),
          ],
          _labeledField(
            'memory_selector_sidecar_model'.tr(),
            _sidecarModelCtrl,
            hint: _sidecarSource == 'custom'
                ? 'gpt-4o-mini'
                : 'memory_selector_current_model_hint'.tr(),
          ),
          if (_sidecarSource == 'custom') ...[
            const SizedBox(height: 8),
            _labeledField(
              'label_embedding_key'.tr(),
              _sidecarApiKeyCtrl,
              hint: 'sk-...',
              obscure: true,
            ),
          ],
          _numberField(
            'memory_selector_sidecar_timeout'.tr(),
            _sidecarTimeoutMs,
            (v) => setState(() => _sidecarTimeoutMs = v),
            min: 500,
            max: 15000,
            step: 500,
          ),
        ],
      ],
    );
  }

  Widget _switchTile(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return SwitchListTile(
      title: Text(
        label,
        style: TextStyle(fontSize: 14, color: context.cs.onSurface),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: context.cs.onSurfaceVariant,
              ),
            )
          : null,
      value: value,
      onChanged: onChanged,
      dense: true,
      activeThumbColor: context.cs.primary,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _numberField(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int min = 0,
    int max = 99999,
    int step = 1,
    String? helpTitle,
    String? helpBody,
  }) {
    final normalized = min + (((value - min) / step).round() * step);
    final clamped = normalized.clamp(min, max);
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13, color: context.cs.onSurface),
                ),
              ),
              if (helpTitle != null && helpBody != null)
                _helpButton(title: helpTitle, body: helpBody),
            ],
          ),
        ),
        SizedBox(
          width: 80,
          child: DropdownButton<int>(
            value: clamped,
            items: List.generate(
              ((max - min) ~/ step) + 1,
              (i) => DropdownMenuItem(
                value: min + (i * step),
                child: Text('${min + (i * step)}'),
              ),
            ),
            onChanged: (v) => onChanged(v ?? value),
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 14, color: context.cs.primary),
          ),
        ),
      ],
    );
  }

  Widget _labeledField(
    String label,
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
    TextInputType? inputType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: inputType,
      inputFormatters: inputType == TextInputType.number
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: TextStyle(color: context.cs.onSurface, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(
          color: context.cs.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }

  Widget _memoryBudgetSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'auto', label: Text('Auto')),
        ButtonSegment(value: 'small', label: Text('Small')),
        ButtonSegment(value: 'medium', label: Text('Medium')),
        ButtonSegment(value: 'large', label: Text('Large')),
        ButtonSegment(value: 'custom', label: Text('Custom')),
      ],
      selected: {_memoryBudgetPreset},
      onSelectionChanged: (selected) {
        final preset = selected.first;
        setState(() {
          _memoryBudgetPreset = preset;
          _maxInjectedTokens = _memoryBudgetTokensForPreset(
            preset,
            _maxInjectedTokens,
          );
          if (_maxInjectedTokens != null) {
            _memoryBudgetCtrl.text = _maxInjectedTokens.toString();
          }
        });
      },
      style: ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  Widget _effectiveBudgetHint() {
    final breakdown = MemoryInjectionBudget.describeBudget(
      contextBudgetTokens: 32000,
      percent: widget.settings.maxInjectionBudgetPercent,
      absoluteCap: _maxInjectedTokens,
    );
    final percentTokens = breakdown.percentTokens;
    final absoluteTokens = breakdown.absoluteTokens;
    final effectiveTokens = breakdown.effectiveTokens;
    final text = absoluteTokens == null
        ? 'At 32k context: uses ${_formatTokens(percentTokens)} from the percent budget.'
        : 'At 32k context: min(${_formatTokens(percentTokens)}, ${_formatTokens(absoluteTokens)}) = ${_formatTokens(effectiveTokens)}. Entries cap stays $_maxInjected.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_memoryBudgetPreset == 'custom')
          TextField(
            key: const Key('memory_custom_token_budget_field'),
            controller: _memoryBudgetCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) {
              final parsed = int.tryParse(value);
              setState(() {
                _maxInjectedTokens = parsed != null && parsed > 0
                    ? parsed
                    : null;
              });
            },
            style: TextStyle(color: context.cs.onSurface, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Max injected memory tokens',
              hintText: '6000',
              labelStyle: TextStyle(
                color: context.cs.onSurfaceVariant,
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        if (_memoryBudgetPreset == 'custom') const SizedBox(height: 8),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
        ),
      ],
    );
  }

  String _normalizeMemoryBudgetPreset(String preset, int? tokens) {
    if (preset == 'small' ||
        preset == 'medium' ||
        preset == 'large' ||
        preset == 'custom') {
      return preset;
    }
    return tokens == null ? 'auto' : 'custom';
  }

  int? _memoryBudgetTokensForPreset(String preset, int? currentCustom) {
    switch (preset) {
      case 'auto':
        return null;
      case 'small':
        return 3000;
      case 'medium':
        return 6000;
      case 'large':
        return 10000;
      case 'custom':
        return currentCustom ?? 6000;
      default:
        return null;
    }
  }

  String _formatTokens(int? tokens) {
    if (tokens == null) return 'unlimited';
    return '$tokens tokens';
  }

  Widget _modelField(
    TextEditingController controller, {
    String? hint,
    required bool isCustom,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(color: context.cs.onSurface, fontSize: 14),
      decoration: InputDecoration(
        labelText: isCustom
            ? 'label_model'.tr()
            : "${'label_model'.tr()} (${'hint_optional'.tr()})",
        labelStyle: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(
          color: context.cs.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        suffixIcon: IconButton(
          icon: _fetchingModels
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.cs.primary,
                  ),
                )
              : Icon(
                  Icons.download_rounded,
                  size: 20,
                  color: context.cs.onSurfaceVariant,
                ),
          tooltip: 'memory_books_loading_models'.tr(),
          onPressed: _fetchingModels ? null : _fetchAndPickModel,
        ),
      ),
    );
  }

  bool _fetchingModels = false;

  void _fetchAndPickModel() async {
    setState(() => _fetchingModels = true);
    try {
      String endpoint;
      String apiKey;
      if (_generationSource == 'custom') {
        endpoint = _generationEndpointCtrl.text.trim();
        apiKey = _generationApiKeyCtrl.text.trim();
      } else {
        final config = ref.read(activeApiConfigProvider);
        if (config == null) {
          if (mounted) GlazeToast.show(context, 'settings_no_api_configs'.tr());
          return;
        }
        endpoint = config.endpoint;
        apiKey = config.apiKey;
      }
      if (endpoint.isEmpty) {
        if (mounted) {
          GlazeToast.show(context, 'settings_err_fill_endpoint'.tr());
        }
        return;
      }
      final models = await SseClient().fetchModels(
        endpoint: endpoint,
        apiKey: apiKey,
      );
      if (models.isEmpty) {
        if (mounted) GlazeToast.show(context, 'settings_err_no_models'.tr());
        return;
      }
      if (!mounted) return;
      final ids =
          models
              .map((m) => m['id'] as String?)
              .where((id) => id != null)
              .cast<String>()
              .toList()
            ..sort();
      final selected = await GlazeBottomSheet.show<String>(
        context,
        title: 'settings_select_model'.tr(),
        items: ids
            .map(
              (id) => BottomSheetItem(
                label: id,
                icon: id == _generationModelCtrl.text ? Icons.check : null,
                iconColor: context.cs.primary,
                onTap: () => Navigator.pop(context, id),
              ),
            )
            .toList(),
      );
      if (selected != null) {
        _generationModelCtrl.text = selected;
      }
    } catch (e) {
      if (mounted) GlazeToast.show(context, "${'settings_err_failed'.tr()} $e");
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Widget _promptPresetSelector() {
    final custom = _customPrompts;
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final result = await GlazeBottomSheet.show<String>(
              context,
              title: 'regex_script_settings'.tr(),
              items: [
                ...MemoryPromptPresets.builtIn.map(
                  (p) => BottomSheetItem(
                    label: p.label,
                    icon: p.key == _promptPreset ? Icons.check : null,
                    iconColor: context.cs.primary,
                    onTap: () => Navigator.pop(context, p.key),
                  ),
                ),
                if (custom.isNotEmpty)
                  BottomSheetItem(
                    label: '── Custom ──',
                    centered: true,
                    onTap: () {},
                  ),
                ...custom.map(
                  (p) => BottomSheetItem(
                    label: p.label,
                    icon: p.key == _promptPreset ? Icons.check : null,
                    iconColor: context.cs.primary,
                    onTap: () => Navigator.pop(context, p.key),
                  ),
                ),
              ],
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
                Text(
                  MemoryPromptPresets.label(_promptPreset, custom),
                  style: TextStyle(fontSize: 13, color: context.cs.onSurface),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: context.cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _openPromptManager,
            icon: const Icon(Icons.manage_accounts_rounded, size: 16),
            label: Text('regex_script_settings'.tr()),
            style: TextButton.styleFrom(
              foregroundColor: context.cs.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }

  void _openPromptManager() async {
    final custom = _customPrompts;
    final result = await GlazeBottomSheet.show<List<MemoryPromptPreset>>(
      context,
      title: "${'theme_custom_font_size'.tr()} ${'label_preset_prompts'.tr()}",
      child: CustomPromptManagerSheet(customPrompts: custom, onChanged: (_) {}),
    );
    if (result != null) {
      final notifier = ref.read(memoryGlobalSettingsProvider.notifier);
      final current = ref.read(memoryGlobalSettingsProvider);
      await notifier.save(
        MemoryGlobalSettings(
          enabled: current.enabled,
          memoryMode: current.memoryMode,
          autoCreateEnabled: current.autoCreateEnabled,
          autoGenerateEnabled: current.autoGenerateEnabled,
          maxInjectedEntries: current.maxInjectedEntries,
          maxInjectedTokens: current.maxInjectedTokens,
          memoryBudgetPreset: current.memoryBudgetPreset,
          autoCreateInterval: current.autoCreateInterval,
          useDelayedAutomation: current.useDelayedAutomation,
          injectionTarget: current.injectionTarget,
          batchSize: current.batchSize,
          parallelJobs: current.parallelJobs,
          vectorSearchEnabled: current.vectorSearchEnabled,
          keyMatchMode: current.keyMatchMode,
          generationSource: current.generationSource,
          generationModel: current.generationModel,
          generationUseCurrentModelOverride:
              current.generationUseCurrentModelOverride,
          generationEndpoint: current.generationEndpoint,
          generationApiKey: current.generationApiKey,
          generationTemperature: current.generationTemperature,
          generationMaxTokens: current.generationMaxTokens,
          promptPreset: current.promptPreset,
          diversityAware: current.diversityAware,
          diversityPenalty: current.diversityPenalty,
          recencyBoost: current.recencyBoost,
          recencyHalfLifeDays: current.recencyHalfLifeDays,
          importanceBoost: current.importanceBoost,
          importanceWeight: current.importanceWeight,
          sourceWindowExclusion: current.sourceWindowExclusion,
          factualContinuityGuardEnabled: current.factualContinuityGuardEnabled,
          classifierEnabled: current.classifierEnabled,
          classifierSource: current.classifierSource,
          classifierModel: current.classifierModel,
          classifierEndpoint: current.classifierEndpoint,
          classifierApiKey: current.classifierApiKey,
          classifierTimeoutMs: current.classifierTimeoutMs,
          sidecarEnabled: current.sidecarEnabled,
          sidecarSource: current.sidecarSource,
          sidecarModel: current.sidecarModel,
          sidecarEndpoint: current.sidecarEndpoint,
          sidecarApiKey: current.sidecarApiKey,
          sidecarTimeoutMs: current.sidecarTimeoutMs,
          queryIncludeAssistant: current.queryIncludeAssistant,
          queryRecentTurns: current.queryRecentTurns,
          queryMaxChars: current.queryMaxChars,
          customPrompts: MemoryPromptPreset.toJsonList(result),
        ),
      );
      setState(() {});
    }
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _sliderField({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
    String? helpTitle,
    String? helpBody,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.cs.onSurface,
                      ),
                    ),
                  ),
                  if (helpTitle != null && helpBody != null)
                    _helpButton(title: helpTitle, body: helpBody),
                ],
              ),
            ),
            Text(
              display,
              style: TextStyle(
                fontSize: 12,
                color: context.cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _helpButton({required String title, required String body}) {
    return Tooltip(
      message: 'memory_selector_help_tooltip'.tr(),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(
          Icons.help_outline_rounded,
          size: 16,
          color: context.cs.onSurfaceVariant,
        ),
        onPressed: () => _showHelpDialog(title: title, body: body),
      ),
    );
  }

  Future<void> _showHelpDialog({required String title, required String body}) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('btn_ok'.tr()),
          ),
        ],
      ),
    );
  }
}

class MemorySettingsSheetResult {
  final MemoryBookSettings settings;
  final double vectorThreshold;

  const MemorySettingsSheetResult({
    required this.settings,
    required this.vectorThreshold,
  });
}

/// Translates the legacy `summary_block` / `summary_macro` enum values
/// (pre-{{memory}}-split) to `hard_block` / `macro`. Used both for
/// freshly loaded settings (defence in depth — the underlying model
/// also migrates in its `fromJson`) and for the segmented-button
/// `selected` value (which is keyed by the segment's `value`).
String _migrateInjectionTarget(String raw) {
  if (raw == 'summary_block') return 'hard_block';
  if (raw == 'summary_macro') return 'macro';
  return raw;
}

String _normalizeMemoryMode(String raw) {
  if (raw == 'deep') return 'deep';
  if (raw == 'legacy') return 'legacy';
  return raw == 'balanced' ? 'balanced' : 'fast';
}

String _normalizeClassifierSource(String raw) {
  return raw == 'custom' ? 'custom' : 'current';
}
