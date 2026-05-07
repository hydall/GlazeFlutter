import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/embedding_service.dart';
import '../../core/llm/sse_client.dart';
import '../../core/models/api_config.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/sheet_view.dart';
import 'api_list_provider.dart';
import 'widgets/connection_status.dart';
import 'widgets/settings_items.dart';

class ApiSettingsScreen extends ConsumerStatefulWidget {
  final bool startExpanded;
  const ApiSettingsScreen({super.key, this.startExpanded = false});

  @override
  ConsumerState<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends ConsumerState<ApiSettingsScreen> {
  int _tab = 0; // 0 = LLM, 1 = Embeddings

  bool _showApiKey = false;
  bool _isLoadingModels = false;
  ApiConnectionStatus _llmStatus = ApiConnectionStatus.idle;
  String _llmError = '';
  ApiConnectionStatus _embStatus = ApiConnectionStatus.idle;
  String _embError = '';
  List<Map<String, dynamic>> _fetchedModels = [];

  // Text controllers
  final _nameCtrl = TextEditingController();
  final _endpointCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _maxTokensCtrl = TextEditingController();
  final _contextSizeCtrl = TextEditingController();
  final _embEndpointCtrl = TextEditingController();
  final _embApiKeyCtrl = TextEditingController();
  final _embModelCtrl = TextEditingController();
  final _embChunkTokensCtrl = TextEditingController();

  // Non-text form state
  double _temperature = 0.7;
  double _topP = 0.9;
  bool _stream = true;
  bool _requestReasoning = false;
  String _reasoningEffort = 'medium';
  bool _omitTemperature = false;
  bool _omitTopP = false;
  bool _omitReasoning = false;
  bool _omitReasoningEffort = false;
  bool _embeddingEnabled = false;
  bool _embeddingUseSame = true;

  String? _loadedPresetId;
  final _scrollController = ScrollController();
  Timer? _saveTimer;
  bool _loading = false;

  List<TextEditingController> get _ctrls => [
    _nameCtrl,
    _endpointCtrl,
    _keyCtrl,
    _modelCtrl,
    _maxTokensCtrl,
    _contextSizeCtrl,
    _embEndpointCtrl,
    _embApiKeyCtrl,
    _embModelCtrl,
    _embChunkTokensCtrl,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _ctrls) {
      c.addListener(_scheduleSave);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActivePreset());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _scrollController.dispose();
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ── State helpers ─────────────────────────────────────────────────────────────

  void _goBack() {
    if (widget.startExpanded) {
      context.go('/tools');
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _scheduleSave() {
    if (_loading) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _save);
  }

  void _loadActivePreset() {
    final config = ref.read(activeApiConfigProvider);
    if (config != null) _loadFromConfig(config);
  }

  void _loadFromConfig(ApiConfig config) {
    if (config.id == _loadedPresetId) return;
    _loadedPresetId = config.id;
    _loading = true;

    _nameCtrl.text = config.name;
    _endpointCtrl.text = config.endpoint;
    _keyCtrl.text = config.apiKey;
    _modelCtrl.text = config.model;
    _maxTokensCtrl.text = config.maxTokens.toString();
    _contextSizeCtrl.text = config.contextSize.toString();
    _embEndpointCtrl.text = config.embeddingEndpoint;
    _embApiKeyCtrl.text = config.embeddingApiKey;
    _embModelCtrl.text = config.embeddingModel;
    _embChunkTokensCtrl.text = config.embeddingMaxChunkTokens.toString();

    setState(() {
      _temperature = config.temperature;
      _topP = config.topP;
      _stream = config.stream;
      _requestReasoning = config.requestReasoning;
      _reasoningEffort = config.reasoningEffort;
      _omitTemperature = config.omitTemperature;
      _omitTopP = config.omitTopP;
      _omitReasoning = config.omitReasoning;
      _omitReasoningEffort = config.omitReasoningEffort;
      _embeddingEnabled = config.embeddingEnabled;
      _embeddingUseSame = config.embeddingUseSame;
      _fetchedModels = [];
    });

    _loading = false;
  }

  Future<void> _save() async {
    final config = ref.read(activeApiConfigProvider);
    if (config == null) return;
    await ref
        .read(apiListProvider.notifier)
        .put(
          config.copyWith(
            name: _nameCtrl.text.trim(),
            endpoint: _endpointCtrl.text.trim(),
            apiKey: _keyCtrl.text.trim(),
            model: _modelCtrl.text.trim(),
            maxTokens: int.tryParse(_maxTokensCtrl.text) ?? config.maxTokens,
            contextSize:
                int.tryParse(_contextSizeCtrl.text) ?? config.contextSize,
            temperature: _temperature,
            topP: _topP,
            stream: _stream,
            requestReasoning: _requestReasoning,
            reasoningEffort: _reasoningEffort,
            omitTemperature: _omitTemperature,
            omitTopP: _omitTopP,
            omitReasoning: _omitReasoning,
            omitReasoningEffort: _omitReasoningEffort,
            embeddingEnabled: _embeddingEnabled,
            embeddingUseSame: _embeddingUseSame,
            embeddingEndpoint: _embEndpointCtrl.text.trim(),
            embeddingApiKey: _embApiKeyCtrl.text.trim(),
            embeddingModel: _embModelCtrl.text.trim(),
            embeddingMaxChunkTokens:
                int.tryParse(_embChunkTokensCtrl.text) ??
                config.embeddingMaxChunkTokens,
          ),
        );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(apiListProvider);
    final activeConfig = ref.watch(activeApiConfigProvider);

    if (activeConfig != null && activeConfig.id != _loadedPresetId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFromConfig(activeConfig);
      });
    }

    final list = asyncList.valueOrNull ?? [];
    final activeName = _activeName(activeConfig, list);

    return SheetView(
      startExpanded: widget.startExpanded,
      title: 'API Settings',
      showBack: true,
      onBack: _goBack,
      scrollController: _scrollController,
      actions: [
        SheetViewAction(
          icon: const Icon(Icons.add_rounded, size: 20),
          tooltip: 'New config',
          onPressed: () => _createNewPreset(list),
          color: AppColors.accent,
        ),
      ],
      headerBottom: _buildHeaderBottom(list, activeName),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? _buildEmptyState()
            : _tab == 0
            ? _buildLlmTab()
            : _buildEmbeddingsTab(),
      ),
    );
  }

  String _activeName(ApiConfig? config, List<ApiConfig> list) {
    if (config == null) return list.isEmpty ? 'No configs' : 'Unnamed';
    if (config.name.isNotEmpty) return config.name;
    if (config.model.isNotEmpty) return config.model;
    return 'Unnamed';
  }

  Widget _buildHeaderBottom(List<ApiConfig> list, String activeName) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlazeTabBar(
          tabs: const [
            GlazeTabItem(label: 'LLM', icon: Icons.chat_bubble_outline_rounded),
            GlazeTabItem(label: 'Embeddings', icon: Icons.layers_outlined),
          ],
          activeIndex: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 8),
        // Preset selector pill
        _tab == 0
            ? ConnectionStatus(
                status: _llmStatus,
                errorMessage: _llmError,
                onRetry: _testLlmConnection,
                child: _buildPresetPill(context, list, activeName),
              )
            : _buildPresetPill(context, list, activeName),
      ],
    );
  }

  Widget _buildPresetPill(
    BuildContext context,
    List<ApiConfig> list,
    String activeName,
  ) {
    return GestureDetector(
      onTap: list.isEmpty ? null : () => _showPresetSheet(context, list),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        constraints: const BoxConstraints(maxWidth: 220),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                activeName,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.accent,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.api_rounded, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text(
            'No API configs yet',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _createNewPreset([]),
            child: const Text('Add API Config'),
          ),
        ],
      ),
    );
  }

  // ── LLM tab ───────────────────────────────────────────────────────────────────

  Widget _buildLlmTab() {
    return Builder(
      builder: (context) => ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 12,
          bottom: 32,
        ),
        children: [
          SettingsGroup(
            header: 'Connection',
            children: [
              SettingsItemField(
                label: 'Config Name',
                controller: _nameCtrl,
                placeholder: 'My OpenAI',
              ),
              SettingsItemField(
                label: 'API Endpoint',
                controller: _endpointCtrl,
                placeholder: 'http://127.0.0.1:5000/v1',
              ),
              SettingsItemField(
                label: 'Model Name',
                controller: _modelCtrl,
                placeholder: 'gemini-3-pro-preview',
                suffix: _isLoadingModels
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                          size: 22,
                        ),
                        tooltip: _fetchedModels.isEmpty
                            ? 'Fetch models'
                            : 'Select model',
                        onPressed: _openModelSelector,
                      ),
              ),
              SettingsItemField(
                label: 'API Key',
                controller: _keyCtrl,
                placeholder: 'sk-...',
                obscure: !_showApiKey,
                suffix: IconButton(
                  icon: Icon(
                    _showApiKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showApiKey = !_showApiKey),
                ),
              ),
              SettingsItemSwitch(
                label: 'Streaming response',
                subtitle: 'Show text as it is being generated',
                value: _stream,
                onChanged: (v) {
                  setState(() => _stream = v);
                  _scheduleSave();
                },
              ),
            ],
          ),
          SettingsGroup(
            header: 'Generation Parameters',
            children: [
              SettingsItemRange(
                label: 'Temperature',
                value: _temperature,
                min: 0,
                max: 2,
                divisions: 200,
                onChanged: (v) {
                  setState(() => _temperature = v);
                  _scheduleSave();
                },
              ),
              SettingsItemRange(
                label: 'Top P',
                value: _topP,
                min: 0,
                max: 1,
                divisions: 100,
                onChanged: (v) {
                  setState(() => _topP = v);
                  _scheduleSave();
                },
              ),
              SettingsItemField(
                label: 'Max Output Tokens',
                controller: _maxTokensCtrl,
                placeholder: '8000',
                keyboardType: TextInputType.number,
              ),
              SettingsItemField(
                label: 'Context Size',
                controller: _contextSizeCtrl,
                placeholder: '32000',
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          SettingsGroup(
            header: 'Reasoning',
            children: [
              SettingsItemSwitch(
                label: 'Show Native Reasoning',
                subtitle:
                    "Shows reasoning_content. Doesn't affect model's reasoning.",
                value: _requestReasoning,
                onChanged: (v) {
                  setState(() => _requestReasoning = v);
                  _scheduleSave();
                },
              ),
              SettingsItemSelector(
                label: 'Reasoning Effort',
                currentValue:
                    _reasoningEffort[0].toUpperCase() +
                    _reasoningEffort.substring(1),
                onTap: _openReasoningEffortSelector,
              ),
            ],
          ),
          SettingsGroup(
            header: 'Omit Parameters',
            children: [
              SettingsItemSwitch(
                label: 'Omit Temperature',
                subtitle: "Don't send temperature to API",
                value: _omitTemperature,
                onChanged: (v) {
                  setState(() => _omitTemperature = v);
                  _scheduleSave();
                },
              ),
              SettingsItemSwitch(
                label: 'Omit Top P',
                subtitle: "Don't send top_p to API",
                value: _omitTopP,
                onChanged: (v) {
                  setState(() => _omitTopP = v);
                  _scheduleSave();
                },
              ),
              SettingsItemSwitch(
                label: 'Omit Reasoning',
                subtitle: "Don't send reasoning params to API",
                value: _omitReasoning,
                onChanged: (v) {
                  setState(() => _omitReasoning = v);
                  _scheduleSave();
                },
              ),
              SettingsItemSwitch(
                label: 'Omit Reasoning Effort',
                subtitle: "Don't send reasoning_effort to API",
                value: _omitReasoningEffort,
                onChanged: (v) {
                  setState(() => _omitReasoningEffort = v);
                  _scheduleSave();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Embeddings tab ────────────────────────────────────────────────────────────

  Widget _buildEmbeddingsTab() {
    return Builder(
      builder: (context) => ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 12,
          bottom: 32,
        ),
        children: [
          SettingsGroup(
            header: 'Embeddings',
            children: [
              SettingsItemSwitch(
                label: 'Vector Search',
                subtitle: 'Enable semantic search for lorebook entries',
                value: _embeddingEnabled,
                onChanged: (v) {
                  setState(() => _embeddingEnabled = v);
                  _scheduleSave();
                },
              ),
              if (_embeddingEnabled) ...[
                SettingsItemSwitch(
                  label: 'Use LLM API',
                  subtitle: 'Use the same endpoint as LLM for embeddings',
                  value: _embeddingUseSame,
                  onChanged: (v) {
                    setState(() => _embeddingUseSame = v);
                    _scheduleSave();
                  },
                ),
                if (!_embeddingUseSame) ...[
                  SettingsItemField(
                    label: 'Embedding Endpoint',
                    controller: _embEndpointCtrl,
                    placeholder: 'http://127.0.0.1:11434/v1',
                  ),
                  SettingsItemField(
                    label: 'Embedding Model',
                    controller: _embModelCtrl,
                    placeholder: 'text-embedding-3-small',
                  ),
                  SettingsItemField(
                    label: 'API Key',
                    controller: _embApiKeyCtrl,
                    placeholder: 'sk-...',
                    obscure: true,
                  ),
                ],
                if (_embeddingUseSame)
                  SettingsItemField(
                    label: 'Embedding Model',
                    controller: _embModelCtrl,
                    placeholder: 'text-embedding-3-small',
                  ),
                SettingsItemField(
                  label: 'Max Tokens Per Chunk',
                  controller: _embChunkTokensCtrl,
                  placeholder: '512',
                  keyboardType: TextInputType.number,
                ),
              ],
            ],
          ),
          if (_embeddingEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _embStatus == ApiConnectionStatus.connecting
                    ? null
                    : _testEmbConnection,
                icon: _embStatus == ApiConnectionStatus.connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find_rounded),
                label: Text(
                  _embStatus == ApiConnectionStatus.connecting
                      ? 'Testing...'
                      : 'Test Connection',
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Sheet actions ─────────────────────────────────────────────────────────────

  Future<void> _showPresetSheet(
    BuildContext context,
    List<ApiConfig> list,
  ) async {
    final activeId =
        ref.read(activeApiPresetIdProvider) ??
        (list.isNotEmpty ? list.first.id : null);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PresetSheet(
        configs: list,
        activeId: activeId,
        onSelect: (config) {
          _saveTimer?.cancel();
          ref.read(activeApiPresetIdProvider.notifier).state = config.id;
          _loadedPresetId = null;
          _loadFromConfig(config);
        },
        onNew: () => _createNewPreset(list),
        onDelete: (id) async {
          await ref.read(apiListProvider.notifier).remove(id);
          if (activeId == id) {
            ref.read(activeApiPresetIdProvider.notifier).state = null;
            _loadedPresetId = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadActivePreset();
            });
          }
        },
      ),
    );
  }

  Future<void> _createNewPreset(List<ApiConfig> existing) async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: const Text(
          'New API Config',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'My OpenAI',
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            filled: true,
            fillColor: const Color(0xFF252525),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text(
              'Create',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || name.isEmpty) return;

    final newConfig = ApiConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    await ref.read(apiListProvider.notifier).put(newConfig);
    ref.read(activeApiPresetIdProvider.notifier).state = newConfig.id;
    _loadedPresetId = null;
    _loadFromConfig(newConfig);
  }

  Future<void> _openModelSelector() async {
    if (_fetchedModels.isEmpty) {
      await _fetchModels();
      if (_fetchedModels.isEmpty) return;
    }
    if (!mounted) return;
    final models = _fetchedModels.map((m) => m['id'] as String).toList();
    final current = _modelCtrl.text;
    if (current.isNotEmpty && !models.contains(current)) {
      models.insert(0, current);
    }
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ListSheet(
        title: 'Select Model',
        items: models,
        activeItem: current,
        onSelect: (m) => _modelCtrl.text = m,
      ),
    );
  }

  void _openReasoningEffortSelector() {
    const options = ['auto', 'low', 'medium', 'high'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ListSheet(
        title: 'Reasoning Effort',
        items: options.map((e) => e[0].toUpperCase() + e.substring(1)).toList(),
        activeItem:
            _reasoningEffort[0].toUpperCase() + _reasoningEffort.substring(1),
        onSelect: (label) {
          setState(() => _reasoningEffort = label.toLowerCase());
          _scheduleSave();
        },
      ),
    );
  }

  Future<void> _fetchModels() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    if (endpoint.isEmpty || apiKey.isEmpty) {
      GlazeToast.show(context, 'Enter endpoint and API key first');
      return;
    }
    setState(() => _isLoadingModels = true);
    try {
      final models = await SseClient().fetchModels(
        endpoint: endpoint,
        apiKey: apiKey,
      );
      if (!mounted) return;
      setState(() {
        _fetchedModels = models;
        _isLoadingModels = false;
      });
      if (models.isEmpty) GlazeToast.show(context, 'No models returned');
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingModels = false);
        GlazeToast.error(context, 'Failed: ', e);
      }
    }
  }

  Future<void> _testLlmConnection() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (endpoint.isEmpty || apiKey.isEmpty || model.isEmpty) {
      GlazeToast.show(context, 'Fill endpoint, API key, and model');
      return;
    }
    setState(() {
      _llmStatus = ApiConnectionStatus.connecting;
      _llmError = '';
    });
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
        if (mounted && responseText != null) {
          setState(() {
            _llmStatus = ApiConnectionStatus.connected;
          });
          GlazeToast.show(context, 'Connection successful!');
        }
      } else {
        final exists = models.any((m) => m['id'] == model);
        if (mounted) {
          setState(() {
            _llmStatus = ApiConnectionStatus.connected;
          });
          GlazeToast.show(
            context,
            exists
                ? 'Connected! Model "$model" found.'
                : 'Connected, but "$model" not found.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _llmStatus = ApiConnectionStatus.failed;
          _llmError = e.toString();
        });
        GlazeToast.error(context, 'Connection failed: ', e);
      }
    }
  }

  Future<void> _testEmbConnection() async {
    final String endpoint, apiKey, model;
    if (_embeddingUseSame) {
      endpoint = _endpointCtrl.text.trim();
      apiKey = _keyCtrl.text.trim();
      model = _embModelCtrl.text.trim().isNotEmpty
          ? _embModelCtrl.text.trim()
          : _modelCtrl.text.trim();
    } else {
      endpoint = _embEndpointCtrl.text.trim();
      apiKey = _embApiKeyCtrl.text.trim();
      model = _embModelCtrl.text.trim();
    }
    if (endpoint.isEmpty) {
      GlazeToast.show(context, 'Fill endpoint first');
      return;
    }
    setState(() {
      _embStatus = ApiConnectionStatus.connecting;
      _embError = '';
    });
    try {
      final config = EmbeddingConfig(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        maxChunkTokens: 64,
      );
      final result = await EmbeddingService().getEmbeddings(['test'], config);
      if (!mounted) return;
      if (result.isNotEmpty && result.first.isNotEmpty) {
        setState(() {
          _embStatus = ApiConnectionStatus.connected;
        });
        GlazeToast.show(context, 'Connected (dim: ${result.first.length})');
      } else {
        setState(() {
          _embStatus = ApiConnectionStatus.failed;
          _embError = 'Empty response from embedding API';
        });
        GlazeToast.show(context, 'Empty response from embedding API');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _embStatus = ApiConnectionStatus.failed;
          _embError = e.toString();
        });
        GlazeToast.error(context, 'Connection failed: ', e);
      }
    }
  }
}

