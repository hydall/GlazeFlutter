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
    return ListTile(
      leading: const Icon(Icons.api),
      title: Text(config.name.isNotEmpty ? config.name : config.model),
      subtitle: Text(
        '${config.endpoint.replaceAll(RegExp(r'https?://'), '').split('/').first} · ${config.model}',
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
  late final _modelCtrl = TextEditingController(text: widget.config?.model ?? '');
  late final _maxTokensCtrl = TextEditingController(
      text: (widget.config?.maxTokens ?? 8000).toString());
  late final _contextSizeCtrl = TextEditingController(
      text: (widget.config?.contextSize ?? 32000).toString());
  late double _temperature = widget.config?.temperature ?? 0.7;
  late double _topP = widget.config?.topP ?? 0.9;
  late bool _stream = widget.config?.stream ?? true;
  bool _isTesting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _endpointCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _maxTokensCtrl.dispose();
    _contextSizeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _endpointCtrl,
            decoration: const InputDecoration(
              labelText: 'Endpoint',
              hintText: 'https://api.openai.com/v1/chat/completions',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            decoration: const InputDecoration(labelText: 'API Key'),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'gpt-4o',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxTokensCtrl,
                  decoration: const InputDecoration(labelText: 'Max Tokens'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _contextSizeCtrl,
                  decoration: const InputDecoration(labelText: 'Context Size'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Temperature'),
              Expanded(
                child: Slider(
                  value: _temperature,
                  min: 0,
                  max: 2,
                  divisions: 20,
                  label: _temperature.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _temperature = v),
                ),
              ),
              SizedBox(
                  width: 48, child: Text(_temperature.toStringAsFixed(1))),
            ],
          ),
          Row(
            children: [
              const Text('Top P'),
              Expanded(
                child: Slider(
                  value: _topP,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: _topP.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _topP = v),
                ),
              ),
              SizedBox(width: 48, child: Text(_topP.toStringAsFixed(1))),
            ],
          ),
          SwitchListTile(
            title: const Text('Stream'),
            value: _stream,
            onChanged: (v) => setState(() => _stream = v),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _isTesting ? null : _testConnection,
            child: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Test Connection'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final config = ApiConfig(
      id: widget.config?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
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
    final model = _modelCtrl.text.trim();

    if (endpoint.isEmpty || apiKey.isEmpty || model.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Fill in endpoint, API key, and model first')),
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
