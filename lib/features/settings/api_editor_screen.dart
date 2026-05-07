import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class _ApiEditorScreenState extends ConsumerState<ApiEditorScreen> {
  late final _nameCtrl = TextEditingController(text: widget.config?.name ?? '');
  late final _endpointCtrl = TextEditingController(
    text: widget.config?.endpoint ?? '',
  );
  late final _keyCtrl = TextEditingController(
    text: widget.config?.apiKey ?? '',
  );
  late String _mode = widget.config?.mode ?? 'chat';
  String _selectedModel = '';
  List<Map<String, dynamic>> _fetchedModels = [];
  bool _isLoadingModels = false;
  String? _modelsError;
  late final _maxTokensCtrl = TextEditingController(
    text: (widget.config?.maxTokens ?? 8000).toString(),
  );
  late final _contextSizeCtrl = TextEditingController(
    text: (widget.config?.contextSize ?? 32000).toString(),
  );
  late double _temperature = widget.config?.temperature ?? 0.7;
  late double _topP = widget.config?.topP ?? 0.9;
  late bool _stream = widget.config?.stream ?? true;
  late bool _requestReasoning = widget.config?.requestReasoning ?? false;
  late String _reasoningEffort = widget.config?.reasoningEffort ?? 'medium';
  late bool _omitTemperature = widget.config?.omitTemperature ?? false;
  late bool _omitTopP = widget.config?.omitTopP ?? false;
  late bool _omitReasoning = widget.config?.omitReasoning ?? false;
  late bool _omitReasoningEffort = widget.config?.omitReasoningEffort ?? false;
  late bool _embeddingUseSame = widget.config?.embeddingUseSame ?? true;
  late final _embEndpointCtrl = TextEditingController(
    text: widget.config?.embeddingEndpoint ?? '',
  );
  late final _embApiKeyCtrl = TextEditingController(
    text: widget.config?.embeddingApiKey ?? '',
  );
  late final _embModelCtrl = TextEditingController(
    text: widget.config?.embeddingModel ?? '',
  );
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.config?.model ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _endpointCtrl.dispose();
    _keyCtrl.dispose();
    _maxTokensCtrl.dispose();
    _contextSizeCtrl.dispose();
    _embEndpointCtrl.dispose();
    _embApiKeyCtrl.dispose();
    _embModelCtrl.dispose();
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Config Name',
              hintText: 'My OpenAI',
              prefixIcon: Icon(Icons.label),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpointCtrl,
            decoration: const InputDecoration(
              labelText: 'Endpoint',
              hintText:
                  'https://api.openai.com/v1  (chat/completions appended auto)',
              prefixIcon: Icon(Icons.link),
            ),
          ),
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
          const SizedBox(height: 16),
          _buildModelSelector(),
          ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxTokensCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Max Tokens',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _contextSizeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Context Size',
                      prefixIcon: Icon(Icons.data_array),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ParamSlider(
              label: 'Temperature',
              value: _temperature,
              min: 0,
              max: 2,
              onChanged: (v) => setState(() => _temperature = v),
            ),
            ParamSlider(
              label: 'Top P',
              value: _topP,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => _topP = v),
            ),
            SwitchListTile(
              title: const Text('Stream'),
              value: _stream,
              onChanged: (v) => setState(() => _stream = v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Show Native Reasoning'),
              subtitle: const Text("Shows reasoning_content. Doesn't affect model's reasoning."),
              value: _requestReasoning,
              onChanged: (v) => setState(() => _requestReasoning = v),
            ),
            if (_requestReasoning) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
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
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Omit Parameters', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
            SwitchListTile(
              title: const Text('Omit Temperature'),
              subtitle: const Text("Don't send temperature to API"),
              value: _omitTemperature,
              onChanged: (v) => setState(() => _omitTemperature = v),
            ),
            SwitchListTile(
              title: const Text('Omit Top P'),
              subtitle: const Text("Don't send top_p to API"),
              value: _omitTopP,
              onChanged: (v) => setState(() => _omitTopP = v),
            ),
            SwitchListTile(
              title: const Text('Omit Reasoning'),
              subtitle: const Text("Don't send reasoning params to API"),
              value: _omitReasoning,
              onChanged: (v) => setState(() => _omitReasoning = v),
            ),
            SwitchListTile(
              title: const Text('Omit Reasoning Effort'),
              subtitle: const Text("Don't send reasoning_effort to API"),
              value: _omitReasoningEffort,
              onChanged: (v) => setState(() => _omitReasoningEffort = v),
            ),
          ],
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Embedding', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          SwitchListTile(
            title: const Text('Use same endpoint for embeddings'),
            value: _embeddingUseSame,
            onChanged: (v) => setState(() => _embeddingUseSame = v),
          ),
          if (!_embeddingUseSame) ...[
            TextField(
              controller: _embEndpointCtrl,
              decoration: const InputDecoration(
                labelText: 'Embedding Endpoint',
                hintText: 'https://api.openai.com/v1',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _embApiKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'Embedding API Key',
                prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
            ),
          ],
          TextField(
            controller: _embModelCtrl,
            decoration: InputDecoration(
              labelText: 'Embedding Model',
              hintText: 'text-embedding-3-small',
              prefixIcon: const Icon(Icons.hub),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector() {
    if (_isLoadingModels) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_fetchedModels.isNotEmpty) {
      final modelNames = _fetchedModels.map((m) => m['id'] as String).toList();
      if (!modelNames.contains(_selectedModel) && _selectedModel.isNotEmpty) {
        modelNames.insert(0, _selectedModel);
      }

      return DropdownButtonFormField<String>(
        initialValue: modelNames.contains(_selectedModel)
            ? _selectedModel
            : null,
        decoration: InputDecoration(
          labelText: _mode == 'chat' ? 'Chat Model' : 'Embedding Model',
          prefixIcon: Icon(_mode == 'chat' ? Icons.smart_toy : Icons.hub),
        ),
        items: modelNames
            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => _selectedModel = v);
        },
      );
    }

    if (_modelsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: TextEditingController(text: _selectedModel),
            decoration: InputDecoration(
              labelText: _mode == 'chat' ? 'Chat Model' : 'Embedding Model',
              prefixIcon: Icon(_mode == 'chat' ? Icons.smart_toy : Icons.hub),
            ),
            onChanged: (v) => _selectedModel = v,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              'Could not fetch models: $_modelsError',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      );
    }

    return TextField(
      controller: TextEditingController(text: _selectedModel),
      decoration: InputDecoration(
        labelText: _mode == 'chat' ? 'Chat Model' : 'Embedding Model',
        hintText: 'gpt-4o',
        prefixIcon: Icon(_mode == 'chat' ? Icons.smart_toy : Icons.hub),
        suffixIcon: IconButton(
          icon: const Icon(Icons.download, size: 20),
          tooltip: 'Fetch models from API',
          onPressed: _isLoadingModels ? null : _fetchModels,
        ),
      ),
      onChanged: (v) => _selectedModel = v,
    );
  }

  Future<void> _fetchModels() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();

    if (endpoint.isEmpty || apiKey.isEmpty) {
      GlazeToast.show(context, 'Enter endpoint and API key first');
      return;
    }

    setState(() {
      _isLoadingModels = true;
      _modelsError = null;
    });

    try {
      final client = SseClient();
      final models = await client.fetchModels(
        endpoint: endpoint,
        apiKey: apiKey,
      );
      if (!mounted) return;

      setState(() {
        _fetchedModels = models;
        _isLoadingModels = false;
      });

      if (models.isEmpty) {
        setState(() => _modelsError = 'No models returned by API');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _modelsError = e.toString();
          _isLoadingModels = false;
        });
      }
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
      embeddingEndpoint: _embEndpointCtrl.text.trim(),
      embeddingApiKey: _embApiKeyCtrl.text.trim(),
      embeddingModel: _embModelCtrl.text.trim(),
    );
    await ref.read(apiListProvider.notifier).put(config);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _testConnection() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    final model = _selectedModel.trim();

    if (endpoint.isEmpty || apiKey.isEmpty || model.isEmpty) {
      if (mounted) {
        GlazeToast.show(context, 'Fill in endpoint, API key, and model first');
      }
      return;
    }

    setState(() => _isTesting = true);
    try {
      final client = SseClient();
      final models = await client.fetchModels(
        endpoint: endpoint,
        apiKey: apiKey,
      );

      if (!mounted) return;

      if (models.isEmpty) {
        String? responseText;
        await client.streamChatCompletion(
          endpoint: endpoint,
          apiKey: apiKey,
          model: model,
          messages: [
            {'role': 'user', 'content': 'Hi'},
          ],
          maxTokens: 8,
          temperature: 0.0,
          topP: 1.0,
          stream: false,
          onComplete: (text, _) => responseText = text,
          onError: (e) => throw e,
        );

        if (!mounted) return;
        if (responseText != null) {
          GlazeToast.show(context, 'Connection successful!');
        }
      } else {
        final modelExists = models.any((m) => m['id'] == model);
        GlazeToast.show(
          context,
          modelExists
              ? 'Connection successful! Model "$model" found.'
              : 'Connected, but model "$model" not found. '
                    'Available: ${models.take(5).map((m) => m['id']).join(', ')}${models.length > 5 ? '...' : ''}',
        );
      }
    } catch (e) {
      if (mounted) {
        GlazeToast.show(context, 'Connection failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }
}
