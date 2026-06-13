import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/api_connection_tester.dart';
import '../../../core/llm/lorebook_providers.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../core/state/shared_prefs_provider.dart';
import '../../../shared/shell/shell_header_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_error_dialog.dart';
import '../../../shared/widgets/glaze_toast.dart';

class EmbeddingSettingsScreen extends ConsumerStatefulWidget {
  const EmbeddingSettingsScreen({super.key});

  @override
  ConsumerState<EmbeddingSettingsScreen> createState() =>
      _EmbeddingSettingsScreenState();
}

class _EmbeddingSettingsScreenState
    extends ConsumerState<EmbeddingSettingsScreen> with ShellHeaderMixin {
  @override
  int get headerBranchIndex => 2;

  @override
  ShellHeaderConfig buildShellHeader() => ShellHeaderConfig(
    title: 'title_embedding_settings'.tr(),
    showBack: true,
    onBack: () => context.go('/tools'),
  );

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync fields when embeddingConfigProvider updates (e.g. after API list loads)
    final config = ref.read(embeddingConfigProvider);
    if (config.endpoint.isNotEmpty && _endpointCtrl.text.isEmpty) {
      _endpointCtrl.text = config.endpoint;
      _apiKeyCtrl.text = config.apiKey;
      _modelCtrl.text = config.model;
      _maxChunkTokensCtrl.text = config.maxChunkTokens.toString();
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
    final maxChunkTokens = int.tryParse(_maxChunkTokensCtrl.text) ?? 8192;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setInt('gz_embedding_max_chunk_tokens', maxChunkTokens);

    final current = ref.read(lorebookSettingsProvider);
    ref.read(lorebookSettingsProvider.notifier).state = current.copyWith(
      searchType: _searchType,
      vectorThreshold: double.tryParse(_thresholdCtrl.text) ?? 0.45,
      vectorTopK: int.tryParse(_topKCtrl.text) ?? 10,
      scanDepth: int.tryParse(_scanDepthCtrl.text) ?? 10,
    );

    if (mounted) GlazeToast.show(context, 'settings_saved'.tr());
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final result = await ApiConnectionTester().testEmbedding(
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
    );
    if (!mounted) return;
    switch (result) {
      case ApiTestSuccess(:final message):
        GlazeToast.show(context, message);
      case ApiTestFailure(:final error):
        GlazeErrorDialog.show(context, error, prefix: 'Failed: ');
    }
    if (mounted) setState(() => _isTesting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cs.surface,
      body: Column(
        children: [
          const SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(height: 56),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Text(
                  'label_search_type'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SearchModeChip(
                      label: 'search_type_keys'.tr(),
                      selected: _searchType == 'keyword',
                      onTap: () => setState(() => _searchType = 'keyword'),
                    ),
                    const SizedBox(width: 8),
                    _SearchModeChip(
                      label: 'search_type_vector'.tr(),
                      selected: _searchType == 'vector',
                      onTap: () => setState(() => _searchType = 'vector'),
                    ),
                    const SizedBox(width: 8),
                    _SearchModeChip(
                      label: 'search_type_both'.tr(),
                      selected: _searchType == 'both',
                      onTap: () => setState(() => _searchType = 'both'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'section_embeddings'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _field(
                  'label_embedding_endpoint'.tr(),
                  _endpointCtrl,
                  hint: 'http://127.0.0.1:11434/v1',
                ),
                const SizedBox(height: 8),
                _field('label_embedding_key'.tr(), _apiKeyCtrl, hint: 'Optional', obscure: true),
                const SizedBox(height: 8),
                _field('label_embedding_model'.tr(), _modelCtrl, hint: 'text-embedding-3-small'),
                const SizedBox(height: 8),
                _field('label_max_chunk_tokens'.tr(), _maxChunkTokensCtrl, hint: '8192'),
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
                    label: Text(_isTesting ? 'btn_testing'.tr() : 'btn_test_connection'.tr()),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'vector_search_params'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _field('label_similarity_threshold'.tr(), _thresholdCtrl, hint: '0.45'),
                const SizedBox(height: 8),
                _field('label_top_k'.tr(), _topKCtrl, hint: '10'),
                const SizedBox(height: 8),
                _field('label_vector_scan_depth'.tr(), _scanDepthCtrl, hint: '10'),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.cs.primary,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _save,
                    child: Text('btn_save'.tr()),
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
      style: TextStyle(color: context.cs.onSurface, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 12),
        hintStyle: TextStyle(
          color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
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
        ? context.cs.primary
        : Colors.white.withValues(alpha: 0.1);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? context.cs.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? context.cs.primary : context.cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
