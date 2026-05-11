import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/llm/embedding_service.dart';
import '../../../core/llm/lorebook_vector_search.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import '../../../shared/widgets/glaze_toast.dart';

class EmbeddingSettingsScreen extends ConsumerStatefulWidget {
  const EmbeddingSettingsScreen({super.key});

  @override
  ConsumerState<EmbeddingSettingsScreen> createState() =>
      _EmbeddingSettingsScreenState();
}

class _EmbeddingSettingsScreenState
    extends ConsumerState<EmbeddingSettingsScreen> {
  late TextEditingController _endpointCtrl;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _maxChunkTokensCtrl;
  late TextEditingController _thresholdCtrl;
  late TextEditingController _topKCtrl;
  late TextEditingController _scanDepthCtrl;
  String _searchType = 'keyword';
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) {
      _initFromDb();
    }
    final settings = ref.read(lorebookSettingsProvider);
    _endpointCtrl = TextEditingController(text: config.endpoint);
    _apiKeyCtrl = TextEditingController(text: config.apiKey);
    _modelCtrl = TextEditingController(text: config.model);
    _maxChunkTokensCtrl = TextEditingController(
      text: config.maxChunkTokens.toString(),
    );
    _thresholdCtrl = TextEditingController(
      text: settings.vectorThreshold.toString(),
    );
    _topKCtrl = TextEditingController(text: settings.vectorTopK.toString());
    _scanDepthCtrl = TextEditingController(text: settings.scanDepth.toString());
    _searchType = settings.searchType;
  }

  Future<void> _initFromDb() async {
    final apiConfigs = await ref.read(apiConfigRepoProvider).getAll();
    final chatConfig = apiConfigs.where((c) => c.mode != 'embedding').firstOrNull;
    if (chatConfig != null && mounted) {
      String ep, ak, md;
      if (chatConfig.embeddingUseSame || chatConfig.embeddingEndpoint.isEmpty) {
        ep = chatConfig.endpoint;
        ak = chatConfig.apiKey;
        md = chatConfig.embeddingModel.isNotEmpty ? chatConfig.embeddingModel : chatConfig.model;
      } else {
        ep = chatConfig.embeddingEndpoint;
        ak = chatConfig.embeddingApiKey;
        md = chatConfig.embeddingModel;
      }
      ref.read(embeddingConfigProvider.notifier).state = EmbeddingConfig(
        endpoint: ep,
        apiKey: ak,
        model: md,
        maxChunkTokens: chatConfig.embeddingMaxChunkTokens,
      );
      setState(() {
        _endpointCtrl.text = ep;
        _apiKeyCtrl.text = ak;
        _modelCtrl.text = md;
        _maxChunkTokensCtrl.text = chatConfig.embeddingMaxChunkTokens.toString();
      });
    }
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _maxChunkTokensCtrl.dispose();
    _thresholdCtrl.dispose();
    _topKCtrl.dispose();
    _scanDepthCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    final config = EmbeddingConfig(
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      maxChunkTokens: int.tryParse(_maxChunkTokensCtrl.text) ?? 8192,
    );
    ref.read(embeddingConfigProvider.notifier).state = config;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('gz_embedding_max_chunk_tokens', config.maxChunkTokens);

    final current = ref.read(lorebookSettingsProvider);
    ref.read(lorebookSettingsProvider.notifier).state = current.copyWith(
      searchType: _searchType,
      vectorThreshold: double.tryParse(_thresholdCtrl.text) ?? 0.45,
      vectorTopK: int.tryParse(_topKCtrl.text) ?? 10,
      scanDepth: int.tryParse(_scanDepthCtrl.text) ?? 10,
    );

    GlazeToast.show(context, 'Saved');
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      final service = EmbeddingService();
      final config = EmbeddingConfig(
        endpoint: _endpointCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        maxChunkTokens: 64,
      );
      final result = await service.getEmbeddings(['test'], config);
      if (result.isNotEmpty && result.first.isNotEmpty) {
        if (mounted) {
          GlazeToast.show(context, 'OK — vector dim: ${result.first.length}');
        }
      }
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Failed: ', e);
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlazeAppBar(
                title: 'Embedding Settings',
                leading: BackButton(onPressed: () => context.go('/tools')),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Text(
                  'Search Mode',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SearchModeChip(
                      label: 'Keyword',
                      selected: _searchType == 'keyword',
                      onTap: () => setState(() => _searchType = 'keyword'),
                    ),
                    const SizedBox(width: 8),
                    _SearchModeChip(
                      label: 'Vector',
                      selected: _searchType == 'vector',
                      onTap: () => setState(() => _searchType = 'vector'),
                    ),
                    const SizedBox(width: 8),
                    _SearchModeChip(
                      label: 'Both',
                      selected: _searchType == 'both',
                      onTap: () => setState(() => _searchType = 'both'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Embedding API',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _field(
                  'Endpoint',
                  _endpointCtrl,
                  hint: 'http://127.0.0.1:11434/v1',
                ),
                const SizedBox(height: 8),
                _field('API Key', _apiKeyCtrl, hint: 'Optional', obscure: true),
                const SizedBox(height: 8),
                _field('Model', _modelCtrl, hint: 'text-embedding-3-small'),
                const SizedBox(height: 8),
                _field('Max Chunk Tokens', _maxChunkTokensCtrl, hint: '8192'),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Vector Search Parameters',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _field('Similarity Threshold', _thresholdCtrl, hint: '0.45'),
                const SizedBox(height: 8),
                _field('Top K Results', _topKCtrl, hint: '10'),
                const SizedBox(height: 8),
                _field('Scan Depth (messages)', _scanDepthCtrl, hint: '10'),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _save,
                    child: const Text('Save Settings'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        hintStyle: TextStyle(
          color: context.colors.textSecondary.withValues(alpha: 0.5),
          fontSize: 12,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _SearchModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SearchModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.colors.accent
        : Colors.white.withValues(alpha: 0.1);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? context.colors.accent : context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
