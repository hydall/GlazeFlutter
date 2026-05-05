import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/llm/sse_client.dart';
import '../../core/state/db_provider.dart';
import '../../core/models/api_config.dart';
import '../../shared/theme/app_colors.dart';

final apiListProvider =
    AsyncNotifierProvider<ApiListNotifier, List<ApiConfig>>(
        ApiListNotifier.new);

class ApiListNotifier extends AsyncNotifier<List<ApiConfig>> {
  @override
  Future<List<ApiConfig>> build() async {
    return ref.watch(apiConfigRepoProvider).getAll();
  }

  Future<void> put(ApiConfig config) async {
    await ref.read(apiConfigRepoProvider).put(config);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(apiConfigRepoProvider).delete(id);
    ref.invalidateSelf();
  }
}

class ApiSettingsScreen extends ConsumerWidget {
  const ApiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(apiListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/tools')),
        title: const Text('API Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ApiEditorScreen(),
              ),
            ),
          ),
        ],
      ),
      body: configs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.api, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    const Text('No API configs yet'),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ApiEditorScreen(),
                        ),
                      ),
                      child: const Text('Add API Config'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _ApiConfigTile(config: list[i]),
              ),
      ),
    );
  }
}

class _ApiConfigTile extends ConsumerWidget {
  final ApiConfig config;
  const _ApiConfigTile({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEmbedding = config.mode == 'embedding';
    return ListTile(
      leading: Icon(
        isEmbedding ? Icons.hub : Icons.smart_toy,
        color: isEmbedding ? AppColors.accent : null,
        size: 20,
      ),
      title: Text(config.name.isNotEmpty ? config.name : config.model),
      subtitle: Text(
        '${config.endpoint.replaceAll(RegExp(r'https?://'), '').split('/').first} · ${config.model} · ${isEmbedding ? 'Embedding' : 'Chat'}',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ApiEditorScreen(config: config),
              ),
            );
          } else if (value == 'delete') {
            ref.read(apiListProvider.notifier).remove(config.id);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ApiEditorScreen(config: config),
        ),
      ),
    );
  }
}

class ApiEditorScreen extends ConsumerStatefulWidget {
  final ApiConfig? config;
  const ApiEditorScreen({super.key, this.config});

  @override
  ConsumerState<ApiEditorScreen> createState() => _ApiEditorScreenState();
}

class _ApiEditorScreenState extends ConsumerState<ApiEditorScreen> {
  late final _nameCtrl = TextEditingController(text: widget.config?.name ?? '');
  late final _endpointCtrl =
      TextEditingController(text: widget.config?.endpoint ?? '');
  late final _keyCtrl = TextEditingController(text: widget.config?.apiKey ?? '');
  late String _mode = widget.config?.mode ?? 'chat';
  String _selectedModel = '';
  List<Map<String, dynamic>> _fetchedModels = [];
  bool _isLoadingModels = false;
  String? _modelsError;
  late final _maxTokensCtrl = TextEditingController(
      text: (widget.config?.maxTokens ?? 8000).toString());
  late final _contextSizeCtrl = TextEditingController(
      text: (widget.config?.contextSize ?? 32000).toString());
  late double _temperature = widget.config?.temperature ?? 0.7;
  late double _topP = widget.config?.topP ?? 0.9;
  late bool _stream = widget.config?.stream ?? true;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isChat = _mode == 'chat';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(widget.config != null ? 'Edit API Config' : 'New API Config'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
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
          _ModeSelector(
            mode: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpointCtrl,
            decoration: const InputDecoration(
              labelText: 'Endpoint',
              hintText: 'https://api.openai.com/v1  (chat/completions appended auto)',
              prefixIcon: Icon(Icons.link),
            ),
            onChanged: (_) {},
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
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          _buildModelSelector(),
          if (isChat) ...[
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
            _ParamSlider(
              label: 'Temperature',
              value: _temperature,
              min: 0,
              max: 2,
              onChanged: (v) => setState(() => _temperature = v),
            ),
            _ParamSlider(
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
          ],
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
        initialValue: modelNames.contains(_selectedModel) ? _selectedModel : null,
        decoration: InputDecoration(
          labelText: _mode == 'chat' ? 'Chat Model' : 'Embedding Model',
          prefixIcon: Icon(
            _mode == 'chat' ? Icons.smart_toy : Icons.hub,
          ),
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
              prefixIcon: Icon(
                _mode == 'chat' ? Icons.smart_toy : Icons.hub,
              ),
            ),
            onChanged: (v) => _selectedModel = v,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              'Could not fetch models: $_modelsError',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
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
        prefixIcon: Icon(
          _mode == 'chat' ? Icons.smart_toy : Icons.hub,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter endpoint and API key first')),
      );
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
      id: widget.config?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _selectedModel.trim(),
      mode: _mode,
      maxTokens: int.tryParse(_maxTokensCtrl.text) ?? 8000,
      contextSize: int.tryParse(_contextSizeCtrl.text) ?? 32000,
      temperature: _temperature,
      topP: _topP,
      stream: _stream,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Fill in endpoint, API key, and model first')),
        );
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
            {'role': 'user', 'content': 'Hi'}
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection successful!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final modelExists = models.any((m) => m['id'] == model);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              modelExists
                  ? 'Connection successful! Model "$model" found.'
                  : 'Connected, but model "$model" not found. '
                      'Available: ${models.take(5).map((m) => m['id']).join(', ')}${models.length > 5 ? '...' : ''}',
            ),
            backgroundColor: modelExists ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }
}

class _ModeSelector extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _ModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _ModeChip(
              icon: Icons.smart_toy,
              label: 'Chat',
              selected: mode == 'chat',
              color: scheme.primary,
              onTap: () => onChanged('chat'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeChip(
              icon: Icons.hub,
              label: 'Embedding',
              selected: mode == 'embedding',
              color: AppColors.accent,
              onTap: () => onChanged('embedding'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:
                    selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 10).toInt(),
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(value.toStringAsFixed(1))),
      ],
    );
  }
}