// ── Preset selector bottom sheet ──────────────────────────────────────────────

class _PresetSheet extends StatelessWidget {
  final List<ApiConfig> configs;
  final String? activeId;
  final ValueChanged<ApiConfig> onSelect;
  final VoidCallback onNew;
  final ValueChanged<String> onDelete;

  const _PresetSheet({
    required this.configs,
    this.activeId,
    required this.onSelect,
    required this.onNew,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: AppColors.glassBorder),
          left: BorderSide(color: AppColors.glassBorder),
          right: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'API Configs',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.accent,
                  ),
                  tooltip: 'New config',
                  onPressed: () {
                    Navigator.pop(context);
                    onNew();
                  },
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: configs.length,
              itemBuilder: (_, i) {
                final config = configs[i];
                final isActive = config.id == activeId;
                final name = config.name.isNotEmpty
                    ? config.name
                    : config.model.isNotEmpty
                    ? config.model
                    : 'Unnamed';
                return ListTile(
                  leading: Icon(
                    isActive
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isActive
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      color: isActive
                          ? AppColors.accent
                          : AppColors.textPrimary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  subtitle: config.endpoint.isNotEmpty
                      ? Text(
                          config.endpoint
                              .replaceAll(RegExp(r'https?://'), '')
                              .split('/')
                              .first,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: configs.length > 1
                      ? IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            onDelete(config.id);
                          },
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(config);
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ── Generic list selector sheet ───────────────────────────────────────────────

class _ListSheet extends StatelessWidget {
  final String title;
  final List<String> items;
  final String activeItem;
  final ValueChanged<String> onSelect;

  const _ListSheet({
    required this.title,
    required this.items,
    required this.activeItem,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: AppColors.glassBorder),
          left: BorderSide(color: AppColors.glassBorder),
          right: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                final isActive = item == activeItem;
                return ListTile(
                  leading: isActive
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.accent,
                          size: 20,
                        )
                      : const SizedBox(width: 20),
                  title: Text(
                    item,
                    style: TextStyle(
                      color: isActive
                          ? AppColors.accent
                          : AppColors.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(item);
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}
