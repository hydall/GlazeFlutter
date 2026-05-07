import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/llm/embedding_service.dart';
import '../../../core/llm/sse_client.dart';
import '../../../core/models/api_config.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import '../../../shared/widgets/glaze_toast.dart';
import 'api_settings_screen.dart';
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
  String? _modelsError;
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
      title: widget.config != null ? 'Edit API Config' : 'New API Config',
      onBack: () => Navigator.of(context).pop(),
      actions: [
        TextButton(
          onPressed: _save,
          child: const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Config Name',
                hintText: 'My OpenAI',
                prefixIcon: Icon(Icons.label),
                isDense: true,
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.accent,
            tabs: const [
              Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'LLM'),
              Tab(icon: Icon(Icons.layers_outlined, size: 18), text: 'Embeddings'),
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
        const _SectionHeader('Connection'),
        TextField(
          controller: _endpointCtrl,
          decoration: const InputDecoration(
            labelText: 'API Endpoint',
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
            labelText: 'API Key',
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Fetch models',
              onPressed: _isLoadingModels ? null : _fetchModels,
            ),
          ),
          obscureText: true,
        ),
        SwitchListTile(
          title: const Text('Streaming response'),
          subtitle: const Text('Show text as it is being generated'),
          value: _stream,
          onChanged: (v) => setState(() => _stream = v),
        ),
        const SizedBox(height: 12),
        const _SectionHeader('Generation Parameters'),
        ParamSlider(label: 'Temperature', value: _temperature, min: 0, max: 2, onChanged: (v) => setState(() => _temperature = v)),
        ParamSlider(label: 'Top P', value: _topP, min: 0, max: 1, onChanged: (v) => setState(() => _topP = v)),
        Row(children: [
          Expanded(child: TextField(controller: _maxTokensCtrl, decoration: const InputDecoration(labelText: 'Max Output Tokens', prefixIcon: Icon(Icons.numbers)), keyboardType: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _contextSizeCtrl, decoration: const InputDecoration(labelText: 'Context Size', prefixIcon: Icon(Icons.data_array)), keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 12),
        const _SectionHeader('Reasoning'),
        SwitchListTile(
          title: const Text('Show Native Reasoning'),
          subtitle: const Text("Shows reasoning_content. Doesn't affect model's reasoning."),
          value: _requestReasoning,
          onChanged: (v) => setState(() => _requestReasoning = v),
        ),
        if (_requestReasoning) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Text('Reasoning Effort:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              ...['auto', 'low', 'medium', 'high'].map((e) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(e[0].toUpperCase() + e.substring(1), style: const TextStyle(fontSize: 12)),
                  selected: _reasoningEffort == e,
                  onSelected: (_) => setState(() => _reasoningEffort = e),
                  visualDensity: VisualDensity.compact,
                ),
              )),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        const _SectionHeader('Omit Parameters'),
        SwitchListTile(title: const Text('Omit Temperature'), subtitle: const Text("Don't send temperature to API"), value: _omitTemperature, onChanged: (v) => setState(() => _omitTemperature = v)),
        SwitchListTile(title: const Text('Omit Top P'), subtitle: const Text("Don't send top_p to API"), value: _omitTopP, onChanged: (v) => setState(() => _omitTopP = v)),
        SwitchListTile(title: const Text('Omit Reasoning'), subtitle: const Text("Don't send reasoning params to API"), value: _omitReasoning, onChanged: (v) => setState(() => _omitReasoning = v)),
        SwitchListTile(title: const Text('Omit Reasoning Effort'), subtitle: const Text("Don't send reasoning_effort to API"), value: _omitReasoningEffort, onChanged: (v) => setState(() => _omitReasoningEffort = v)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _isTestingLlm ? null : _testLlmConnection,
          icon: _isTestingLlm ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find),
          label: Text(_isTestingLlm ? 'Testing...' : 'Test Connection'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildEmbeddingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader('Embeddings'),
        SwitchListTile(
          title: const Text('Vector Search'),
          subtitle: const Text('Enable semantic search for lorebook entries'),
          value: _embeddingEnabled,
          onChanged: (v) => setState(() => _embeddingEnabled = v),
        ),
        if (_embeddingEnabled) ...[
          SwitchListTile(
            title: const Text('Use LLM API'),
            subtitle: const Text('Use the same endpoint as LLM for embeddings'),
            value: _embeddingUseSame,
            onChanged: (v) => setState(() => _embeddingUseSame = v),
          ),
          if (!_embeddingUseSame) ...[
            TextField(
              controller: _embEndpointCtrl,
              decoration: const InputDecoration(
                labelText: 'Embedding Endpoint',
                hintText: 'http://127.0.0.1:11434/v1',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _embModelCtrl,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'text-embedding-3-small',
                prefixIcon: Icon(Icons.hub),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _embApiKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-...',
                prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
            ),
          ],
          if (_embeddingUseSame) ...[
            TextField(
              controller: _embModelCtrl,
              decoration: const InputDecoration(
                labelText: 'Embedding Model',
                hintText: 'text-embedding-3-small',
                prefixIcon: Icon(Icons.hub),
                suffixText: '(uses LLM endpoint & key)',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _embChunkTokensCtrl,
            decoration: const InputDecoration(
              labelText: 'Max Tokens Per Chunk',
              hintText: '512',
              prefixIcon: Icon(Icons.data_array),
              helperText: 'Auto-splits long texts into chunks',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isTestingEmb ? null : _testEmbConnection,
            icon: _isTestingEmb ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find),
            label: Text(_isTestingEmb ? 'Testing...' : 'Test Connection'),
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
        decoration: const InputDecoration(labelText: 'Model Name', prefixIcon: Icon(Icons.smart_toy)),
        items: modelNames.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) { if (v != null) setState(() => _selectedModel = v); },
      );
    }
    return TextField(
      controller: TextEditingController(text: _selectedModel),
      decoration: InputDecoration(
        labelText: 'Model Name',
        hintText: 'gemini-3-pro-preview',
        prefixIcon: const Icon(Icons.smart_toy),
        suffixIcon: IconButton(icon: const Icon(Icons.download, size: 20), tooltip: 'Fetch models', onPressed: _isLoadingModels ? null : _fetchModels),
      ),
      onChanged: (v) => _selectedModel = v,
    );
  }

  Future<void> _fetchModels() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    if (endpoint.isEmpty || apiKey.isEmpty) { GlazeToast.show(context, 'Enter endpoint and API key first'); return; }
    setState(() { _isLoadingModels = true; _modelsError = null; });
    try {
      final client = SseClient();
      final models = await client.fetchModels(endpoint: endpoint, apiKey: apiKey);
      if (!mounted) return;
      setState(() { _fetchedModels = models; _isLoadingModels = false; });
      if (models.isEmpty) setState(() => _modelsError = 'No models returned by API');
    } catch (e) {
      if (mounted) setState(() { _modelsError = e.toString(); _isLoadingModels = false; });
    }
  }

  Future<void> _testLlmConnection() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    final model = _selectedModel.trim();
    if (endpoint.isEmpty || apiKey.isEmpty || model.isEmpty) { GlazeToast.show(context, 'Fill endpoint, API key, and model'); return; }
    setState(() => _isTestingLlm = true);
    try {
      final client = SseClient();
      final models = await client.fetchModels(endpoint: endpoint, apiKey: apiKey);
      if (!mounted) return;
      if (models.isEmpty) {
        String? responseText;
        await client.streamChatCompletion(endpoint: endpoint, apiKey: apiKey, model: model, messages: [{'role': 'user', 'content': 'Hi'}], maxTokens: 8, temperature: 0.0, topP: 1.0, stream: false, onComplete: (text, _) => responseText = text, onError: (e) => throw e);
        if (!mounted) return;
        if (responseText != null) GlazeToast.show(context, 'Connection successful!');
      } else {
        final exists = models.any((m) => m['id'] == model);
        GlazeToast.show(context, exists ? 'Connection successful! Model "$model" found.' : 'Connected, but "$model" not found.');
      }
    } catch (e) {
      if (mounted) GlazeToast.error(context, 'Connection failed: ', e);
    } finally {
      if (mounted) setState(() => _isTestingLlm = false);
    }
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
    if (endpoint.isEmpty) { GlazeToast.show(context, 'Fill endpoint first'); return; }
    setState(() => _isTestingEmb = true);
    try {
      final service = EmbeddingService();
      final config = EmbeddingConfig(endpoint: endpoint, apiKey: apiKey, model: model, maxChunkTokens: 64);
      final result = await service.getEmbeddings(['test'], config);
      if (!mounted) return;
      if (result.isNotEmpty && result.first.isNotEmpty) {
        GlazeToast.show(context, 'Connected (dim: ${result.first.length})');
      } else {
        GlazeToast.show(context, 'Connection failed: empty response');
      }
    } catch (e) {
      if (mounted) GlazeToast.error(context, 'Connection failed: ', e);
    } finally {
      if (mounted) setState(() => _isTestingEmb = false);
    }
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
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
  );
}
