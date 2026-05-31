import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/sse_client.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/api_connection_tester.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../../shared/widgets/help_tip.dart';
import 'api_list_provider.dart';
import 'widgets/widgets.dart';

class ApiEditorScreen extends ConsumerStatefulWidget {
  final ApiConfig? config;
  const ApiEditorScreen({super.key, this.config});

  @override
  ConsumerState<ApiEditorScreen> createState() => _ApiEditorScreenState();
}

class _ApiEditorScreenState extends ConsumerState<ApiEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  late final _nameCtrl = TextEditingController(text: widget.config?.name ?? '');
  late final _endpointCtrl = TextEditingController(text: widget.config?.endpoint ?? '');
  late final _keyCtrl = TextEditingController(text: widget.config?.apiKey ?? '');
  String _selectedModel = '';
  List<Map<String, dynamic>> _fetchedModels = [];
  bool _isLoadingModels = false;
  late final _maxTokensCtrl = TextEditingController(text: (widget.config?.maxTokens ?? 8000).toString());
  late final _contextSizeCtrl = TextEditingController(text: (widget.config?.contextSize ?? 32000).toString());
  late double _temperature = widget.config?.temperature ?? 0.7;
  late double _topP = widget.config?.topP ?? 0.9;
  late bool _stream = widget.config?.stream ?? true;
  late bool _requestReasoning = widget.config?.requestReasoning ?? false;
  late String _reasoningEffort = widget.config?.reasoningEffort ?? 'medium';
  late bool _omitTemperature = widget.config?.omitTemperature ?? false;
  late bool _omitTopP = widget.config?.omitTopP ?? false;
  late bool _omitReasoning = widget.config?.omitReasoning ?? false;
  late bool _omitReasoningEffort = widget.config?.omitReasoningEffort ?? false;

  late bool _embeddingEnabled;
  late bool _embeddingUseSame;
  late final _embEndpointCtrl = TextEditingController(text: widget.config?.embeddingEndpoint ?? '');
  late final _embApiKeyCtrl = TextEditingController(text: widget.config?.embeddingApiKey ?? '');
  late final _embModelCtrl = TextEditingController(text: widget.config?.embeddingModel ?? '');
  late final _embChunkTokensCtrl = TextEditingController(
    text: (widget.config?.embeddingMaxChunkTokens ?? 512).toString(),
  );
  bool _isTestingLlm = false;
  bool _isTestingEmb = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedModel = widget.config?.model ?? '';
    _embeddingEnabled = widget.config?.embeddingEnabled ?? false;
    _embeddingUseSame = widget.config?.embeddingUseSame ?? true;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _endpointCtrl.dispose();
    _keyCtrl.dispose();
    _maxTokensCtrl.dispose();
    _contextSizeCtrl.dispose();
    _embEndpointCtrl.dispose();
    _embApiKeyCtrl.dispose();
    _embModelCtrl.dispose();
    _embChunkTokensCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlazeScaffold(
      title: widget.config != null
          ? '${'action_edit'.tr()} ${'tab_api'.tr()}'
          : 'settings_new_config_title'.tr(),
      onBack: () => Navigator.of(context).pop(),
      actions: [
        TextButton(
          onPressed: _save,
          child: Text('btn_save'.tr(), style: const TextStyle(color: Colors.white)),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'settings_config_name'.tr(),
                hintText: 'My OpenAI',
                prefixIcon: const Icon(Icons.label),
                isDense: true,
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: context.cs.primary,
            unselectedLabelColor: context.cs.onSurfaceVariant,
            indicatorColor: context.cs.primary,
            tabs: [
              const Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'LLM'),
              Tab(icon: const Icon(Icons.layers_outlined, size: 18), text: 'tab_embeddings'.tr()),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLlmTab(),
                _buildEmbeddingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLlmTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('onboarding_connection'.tr(), helpTerm: 'api'),
        TextField(
          controller: _endpointCtrl,
          decoration: const InputDecoration(
            labelText: 'onboarding_label_endpoint',
            hintText: 'http://127.0.0.1:5000/v1',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
        _buildModelSelector(),
        const SizedBox(height: 12),
        TextField(
          controller: _keyCtrl,
          decoration: InputDecoration(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('onboarding_label_key'.tr()), const HelpTip(term: 'apikey')],
            ),
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'settings_fetch_models'.tr(),
              onPressed: _isLoadingModels ? null : _fetchModels,
            ),
          ),
          obscureText: true,
        ),
        SwitchListTile(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('label_stream'.tr()),
              const HelpTip(term: 'streaming'),
            ],
          ),
          subtitle: Text('desc_stream'.tr()),
          value: _stream,
          onChanged: (v) => setState(() => _stream = v),
        ),
        const SizedBox(height: 12),
        _SectionHeader('section_gen_params'.tr(), helpTerm: 'guided'),
        ParamSlider(label: 'label_temperature'.tr(), value: _temperature, min: 0, max: 2, onChanged: (v) => setState(() => _temperature = v)),
        ParamSlider(label: 'label_top_p'.tr(), value: _topP, min: 0, max: 1, onChanged: (v) => setState(() => _topP = v)),
        Row(children: [
          Expanded(child: TextField(controller: _maxTokensCtrl, decoration: InputDecoration(labelText: 'label_max_tokens'.tr(), prefixIcon: const Icon(Icons.numbers)), keyboardType: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _contextSizeCtrl, decoration: InputDecoration(labelText: 'label_context_size'.tr(), prefixIcon: const Icon(Icons.data_array)), keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 12),
        _SectionHeader('label_reasoning_settings'.tr(), helpTerm: 'preset-reasoning'),
        SwitchListTile(
          title: Text('label_reasoning'.tr()),
          subtitle: Text('desc_reasoning'.tr()),
          value: _requestReasoning,
          onChanged: (v) => setState(() => _requestReasoning = v),
        ),
        if (_requestReasoning) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text('${'label_reasoning_effort'.tr()}:', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              ...['auto', 'low', 'medium', 'high'].map((e) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(_reasoningEffortLabel(e), style: const TextStyle(fontSize: 12)),
                  selected: _reasoningEffort == e,
                  onSelected: (_) => setState(() => _reasoningEffort = e),
                  visualDensity: VisualDensity.compact,
                ),
              )),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        _SectionHeader('section_omit_params'.tr()),
        SwitchListTile(title: Text('label_omit_temperature'.tr()), subtitle: Text('desc_omit_temperature'.tr()), value: _omitTemperature, onChanged: (v) => setState(() => _omitTemperature = v)),
        SwitchListTile(title: Text('label_omit_top_p'.tr()), subtitle: Text('desc_omit_top_p'.tr()), value: _omitTopP, onChanged: (v) => setState(() => _omitTopP = v)),
        SwitchListTile(title: Text('label_omit_reasoning'.tr()), subtitle: Text('desc_omit_reasoning'.tr()), value: _omitReasoning, onChanged: (v) => setState(() => _omitReasoning = v)),
        SwitchListTile(title: Text('label_omit_reasoning_effort'.tr()), subtitle: Text('desc_omit_reasoning_effort'.tr()), value: _omitReasoningEffort, onChanged: (v) => setState(() => _omitReasoningEffort = v)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _isTestingLlm ? null : _testLlmConnection,
          icon: _isTestingLlm ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find),
          label: Text(_isTestingLlm ? 'settings_testing'.tr() : 'settings_test_connection'.tr()),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildEmbeddingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('tab_embeddings'.tr(), helpTerm: 'embeddings'),
        SwitchListTile(
          title: Text('search_type_vector'.tr()),
          subtitle: Text('settings_enable_vector_desc'.tr()),
          value: _embeddingEnabled,
          onChanged: (v) => setState(() => _embeddingEnabled = v),
        ),
        if (_embeddingEnabled) ...[
          SwitchListTile(
            title: Text('settings_use_llm_api'.tr()),
            subtitle: Text('settings_use_llm_api_desc'.tr()),
            value: _embeddingUseSame,
            onChanged: (v) => setState(() => _embeddingUseSame = v),
          ),
          if (!_embeddingUseSame) ...[
            TextField(
              controller: _embEndpointCtrl,
              decoration: InputDecoration(
                labelText: 'settings_embedding_endpoint'.tr(),
                hintText: 'http://127.0.0.1:11434/v1',
                prefixIcon: const Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _embModelCtrl,
              decoration: InputDecoration(
                labelText: 'settings_embedding_model'.tr(),
                hintText: 'text-embedding-3-small',
                prefixIcon: const Icon(Icons.hub),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _embApiKeyCtrl,
              decoration: InputDecoration(
                labelText: 'onboarding_label_key'.tr(),
                hintText: 'sk-...',
                prefixIcon: const Icon(Icons.key),
              ),
              obscureText: true,
            ),
          ],
          if (_embeddingUseSame) ...[
            TextField(
              controller: _embModelCtrl,
              decoration: InputDecoration(
                labelText: 'settings_embedding_model'.tr(),
                hintText: 'text-embedding-3-small',
                prefixIcon: const Icon(Icons.hub),
                suffixText: '(uses LLM endpoint & key)',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _embChunkTokensCtrl,
            decoration: InputDecoration(
              labelText: 'settings_max_tokens_chunk'.tr(),
              hintText: '512',
              prefixIcon: const Icon(Icons.data_array),
              helperText: 'Auto-splits long texts into chunks',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isTestingEmb ? null : _testEmbConnection,
            icon: _isTestingEmb ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find),
            label: Text(_isTestingEmb ? 'settings_testing'.tr() : 'settings_test_connection'.tr()),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildModelSelector() {
    if (_isLoadingModels) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()));
    }
    if (_fetchedModels.isNotEmpty) {
      final modelNames = _fetchedModels.map((m) => m['id'] as String).toList();
      if (!modelNames.contains(_selectedModel) && _selectedModel.isNotEmpty) {
        modelNames.insert(0, _selectedModel);
      }
      return DropdownButtonFormField<String>(
        value: modelNames.contains(_selectedModel) ? _selectedModel : null,
        decoration: InputDecoration(labelText: 'onboarding_label_model'.tr(), prefixIcon: const Icon(Icons.smart_toy)),
        items: modelNames.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) { if (v != null) setState(() => _selectedModel = v); },
      );
    }
    return TextField(
      controller: TextEditingController(text: _selectedModel),
      decoration: InputDecoration(
        labelText: 'onboarding_label_model'.tr(),
        hintText: 'gemini-3-pro-preview',
        prefixIcon: const Icon(Icons.smart_toy),
        suffixIcon: IconButton(icon: const Icon(Icons.download, size: 20), tooltip: 'settings_fetch_models'.tr(), onPressed: _isLoadingModels ? null : _fetchModels),
      ),
      onChanged: (v) => _selectedModel = v,
    );
  }

  String _reasoningEffortLabel(String effort) {
    return switch (effort) {
      'auto' => 'theme_auto'.tr(),
      'low' => 'reasoning_effort_low'.tr(),
      'medium' => 'reasoning_effort_medium'.tr(),
      'high' => 'reasoning_effort_high'.tr(),
      _ => effort,
    };
  }

  Future<void> _fetchModels() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    if (endpoint.isEmpty || apiKey.isEmpty) { GlazeToast.show(context, 'settings_err_endpoint_key'.tr()); return; }
    setState(() { _isLoadingModels = true; });
    try {
      final client = SseClient();
      final models = await client.fetchModels(endpoint: endpoint, apiKey: apiKey);
      if (!mounted) return;
      setState(() { _fetchedModels = models; _isLoadingModels = false; });
      if (models.isEmpty) GlazeToast.show(context, 'settings_err_no_models'.tr());
    } catch (e) {
      if (mounted) setState(() { _isLoadingModels = false; });
    }
  }

  Future<void> _testLlmConnection() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    final model = _selectedModel.trim();
    if (endpoint.isEmpty || apiKey.isEmpty || model.isEmpty) { GlazeToast.show(context, 'settings_err_fill_all'.tr()); return; }
    setState(() => _isTestingLlm = true);
    final result = await ApiConnectionTester().testLlm(
      endpoint: endpoint, apiKey: apiKey, model: model,
    );
    if (!mounted) return;
    switch (result) {
      case ApiTestSuccess(:final message):
        GlazeToast.show(context, message);
      case ApiTestFailure(:final error):
        GlazeToast.error(context, 'settings_err_conn_failed'.tr(), error);
    }
    if (mounted) setState(() => _isTestingLlm = false);
  }

  Future<void> _testEmbConnection() async {
    String endpoint, apiKey, model;
    if (_embeddingUseSame) {
      endpoint = _endpointCtrl.text.trim();
      apiKey = _keyCtrl.text.trim();
      model = _embModelCtrl.text.trim().isNotEmpty ? _embModelCtrl.text.trim() : _selectedModel.trim();
    } else {
      endpoint = _embEndpointCtrl.text.trim();
      apiKey = _embApiKeyCtrl.text.trim();
      model = _embModelCtrl.text.trim();
    }
    if (endpoint.isEmpty) { GlazeToast.show(context, 'settings_err_fill_endpoint'.tr()); return; }
    setState(() => _isTestingEmb = true);
    final result = await ApiConnectionTester().testEmbedding(
      endpoint: endpoint, apiKey: apiKey, model: model,
    );
    if (!mounted) return;
    switch (result) {
      case ApiTestSuccess(:final message):
        GlazeToast.show(context, message);
      case ApiTestFailure(:final error):
        GlazeToast.error(context, 'settings_err_conn_failed'.tr(), error);
    }
    if (mounted) setState(() => _isTestingEmb = false);
  }

  Future<void> _save() async {
    final config = ApiConfig(
      id: widget.config?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _selectedModel.trim(),
      mode: 'chat',
      maxTokens: int.tryParse(_maxTokensCtrl.text) ?? 8000,
      contextSize: int.tryParse(_contextSizeCtrl.text) ?? 32000,
      temperature: _temperature,
      topP: _topP,
      stream: _stream,
      requestReasoning: _requestReasoning,
      reasoningEffort: _reasoningEffort,
      omitTemperature: _omitTemperature,
      omitTopP: _omitTopP,
      omitReasoning: _omitReasoning,
      omitReasoningEffort: _omitReasoningEffort,
      embeddingUseSame: _embeddingUseSame,
      embeddingEnabled: _embeddingEnabled,
      embeddingEndpoint: _embEndpointCtrl.text.trim(),
      embeddingApiKey: _embApiKeyCtrl.text.trim(),
      embeddingModel: _embModelCtrl.text.trim(),
      embeddingMaxChunkTokens: int.tryParse(_embChunkTokensCtrl.text) ?? 512,
    );
    await ref.read(apiListProvider.notifier).put(config);
    if (mounted) Navigator.of(context).pop();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? helpTerm;
  const _SectionHeader(this.title, {this.helpTerm});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.cs.onSurfaceVariant,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: helpTerm == null
          ? label
          : Row(mainAxisSize: MainAxisSize.min, children: [label, HelpTip(term: helpTerm!)]),
    );
  }
}
