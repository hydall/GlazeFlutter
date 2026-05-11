import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/sse_client.dart';
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
  ConsumerState<MemoryGenerationSettingsSheet> createState() => _MemoryGenerationSettingsSheetState();
}

class _MemoryGenerationSettingsSheetState extends ConsumerState<MemoryGenerationSettingsSheet> {
  late bool _enabled;
  late bool _autoCreate;
  late bool _autoGenerate;
  late int _maxInjected;
  late int _autoCreateInterval;
  late int _batchSize;
  late bool _useDelayedAutomation;
  late String _injectionTarget;
  late String _generationSource;
  late String _promptPreset;
  late String _keyMatchMode;
  late bool _vectorSearchEnabled;

  late final TextEditingController _generationModelCtrl;
  late final TextEditingController _generationEndpointCtrl;
  late final TextEditingController _generationApiKeyCtrl;
  late final TextEditingController _temperatureCtrl;
  late final TextEditingController _maxTokensCtrl;

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
    _promptPreset = s.promptPreset;
    _keyMatchMode = s.keyMatchMode;
    _vectorSearchEnabled = s.vectorSearchEnabled;

    _generationModelCtrl = TextEditingController(text: s.generationModel);
    _generationEndpointCtrl = TextEditingController(text: s.generationEndpoint);
    _generationApiKeyCtrl = TextEditingController(text: s.generationApiKey);
    _temperatureCtrl = TextEditingController(text: s.generationTemperature != null && s.generationTemperature! > 0 ? s.generationTemperature!.round().toString() : '');
    _maxTokensCtrl = TextEditingController(text: s.generationMaxTokens != null && s.generationMaxTokens! > 0 ? s.generationMaxTokens.toString() : '');
  }

  @override
  void dispose() {
    _generationModelCtrl.dispose();
    _generationEndpointCtrl.dispose();
    _generationApiKeyCtrl.dispose();
    _temperatureCtrl.dispose();
    _maxTokensCtrl.dispose();
    super.dispose();
  }

  List<MemoryPromptPreset> get _customPrompts =>
      MemoryPromptPreset.fromJsonList(ref.read(memoryGlobalSettingsProvider).customPrompts);

  void _save() {
    final temp = int.tryParse(_temperatureCtrl.text);
    final tokens = int.tryParse(_maxTokensCtrl.text);
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
      generationModel: _generationModelCtrl.text,
      generationEndpoint: _generationEndpointCtrl.text,
      generationApiKey: _generationApiKeyCtrl.text,
      generationTemperature: temp != null && temp > 0 ? temp.toDouble() : null,
      generationMaxTokens: tokens != null && tokens > 0 ? tokens : null,
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
            _labeledField('Endpoint', _generationEndpointCtrl, hint: 'https://...'),
            const SizedBox(height: 8),
            _modelField(_generationModelCtrl, hint: 'gpt-4o-mini', isCustom: true),
            const SizedBox(height: 8),
            _labeledField('API Key', _generationApiKeyCtrl, hint: 'sk-...', obscure: true),
          ] else ...[
            const SizedBox(height: 8),
            _modelField(_generationModelCtrl, hint: 'Leave blank for current LLM model', isCustom: false),
          ],
          const SizedBox(height: 8),
          _labeledField('Temperature Override', _temperatureCtrl, hint: '0 = use API default', inputType: TextInputType.number),
          _labeledField('Output Token Limit', _maxTokensCtrl, hint: '0 = auto (recommended 2000-4000)', inputType: TextInputType.number),
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
                style: FilledButton.styleFrom(backgroundColor: context.colors.accent, foregroundColor: Colors.black),
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
      title: Text(label, style: TextStyle(fontSize: 14, color: context.colors.textPrimary)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)) : null,
      value: value,
      onChanged: onChanged,
      dense: true,
      activeThumbColor: context.colors.accent,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _numberField(String label, int value, ValueChanged<int> onChanged, {int min = 0, int max = 99999}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: context.colors.textPrimary))),
        SizedBox(
          width: 80,
          child: DropdownButton<int>(
            value: value.clamp(min, max),
            items: List.generate(max - min + 1, (i) => DropdownMenuItem(value: min + i, child: Text('${min + i}'))),
            onChanged: (v) => onChanged(v ?? value),
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 14, color: context.colors.accent),
          ),
        ),
      ],
    );
  }

  Widget _labeledField(String label, TextEditingController controller, {String? hint, bool obscure = false, TextInputType? inputType}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: inputType,
      inputFormatters: inputType == TextInputType.number ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: context.colors.textSecondary.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _modelField(TextEditingController controller, {String? hint, required bool isCustom}) {
    return TextField(
      controller: controller,
      style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: isCustom ? 'Model' : 'Model Override (optional)',
        labelStyle: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: context.colors.textSecondary.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: IconButton(
          icon: _fetchingModels
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.accent))
              : Icon(Icons.download_rounded, size: 20, color: context.colors.textSecondary),
          tooltip: 'Fetch models from API',
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
          if (mounted) GlazeToast.show(context, 'No API config available');
          return;
        }
        endpoint = config.endpoint;
        apiKey = config.apiKey;
      }
      if (endpoint.isEmpty) {
        if (mounted) GlazeToast.show(context, 'Endpoint is empty');
        return;
      }
      final models = await SseClient().fetchModels(endpoint: endpoint, apiKey: apiKey);
      if (models.isEmpty) {
        if (mounted) GlazeToast.show(context, 'No models found');
        return;
      }
      if (!mounted) return;
      final ids = models.map((m) => m['id'] as String?).where((id) => id != null).cast<String>().toList()..sort();
      final selected = await GlazeBottomSheet.show<String>(
        context,
        title: 'Select Model',
        items: ids.map((id) => BottomSheetItem(
          label: id,
          icon: id == _generationModelCtrl.text ? Icons.check : null,
          iconColor: context.colors.accent,
          onTap: () => Navigator.pop(context, id),
        )).toList(),
      );
      if (selected != null) {
        _generationModelCtrl.text = selected;
      }
    } catch (e) {
      if (mounted) GlazeToast.show(context, 'Failed to fetch models: $e');
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
              title: 'Prompt Preset',
              items: [
                ...MemoryPromptPresets.builtIn.map((p) => BottomSheetItem(
                  label: p.label,
                  icon: p.key == _promptPreset ? Icons.check : null,
                  iconColor: context.colors.accent,
                  onTap: () => Navigator.pop(context, p.key),
                )),
                if (custom.isNotEmpty)
                  BottomSheetItem(
                    label: '── Custom ──',
                    centered: true,
                    onTap: () {},
                  ),
                ...custom.map((p) => BottomSheetItem(
                  label: p.label,
                  icon: p.key == _promptPreset ? Icons.check : null,
                  iconColor: context.colors.accent,
                  onTap: () => Navigator.pop(context, p.key),
                )),
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
                Text(MemoryPromptPresets.label(_promptPreset, custom), style: TextStyle(fontSize: 13, color: context.colors.textPrimary)),
                Icon(Icons.arrow_drop_down, size: 20, color: context.colors.textSecondary),
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
            label: const Text('Manage prompts'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.accent,
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
      title: 'Custom Prompts',
      child: CustomPromptManagerSheet(
        customPrompts: custom,
        onChanged: (_) {},
      ),
    );
    if (result != null) {
      final notifier = ref.read(memoryGlobalSettingsProvider.notifier);
      final current = ref.read(memoryGlobalSettingsProvider);
      await notifier.save(MemoryGlobalSettings(
        enabled: current.enabled,
        autoCreateEnabled: current.autoCreateEnabled,
        autoGenerateEnabled: current.autoGenerateEnabled,
        maxInjectedEntries: current.maxInjectedEntries,
        autoCreateInterval: current.autoCreateInterval,
        useDelayedAutomation: current.useDelayedAutomation,
        injectionTarget: current.injectionTarget,
        batchSize: current.batchSize,
        parallelJobs: current.parallelJobs,
        vectorSearchEnabled: current.vectorSearchEnabled,
        keyMatchMode: current.keyMatchMode,
        generationSource: current.generationSource,
        generationModel: current.generationModel,
        generationUseCurrentModelOverride: current.generationUseCurrentModelOverride,
        generationEndpoint: current.generationEndpoint,
        generationApiKey: current.generationApiKey,
        generationTemperature: current.generationTemperature,
        generationMaxTokens: current.generationMaxTokens,
        promptPreset: current.promptPreset,
        customPrompts: MemoryPromptPreset.toJsonList(result),
      ));
      setState(() {});
    }
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
    );
  }
}
