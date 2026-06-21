import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/llm/transport/llm_protocol.dart';
import '../../core/llm/transport/transport_factory.dart';
import '../../core/services/api_connection_tester.dart';
import '../../core/models/api_config.dart';
import '../../core/state/shared_prefs_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
import '../../shared/widgets/glaze_error_dialog.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/sheet_view.dart';
import 'api_list_provider.dart';
import 'widgets/connection_status.dart';
import '../../shared/widgets/menu_group.dart';

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
  double _frequencyPenalty = 0.0;
  double _presencePenalty = 0.0;
  int _topK = 0;
  bool _stream = true;
  bool _requestReasoning = false;
  String _reasoningEffort = 'medium';
  bool _omitTemperature = false;
  bool _omitTopP = false;
  bool _omitReasoning = false;
  bool _omitReasoningEffort = false;
  bool _embeddingEnabled = false;
  bool _embeddingUseSame = true;
  String _cacheControlTtl = 'off';
  String _cacheBreakpointMode = 'depth';
  String _sessionIdMode = 'openrouter';
  String _protocol = LlmProtocol.openai;

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
    _flushSave();
    _scrollController.dispose();
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _flushSave() {
    if (_saveTimer?.isActive == true) {
      _saveTimer!.cancel();
      _save();
    }
  }

  void _goBack() {
    _flushSave();
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

  void _persistActiveId(String? id) async {
    final prefs = ref.read(sharedPreferencesProvider).value;
    if (prefs == null) return;
    if (id != null) {
      await prefs.setString('activeApiConfigId', id);
    } else {
      await prefs.remove('activeApiConfigId');
    }
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
      _topK = config.topK;
      _frequencyPenalty = config.frequencyPenalty;
      _presencePenalty = config.presencePenalty;
      _stream = config.stream;
      _requestReasoning = config.requestReasoning;
      _reasoningEffort = config.reasoningEffort;
      _omitTemperature = config.omitTemperature;
      _omitTopP = config.omitTopP;
      _omitReasoning = config.omitReasoning;
      _omitReasoningEffort = config.omitReasoningEffort;
      _embeddingEnabled = config.embeddingEnabled;
      _embeddingUseSame = config.embeddingUseSame;
      _cacheControlTtl = config.cacheControlTtl;
      _cacheBreakpointMode = config.cacheBreakpointMode;
      _sessionIdMode = config.sessionIdMode;
      _protocol = LlmProtocol.isValid(config.protocol)
          ? config.protocol
          : LlmProtocol.openai;
      _applyProtocolUiPolicy(_protocol);
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
            topK: _topK,
            frequencyPenalty: _frequencyPenalty,
            presencePenalty: _presencePenalty,
            stream: _stream,
            requestReasoning: _requestReasoning,
            reasoningEffort: _reasoningEffort,
            omitTemperature: _omitTemperature,
            omitTopP: _omitTopP,
            omitReasoning: _omitReasoning,
            omitReasoningEffort: _omitReasoningEffort,
            embeddingEnabled: _embeddingEnabled,
            embeddingUseSame: _embeddingUseSame,
            cacheControlTtl: _cacheControlTtl,
            cacheBreakpointMode: _cacheBreakpointMode,
            sessionIdMode: _sessionIdMode,
            protocol: _protocol,
            embeddingEndpoint: _embEndpointCtrl.text.trim(),
            embeddingApiKey: _embApiKeyCtrl.text.trim(),
            embeddingModel: _embModelCtrl.text.trim(),
            embeddingMaxChunkTokens:
                int.tryParse(_embChunkTokensCtrl.text) ??
                config.embeddingMaxChunkTokens,
          ),
        );
  }

  bool get _supportsTemperature => true;

  bool get _supportsTopP => true;

  bool get _supportsTopK =>
      _protocol == LlmProtocol.openai ||
      _protocol == LlmProtocol.openrouter ||
      _protocol == LlmProtocol.anthropic ||
      _protocol == LlmProtocol.gemini;

  bool get _supportsFrequencyPenalty =>
      _protocol == LlmProtocol.openai || _protocol == LlmProtocol.openrouter;

  bool get _supportsPresencePenalty =>
      _protocol == LlmProtocol.openai || _protocol == LlmProtocol.openrouter;

  bool get _supportsPromptCache =>
      _protocol == LlmProtocol.anthropic || _protocol == LlmProtocol.openai;

  bool get _supportsReasoning => true;

  bool get _showsOmitSamplingControls =>
      _protocol == LlmProtocol.openai || _protocol == LlmProtocol.openrouter;

  bool get _showsOmitReasoningControls =>
      _protocol == LlmProtocol.openai || _protocol == LlmProtocol.openrouter;

  bool get _hideSamplingWhileReasoningAnthropic =>
      _protocol == LlmProtocol.anthropic && _requestReasoning;

  List<String> get _reasoningEffortOptions {
    switch (_protocol) {
      case LlmProtocol.anthropic:
      case LlmProtocol.gemini:
        return const ['auto', 'min', 'low', 'medium', 'high', 'max'];
      case LlmProtocol.openai:
      case LlmProtocol.openrouter:
      default:
        return const ['auto', 'low', 'medium', 'high'];
    }
  }

  String _normalizeReasoningEffortForProtocol(String protocol, String effort) {
    final allowed =
        protocol == LlmProtocol.anthropic || protocol == LlmProtocol.gemini
        ? const ['auto', 'min', 'low', 'medium', 'high', 'max']
        : const ['auto', 'low', 'medium', 'high'];
    if (allowed.contains(effort)) return effort;
    if (effort == 'min') return 'low';
    if (effort == 'max') return 'high';
    return 'medium';
  }

  void _applyProtocolUiPolicy(String protocol) {
    _reasoningEffort = _normalizeReasoningEffortForProtocol(
      protocol,
      _reasoningEffort,
    );
    if (protocol != LlmProtocol.openai && protocol != LlmProtocol.openrouter) {
      _omitTemperature = false;
      _omitTopP = false;
      _omitReasoning = false;
      _omitReasoningEffort = false;
    }
    if (protocol != LlmProtocol.openai && protocol != LlmProtocol.openrouter) {
      _frequencyPenalty = 0.0;
      _presencePenalty = 0.0;
    }
    if (protocol != LlmProtocol.anthropic && protocol != LlmProtocol.openai) {
      _cacheControlTtl = 'off';
    }
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

    final list = asyncList.value ?? [];
    final activeName = _activeName(activeConfig, list);

    return SheetView(
      startExpanded: widget.startExpanded,
      showRouteBackground: false,
      title: 'menu_app_settings'.tr(),
      showBack: true,
      onBack: _goBack,
      scrollController: _scrollController,
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${'title_error'.tr()}: $e')),
        data: (list) => list.isEmpty
            ? _buildEmptyState()
            : _tab == 0
            ? _buildLlmTab(list, activeName)
            : _buildEmbeddingsTab(list, activeName),
      ),
    );
  }

  String _activeName(ApiConfig? config, List<ApiConfig> list) {
    if (config == null) {
      return list.isEmpty ? 'no_active_connections'.tr() : 'unnamed_entry'.tr();
    }
    if (config.name.isNotEmpty) return config.name;
    if (config.model.isNotEmpty) return config.model;
    return 'unnamed_entry'.tr();
  }

  Widget _buildTopControls(List<ApiConfig> list, String activeName) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlazeTabBar(
          tabs: [
            GlazeTabItem(label: 'LLM', icon: Icons.chat_bubble_outline_rounded),
            GlazeTabItem(
              label: 'tab_embeddings'.tr(),
              icon: Icons.layers_outlined,
            ),
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
          color: context.cs.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                activeName,
                style: TextStyle(
                  color: context.cs.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: context.cs.primary,
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
          Icon(Icons.cloud, size: 64, color: context.cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'settings_no_api_configs'.tr(),
            style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 15),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _createNewPreset([]),
            child: Text('settings_add_api_config'.tr()),
          ),
        ],
      ),
    );
  }

  // ── LLM tab ───────────────────────────────────────────────────────────────────

  Widget _buildLlmTab(List<ApiConfig> list, String activeName) {
    return Builder(
      builder: (context) => ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 12,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildTopControls(list, activeName),
          ),
          MenuGroup(
            compact: true,
            header: 'onboarding_connection'.tr(),
            helpTerm: 'api',
            items: [
              MenuFieldItem(
                label: 'settings_config_name'.tr(),
                controller: _nameCtrl,
                placeholder: 'My OpenAI',
              ),
              MenuSelectorItem(
                label: 'settings_protocol'.tr(),
                currentValue: LlmProtocol.labels[_protocol] ?? _protocol,
                onTap: _openProtocolSelector,
              ),
              if (_protocol != LlmProtocol.openrouter)
                MenuFieldItem(
                  label: 'onboarding_label_endpoint'.tr(),
                  controller: _endpointCtrl,
                  placeholder: 'https://your-endpoint.example',
                ),
              MenuFieldItem(
                label: 'onboarding_label_model'.tr(),
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
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: context.cs.onSurfaceVariant,
                          size: 22,
                        ),
                        tooltip: _fetchedModels.isEmpty
                            ? 'settings_fetch_models'.tr()
                            : 'settings_select_model'.tr(),
                        onPressed: _openModelSelector,
                      ),
              ),
              MenuFieldItem(
                label: 'onboarding_label_key'.tr(),
                helpTerm: 'apikey',
                controller: _keyCtrl,
                placeholder: 'sk-...',
                obscure: !_showApiKey,
                suffix: IconButton(
                  icon: Icon(
                    _showApiKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: context.cs.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showApiKey = !_showApiKey),
                ),
              ),
              MenuSwitchItem(
                label: 'label_stream'.tr(),
                helpTerm: 'streaming',
                description: 'desc_stream'.tr(),
                value: _stream,
                onChanged: (v) {
                  setState(() => _stream = v);
                  _scheduleSave();
                },
              ),
            ],
          ),
          MenuGroup(
            compact: true,
            header: 'section_gen_params'.tr(),
            helpTerm: 'guided',
            items: [
              if (_supportsTemperature && !_hideSamplingWhileReasoningAnthropic)
                MenuRangeItem(
                  label: 'label_temperature'.tr(),
                  value: _temperature,
                  min: 0,
                  max: 2,
                  divisions: 200,
                  onChanged: (v) {
                    setState(() => _temperature = v);
                    _scheduleSave();
                  },
                ),
              if (_supportsTopP && !_hideSamplingWhileReasoningAnthropic)
                MenuRangeItem(
                  label: 'label_top_p'.tr(),
                  value: _topP,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  onChanged: (v) {
                    setState(() => _topP = v);
                    _scheduleSave();
                  },
                ),
              if (_supportsTopK && !_hideSamplingWhileReasoningAnthropic)
                MenuRangeItem(
                  label: 'label_top_k_sampling'.tr(),
                  value: _topK.toDouble(),
                  min: 0,
                  max: 200,
                  divisions: 200,
                  onChanged: (v) {
                    setState(() => _topK = v.round());
                    _scheduleSave();
                  },
                ),
              if (_supportsFrequencyPenalty)
                MenuRangeItem(
                  label: 'label_frequency_penalty'.tr(),
                  value: _frequencyPenalty,
                  min: -2,
                  max: 2,
                  divisions: 80,
                  onChanged: (v) {
                    setState(() => _frequencyPenalty = v);
                    _scheduleSave();
                  },
                ),
              if (_supportsPresencePenalty)
                MenuRangeItem(
                  label: 'label_presence_penalty'.tr(),
                  value: _presencePenalty,
                  min: -2,
                  max: 2,
                  divisions: 80,
                  onChanged: (v) {
                    setState(() => _presencePenalty = v);
                    _scheduleSave();
                  },
                ),
              MenuFieldItem(
                label: 'label_max_tokens'.tr(),
                controller: _maxTokensCtrl,
                placeholder: '8000',
                keyboardType: TextInputType.number,
              ),
              MenuFieldItem(
                label: 'label_context_size'.tr(),
                controller: _contextSizeCtrl,
                placeholder: '32000',
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          MenuGroup(
            compact: true,
            header: 'label_reasoning_settings'.tr(),
            helpTerm: 'preset-reasoning',
            items: [
              if (_supportsReasoning)
                MenuSwitchItem(
                  label: 'label_reasoning'.tr(),
                  description: 'desc_reasoning'.tr(),
                  value: _requestReasoning,
                  onChanged: (v) {
                    setState(() => _requestReasoning = v);
                    _scheduleSave();
                  },
                ),
              if (_supportsReasoning)
                MenuSelectorItem(
                  label: 'label_reasoning_effort'.tr(),
                  currentValue: _reasoningEffortLabel(_reasoningEffort),
                  onTap: _openReasoningEffortSelector,
                ),
              if (_supportsPromptCache)
                MenuSelectorItem(
                  label: 'label_prompt_cache_ttl'.tr(),
                  currentValue: _cacheControlTtlLabel(_cacheControlTtl),
                  onTap: _openCacheControlTtlSelector,
                ),
              if (_supportsPromptCache)
                MenuSelectorItem(
                  label: 'label_prompt_cache_breakpoint'.tr(),
                  currentValue: _cacheBreakpointModeLabel(_cacheBreakpointMode),
                  onTap: _openCacheBreakpointModeSelector,
                ),
              MenuSelectorItem(
                label: 'label_session_id_mode'.tr(),
                currentValue: _sessionIdModeLabel(_sessionIdMode),
                onTap: _openSessionIdModeSelector,
              ),
            ],
          ),
          if (_showsOmitSamplingControls || _showsOmitReasoningControls)
            MenuGroup(
              compact: true,
              header: 'section_omit_params'.tr(),
              items: [
                if (_showsOmitSamplingControls)
                  MenuSwitchItem(
                    label: 'label_omit_temperature'.tr(),
                    description: 'desc_omit_temperature'.tr(),
                    value: _omitTemperature,
                    onChanged: (v) {
                      setState(() => _omitTemperature = v);
                      _scheduleSave();
                    },
                  ),
                if (_showsOmitSamplingControls)
                  MenuSwitchItem(
                    label: 'label_omit_top_p'.tr(),
                    description: 'desc_omit_top_p'.tr(),
                    value: _omitTopP,
                    onChanged: (v) {
                      setState(() => _omitTopP = v);
                      _scheduleSave();
                    },
                  ),
                if (_showsOmitReasoningControls)
                  MenuSwitchItem(
                    label: 'label_omit_reasoning'.tr(),
                    description: 'desc_omit_reasoning'.tr(),
                    value: _omitReasoning,
                    onChanged: (v) {
                      setState(() => _omitReasoning = v);
                      _scheduleSave();
                    },
                  ),
                if (_showsOmitReasoningControls)
                  MenuSwitchItem(
                    label: 'label_omit_reasoning_effort'.tr(),
                    description: 'desc_omit_reasoning_effort'.tr(),
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

  Widget _buildEmbeddingsTab(List<ApiConfig> list, String activeName) {
    return Builder(
      builder: (context) => ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 12,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildTopControls(list, activeName),
          ),
          MenuGroup(
            compact: true,
            header: 'tab_embeddings'.tr(),
            helpTerm: 'embeddings',
            items: [
              MenuSwitchItem(
                label: 'search_type_vector'.tr(),
                description: 'settings_enable_vector_desc'.tr(),
                value: _embeddingEnabled,
                onChanged: (v) {
                  setState(() => _embeddingEnabled = v);
                  _scheduleSave();
                },
              ),
              if (_embeddingEnabled) ...[
                MenuSwitchItem(
                  label: 'settings_use_llm_api'.tr(),
                  description: 'settings_use_llm_api_desc'.tr(),
                  value: _embeddingUseSame,
                  onChanged: (v) {
                    setState(() => _embeddingUseSame = v);
                    _scheduleSave();
                  },
                ),
                if (!_embeddingUseSame) ...[
                  MenuFieldItem(
                    label: 'settings_embedding_endpoint'.tr(),
                    controller: _embEndpointCtrl,
                    placeholder: 'http://127.0.0.1:11434/v1',
                  ),
                  MenuFieldItem(
                    label: 'settings_embedding_model'.tr(),
                    controller: _embModelCtrl,
                    placeholder: 'text-embedding-3-small',
                  ),
                  MenuFieldItem(
                    label: 'onboarding_label_key'.tr(),
                    controller: _embApiKeyCtrl,
                    placeholder: 'sk-...',
                    obscure: true,
                  ),
                ],
                if (_embeddingUseSame)
                  MenuFieldItem(
                    label: 'settings_embedding_model'.tr(),
                    controller: _embModelCtrl,
                    placeholder: 'text-embedding-3-small',
                  ),
                MenuFieldItem(
                  label: 'settings_max_tokens_chunk'.tr(),
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
                  foregroundColor: context.cs.primary,
                  side: BorderSide(
                    color: context.cs.primary.withValues(alpha: 0.4),
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
                      ? 'settings_testing'.tr()
                      : 'settings_test_connection'.tr(),
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
    await GlazeBottomSheet.show<void>(
      context,
      title: 'settings_api_configs_title'.tr(),
      headerAction: IconButton(
        icon: Icon(Icons.add_circle_outline_rounded, color: context.cs.primary),
        tooltip: 'settings_new_config_tooltip'.tr(),
        onPressed: () {
          Navigator.of(context, rootNavigator: true).pop();
          _createNewPreset(list);
        },
      ),
      cardItems: list.map((config) {
        final isActive = config.id == activeId;
        final name = config.name.isNotEmpty
            ? config.name
            : config.model.isNotEmpty
            ? config.model
            : 'unnamed_entry'.tr();

        String? faviconUrl;
        if (config.endpoint.isNotEmpty) {
          try {
            final uri = Uri.parse(config.endpoint);
            if (uri.host.isNotEmpty &&
                !uri.host.contains('127.0.0.1') &&
                !uri.host.contains('localhost')) {
              faviconUrl =
                  'https://www.google.com/s2/favicons?domain=${uri.host}&sz=128';
            }
          } catch (_) {}
        }

        return BottomSheetCardItem(
          label: name,
          sublabel: config.endpoint.isNotEmpty
              ? config.endpoint
                    .replaceAll(RegExp(r'https?://'), '')
                    .split('/')
                    .first
              : null,
          icon: isActive
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          faviconUrl: faviconUrl,
          isActive: isActive,
          actions: [
            if (list.length > 1)
              BottomSheetAction(
                icon: Icons.delete_outline_rounded,
                color: context.cs.onSurfaceVariant,
                onTap: () async {
                  Navigator.of(context, rootNavigator: true).pop();
                  await ref.read(apiListProvider.notifier).remove(config.id);
                  if (activeId == config.id) {
                    ref.read(activeApiPresetIdProvider.notifier).state = null;
                    _persistActiveId(null);
                    _loadedPresetId = null;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _loadActivePreset();
                    });
                  }
                },
              ),
          ],
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _saveTimer?.cancel();
            ref.read(activeApiPresetIdProvider.notifier).state = config.id;
            _persistActiveId(config.id);
            _loadedPresetId = null;
            _loadFromConfig(config);
          },
        );
      }).toList(),
    );
  }

  Future<void> _createNewPreset(List<ApiConfig> existing) async {
    await GlazeBottomSheet.show<void>(
      context,
      title: 'settings_new_config_title'.tr(),
      input: BottomSheetInput(
        placeholder: 'My OpenAI',
        confirmLabel: 'btn_create'.tr(),
        onConfirm: (name) async {
          Navigator.of(context, rootNavigator: true).pop();
          final trimmed = name.trim();
          if (trimmed.isEmpty) return;

          final newConfig = ApiConfig(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: trimmed,
          );
          ref.read(activeApiPresetIdProvider.notifier).state = newConfig.id;
          _persistActiveId(newConfig.id);
          _loadedPresetId = null;
          _loadFromConfig(newConfig);
          await ref.read(apiListProvider.notifier).put(newConfig);
        },
      ),
    );
  }

  Future<void> _openModelSelector() async {
    if (_fetchedModels.isEmpty) {
      await _fetchModels();
      if (_fetchedModels.isEmpty) return;
    }
    if (!mounted) return;
    final models = _fetchedModels.map((m) => m['id'] as String).toList()
      ..sort();
    final current = _modelCtrl.text;
    if (current.isNotEmpty && !models.contains(current)) {
      models.insert(0, current);
    }
    final selectedIndex = models.indexOf(current);
    await GlazeBottomSheet.show<void>(
      context,
      title: 'onboarding_select_model'.tr(),
      scrollToIndex: selectedIndex >= 0 ? selectedIndex : null,
      items: models
          .map(
            (m) => BottomSheetItem(
              label: m,
              icon: m == current ? Icons.check : null,
              iconColor: context.cs.primary,
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                _modelCtrl.text = m;
              },
            ),
          )
          .toList(),
    );
  }

  String _reasoningEffortLabel(String effort) {
    return switch (effort) {
      'auto' => 'reasoning_effort_auto'.tr(),
      'min' => 'reasoning_effort_min'.tr(),
      'low' => 'reasoning_effort_low'.tr(),
      'medium' => 'reasoning_effort_medium'.tr(),
      'high' => 'reasoning_effort_high'.tr(),
      'max' => 'reasoning_effort_max'.tr(),
      _ => effort,
    };
  }

  void _openReasoningEffortSelector() {
    GlazeBottomSheet.show<void>(
      context,
      title: 'label_reasoning_effort'.tr(),
      items: _reasoningEffortOptions.map((e) {
        final label = _reasoningEffortLabel(e);
        final active = e == _reasoningEffort;
        return BottomSheetItem(
          label: label,
          icon: active ? Icons.check : null,
          iconColor: context.cs.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            setState(() => _reasoningEffort = e);
            _scheduleSave();
          },
        );
      }).toList(),
    );
  }

  String _cacheControlTtlLabel(String ttl) {
    return switch (ttl) {
      '5min' => 'prompt_cache_ttl_5min'.tr(),
      '1h' => 'prompt_cache_ttl_1h'.tr(),
      _ => 'prompt_cache_ttl_off'.tr(),
    };
  }

  String _cacheBreakpointModeLabel(String mode) {
    return switch (mode) {
      'stable_prefix' => 'prompt_cache_breakpoint_stable'.tr(),
      _ => 'prompt_cache_breakpoint_depth'.tr(),
    };
  }

  String _sessionIdModeLabel(String mode) {
    return switch (mode) {
      'always' => 'session_id_mode_always'.tr(),
      'off' => 'session_id_mode_off'.tr(),
      _ => 'session_id_mode_openrouter'.tr(),
    };
  }

  void _openCacheControlTtlSelector() {
    const options = ['off', '5min', '1h'];
    GlazeBottomSheet.show<void>(
      context,
      title: 'label_prompt_cache_ttl'.tr(),
      items: options.map((e) {
        final label = _cacheControlTtlLabel(e);
        final active = e == _cacheControlTtl;
        return BottomSheetItem(
          label: label,
          icon: active ? Icons.check : null,
          iconColor: context.cs.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            setState(() => _cacheControlTtl = e);
            _scheduleSave();
          },
        );
      }).toList(),
    );
  }

  void _openCacheBreakpointModeSelector() {
    const options = ['depth', 'stable_prefix'];
    GlazeBottomSheet.show<void>(
      context,
      title: 'label_prompt_cache_breakpoint'.tr(),
      items: options.map((e) {
        final label = _cacheBreakpointModeLabel(e);
        final active = e == _cacheBreakpointMode;
        return BottomSheetItem(
          label: label,
          icon: active ? Icons.check : null,
          iconColor: context.cs.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            setState(() => _cacheBreakpointMode = e);
            _scheduleSave();
          },
        );
      }).toList(),
    );
  }

  void _openSessionIdModeSelector() {
    const options = ['openrouter', 'always', 'off'];
    GlazeBottomSheet.show<void>(
      context,
      title: 'label_session_id_mode'.tr(),
      items: options.map((e) {
        final label = _sessionIdModeLabel(e);
        final active = e == _sessionIdMode;
        return BottomSheetItem(
          label: label,
          icon: active ? Icons.check : null,
          iconColor: context.cs.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            setState(() => _sessionIdMode = e);
            _scheduleSave();
          },
        );
      }).toList(),
    );
  }

  void _openProtocolSelector() {
    GlazeBottomSheet.show<void>(
      context,
      title: 'settings_protocol'.tr(),
      items: LlmProtocol.all.map((p) {
        final label = LlmProtocol.labels[p] ?? p;
        final active = p == _protocol;
        return BottomSheetItem(
          label: label,
          icon: active ? Icons.check : null,
          iconColor: context.cs.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            setState(() {
              _protocol = p;
              _applyProtocolUiPolicy(_protocol);
              _fetchedModels = [];
            });
            _scheduleSave();
          },
        );
      }).toList(),
    );
  }

  Future<void> _fetchModels() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    final endpointRequired = _protocol != LlmProtocol.openrouter;
    if ((endpointRequired && endpoint.isEmpty) || apiKey.isEmpty) {
      GlazeToast.show(context, 'settings_err_endpoint_key'.tr());
      return;
    }
    setState(() => _isLoadingModels = true);
    try {
      final models = await pickChatTransport(
        _protocol,
      ).fetchModels(endpoint: endpoint, apiKey: apiKey);
      if (!mounted) return;
      setState(() {
        _fetchedModels = models;
        _isLoadingModels = false;
      });
      if (models.isEmpty) {
        GlazeToast.show(context, 'settings_err_no_models'.tr());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingModels = false);
        GlazeErrorDialog.show(context, e, prefix: 'settings_err_failed'.tr());
      }
    }
  }

  Future<void> _testLlmConnection() async {
    final endpoint = _endpointCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final endpointRequired = _protocol != LlmProtocol.openrouter;
    // Model is optional here: tapping the status should let the user verify the
    // provider connection even before a model has been picked.
    if ((endpointRequired && endpoint.isEmpty) || apiKey.isEmpty) {
      GlazeToast.show(context, 'settings_err_endpoint_key'.tr());
      return;
    }
    setState(() {
      _llmStatus = ApiConnectionStatus.connecting;
      _llmError = '';
    });
    final result = await ApiConnectionTester().testLlm(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      protocol: _protocol,
    );
    if (!mounted) return;
    switch (result) {
      case ApiTestSuccess(:final message):
        setState(() => _llmStatus = ApiConnectionStatus.connected);
        GlazeToast.show(context, message);
      case ApiTestFailure(:final error):
        setState(() {
          _llmStatus = ApiConnectionStatus.failed;
          _llmError = error.toString();
        });
        GlazeErrorDialog.show(context, error, prefix: 'settings_err_conn_failed'.tr());
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
      GlazeToast.show(context, 'settings_err_fill_endpoint'.tr());
      return;
    }
    setState(() {
      _embStatus = ApiConnectionStatus.connecting;
    });
    final result = await ApiConnectionTester().testEmbedding(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
    );
    if (!mounted) return;
    switch (result) {
      case ApiTestSuccess(:final message):
        setState(() => _embStatus = ApiConnectionStatus.connected);
        GlazeToast.show(context, message);
      case ApiTestFailure(:final error):
        setState(() => _embStatus = ApiConnectionStatus.failed);
        GlazeErrorDialog.show(context, error, prefix: 'settings_err_conn_failed'.tr());
    }
  }
}
