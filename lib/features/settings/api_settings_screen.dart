import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/db_provider.dart';
import '../../core/models/api_config.dart';

class ApiSettingsScreen extends ConsumerStatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  ConsumerState<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends ConsumerState<ApiSettingsScreen> {
  final _endpointCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _maxTokensCtrl = TextEditingController(text: '8000');
  final _contextSizeCtrl = TextEditingController(text: '32000');
  double _temperature = 0.7;
  double _topP = 0.9;
  bool _stream = true;
  bool _isTesting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              SizedBox(width: 48, child: Text(_temperature.toStringAsFixed(1))),
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
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
          const SizedBox(height: 8),
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
    final repo = await ref.read(apiConfigRepoProvider.future);
    final config = ApiConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      endpoint: _endpointCtrl.text,
      apiKey: _keyCtrl.text,
      model: _modelCtrl.text,
      maxTokens: int.tryParse(_maxTokensCtrl.text) ?? 8000,
      contextSize: int.tryParse(_contextSizeCtrl.text) ?? 32000,
      temperature: _temperature,
      topP: _topP,
      stream: _stream,
    );
    await repo.put(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API settings saved')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      // TODO: implement connection test
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection test not implemented yet')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }
}
