import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/sse_client.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/pipeline_settings.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../settings/api_list_provider.dart';

/// Post-Building menu dialog. Session-bound.
///
/// Hosts all generation-pipeline LLM settings (separated from MemoryBooks):
/// POST-cleaner, agentic write-loop + sidecar, memory generation LLM,
/// classifier, and consolidation LLM. Reads/writes [PipelineSettings] via
/// [pipelineSettingsProvider].
class PostBuildingMenuDialog extends ConsumerStatefulWidget {
  final String charId;
  final String sessionId;

  const PostBuildingMenuDialog({
    super.key,
    required this.charId,
    required this.sessionId,
  });

  @override
  ConsumerState<PostBuildingMenuDialog> createState() =>
      _PostBuildingMenuDialogState();
}

class _PostBuildingMenuDialogState
    extends ConsumerState<PostBuildingMenuDialog> {
  PipelineSettings _pipeline = const PipelineSettings();
  String _memoryMode = 'fast';
  bool _loading = true;

  final Map<String, List<String>> _modelsByApiConfigId = {};
  final Set<String> _fetchingModelConfigIds = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final pipeline = ref.read(pipelineSettingsProvider);
      final book = await ref
          .read(memoryBookRepoProvider)
          .getBySessionId(widget.sessionId);
      final mode = book?.settings.memoryMode ?? 'fast';
      if (mounted) {
        setState(() {
          _pipeline = pipeline;
          _memoryMode = mode;
          // Deep memory mode requires the sidecar. If the user has
          // selected deep mode in Memory Books, force the sidecar
          // toggle ON here so the pipeline doesn't silently degrade to fast.
          if (mode == 'deep' && !_pipeline.sidecarEnabled) {
            _pipeline = _pipeline.copyWith(sidecarEnabled: true);
            ref.read(pipelineSettingsProvider.notifier).save(_pipeline);
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _sidecarLocked => _memoryMode == 'deep';

  Future<void> _savePipeline(
    PipelineSettings Function(PipelineSettings) mutator,
  ) async {
    final updated = mutator(_pipeline);
    await ref.read(pipelineSettingsProvider.notifier).save(updated);
    if (mounted) setState(() => _pipeline = updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        content: SizedBox(
          width: 80,
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cleaning_services_outlined, color: context.cs.primary),
          const SizedBox(width: 8),
          Text('post_building_title'.tr()),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CleanerSection(
                pipeline: _pipeline,
                onSaved: _savePipeline,
                inheritedTimeoutMs: _pipeline.sidecarTimeoutMs,
                modelsByApiConfigId: _modelsByApiConfigId,
                fetchingModelConfigIds: _fetchingModelConfigIds,
                onFetchModels: _fetchProviderModels,
              ),
              const SizedBox(height: 8),
              _WriteLoopSection(
                pipeline: _pipeline,
                onSaved: _savePipeline,
                sidecarLocked: _sidecarLocked,
                memoryMode: _memoryMode,
                modelsByApiConfigId: _modelsByApiConfigId,
                fetchingModelConfigIds: _fetchingModelConfigIds,
                onFetchModels: _fetchProviderModels,
              ),
              const SizedBox(height: 8),
              _PipelineLlmSection(
                titleKey: 'post_building_generation_llm',
                icon: Icons.auto_fix_high_outlined,
                source: _pipeline.generationSource,
                model: _pipeline.generationModel,
                endpoint: _pipeline.generationEndpoint,
                apiKey: _pipeline.generationApiKey,
                temperature: _pipeline.generationTemperature,
                maxTokens: _pipeline.generationMaxTokens,
                modelsByApiConfigId: _modelsByApiConfigId,
                fetchingModelConfigIds: _fetchingModelConfigIds,
                onFetchModels: _fetchProviderModels,
                onSourceChanged: (v) =>
                    _savePipeline((p) => p.copyWith(generationSource: v)),
                onModelChanged: (v) =>
                    _savePipeline((p) => p.copyWith(generationModel: v)),
                onEndpointChanged: (v) =>
                    _savePipeline((p) => p.copyWith(generationEndpoint: v)),
                onApiKeyChanged: (v) =>
                    _savePipeline((p) => p.copyWith(generationApiKey: v)),
                onTemperatureChanged: (v) => _savePipeline(
                  (p) => p.copyWith(generationTemperature: v),
                ),
                onMaxTokensChanged: (v) => _savePipeline(
                  (p) => p.copyWith(generationMaxTokens: v),
                ),
              ),
              const SizedBox(height: 8),
              _ClassifierSection(
                pipeline: _pipeline,
                onSaved: _savePipeline,
                modelsByApiConfigId: _modelsByApiConfigId,
                fetchingModelConfigIds: _fetchingModelConfigIds,
                onFetchModels: _fetchProviderModels,
              ),
              const SizedBox(height: 8),
              _ConsolidationSection(
                pipeline: _pipeline,
                onSaved: _savePipeline,
                modelsByApiConfigId: _modelsByApiConfigId,
                fetchingModelConfigIds: _fetchingModelConfigIds,
                onFetchModels: _fetchProviderModels,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common_close'.tr()),
        ),
      ],
    );
  }

  Future<void> _fetchProviderModels(ApiConfig config) async {
    if (_fetchingModelConfigIds.contains(config.id)) return;
    setState(() => _fetchingModelConfigIds.add(config.id));
    try {
      final models = await SseClient().fetchModels(
        endpoint: config.endpoint,
        apiKey: config.apiKey,
      );
      final ids = models
          .map((m) => m['id'])
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (config.model.isNotEmpty && !ids.contains(config.model)) {
        ids.insert(0, config.model);
      }
      if (!mounted) return;
      setState(() => _modelsByApiConfigId[config.id] = ids);
    } catch (e) {
      if (mounted) {
        GlazeToast.show(context, 'post_building_fetch_models_failed'.tr(namedArgs: {'arg0': '$e'}));
      }
    } finally {
      if (mounted) setState(() => _fetchingModelConfigIds.remove(config.id));
    }
  }
}

/// Common pattern shared by sidecar/classifier/cleaner sources.
typedef PipelineSaver = Future<void> Function(
  PipelineSettings Function(PipelineSettings) mutator,
);

/// Shared state passed to all sections.
typedef FetchModels = Future<void> Function(ApiConfig config);

/// POST-cleaner section: enable, continuity, character audit, model/endpoint/
/// key/source, temperature, max tokens, timeout, history window.
class _CleanerSection extends StatelessWidget {
  final PipelineSettings pipeline;
  final PipelineSaver onSaved;
  final int inheritedTimeoutMs;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final FetchModels onFetchModels;

  const _CleanerSection({
    required this.pipeline,
    required this.onSaved,
    required this.inheritedTimeoutMs,
    required this.modelsByApiConfigId,
    required this.fetchingModelConfigIds,
    required this.onFetchModels,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSource = pipeline.postCleanerSource == 'inherit'
        ? pipeline.sidecarSource
        : pipeline.postCleanerSource;
    return _SectionCard(
      icon: Icons.cleaning_services_outlined,
      titleKey: 'post_building_cleaner_title',
      subtitleKey: 'post_building_cleaner_subtitle',
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('post_building_cleaner_enable'.tr()),
          subtitle: Text('post_building_cleaner_enable_desc'.tr()),
          value: pipeline.postCleanerEnabled,
          onChanged: (v) => onSaved((p) => p.copyWith(postCleanerEnabled: v)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('post_building_cleaner_continuity'.tr()),
          subtitle: Text('post_building_cleaner_continuity_desc'.tr()),
          value: pipeline.postCleanerContinuityEnabled,
          onChanged: (v) => onSaved(
            (p) => p.copyWith(postCleanerContinuityEnabled: v),
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('post_building_cleaner_audit'.tr()),
          subtitle: Text('post_building_cleaner_audit_desc'.tr()),
          value: pipeline.postCleanerCharacterCheckEnabled,
          onChanged: (v) => onSaved(
            (p) => p.copyWith(postCleanerCharacterCheckEnabled: v),
          ),
        ),
        if (pipeline.postCleanerCharacterCheckEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'post_building_cleaner_audit_model_desc'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        if (pipeline.postCleanerCharacterCheckEnabled)
          _AuditModelRow(
            pipeline: pipeline,
            modelsByApiConfigId: modelsByApiConfigId,
            fetchingModelConfigIds: fetchingModelConfigIds,
            onFetchModels: onFetchModels,
            onModelChanged: (v) =>
                onSaved((p) => p.copyWith(postCleanerAuditModel: v)),
          ),
        _SourceSegment(
          source: pipeline.postCleanerSource,
          includeInherit: true,
          onSourceChanged: (v) =>
              onSaved((p) => p.copyWith(postCleanerSource: v)),
        ),
        if (pipeline.postCleanerSource == 'custom') ...[
          _PipelineModelSelector(
            labelKey: 'post_building_cleaner_model',
            model: pipeline.postCleanerModel,
            onModelChanged: (v) =>
                onSaved((p) => p.copyWith(postCleanerModel: v)),
          ),
          _PipelineEndpointField(
            endpoint: pipeline.postCleanerEndpoint,
            onEndpointChanged: (v) =>
                onSaved((p) => p.copyWith(postCleanerEndpoint: v)),
          ),
          _PipelineApiKeyField(
            apiKey: pipeline.postCleanerApiKey,
            onApiKeyChanged: (v) =>
                onSaved((p) => p.copyWith(postCleanerApiKey: v)),
          ),
        ] else if (effectiveSource == 'current') ...[
          Consumer(
            builder: (ctx, ref, _) {
              final activeApi = ref.read(activeApiConfigProvider);
              return _CurrentApiModelRow(
                labelKey: 'post_building_cleaner_model',
                apiConfig: activeApi,
                modelsByApiConfigId: modelsByApiConfigId,
                fetchingModelConfigIds: fetchingModelConfigIds,
                onFetchModels: onFetchModels,
                selectedModel: pipeline.postCleanerModel,
                fallbackModelLabel: activeApi?.model ?? '',
                onModelChanged: (v) =>
                    onSaved((p) => p.copyWith(postCleanerModel: v)),
              );
            },
          ),
        ],
        _NumberTile(
          label: 'post_building_cleaner_temperature'.tr(),
          valueText: pipeline.postCleanerTemperature.toStringAsFixed(2),
          subtitleKey: 'post_building_cleaner_temperature_desc',
          onTap: (ctx) async {
            await _editDouble(
              ctx: ctx,
              title: 'post_building_cleaner_temperature'.tr(),
              value: pipeline.postCleanerTemperature,
              min: 0,
              max: 2,
              onSaved: (v) =>
                  onSaved((p) => p.copyWith(postCleanerTemperature: v)),
            );
          },
        ),
        _NumberTile(
          label: 'post_building_cleaner_max_tokens'.tr(),
          valueText: pipeline.postCleanerMaxTokens == 0
              ? 'post_building_auto_half_length'.tr()
              : 'post_building_tokens_count'
                  .tr(namedArgs: {'arg0': '${pipeline.postCleanerMaxTokens}'}),
          subtitleKey: 'post_building_cleaner_max_tokens_desc',
          onTap: (ctx) async {
            final v = await _editInt(
              ctx: ctx,
              title: 'post_building_cleaner_max_tokens'.tr(),
              value: pipeline.postCleanerMaxTokens,
            );
            if (v != null) {
              await onSaved((p) => p.copyWith(postCleanerMaxTokens: v));
            }
          },
        ),
        _NumberTile(
          label: 'post_building_cleaner_timeout'.tr(),
          valueText: pipeline.postCleanerTimeoutMs == 0
              ? 'post_building_inherit_seconds'.tr(namedArgs: {
                  'arg0': (inheritedTimeoutMs / 1000).toStringAsFixed(0),
                })
              : 'post_building_seconds_count'.tr(namedArgs: {
                  'arg0': (pipeline.postCleanerTimeoutMs / 1000)
                      .toStringAsFixed(0),
                }),
          subtitleKey: 'post_building_cleaner_timeout_desc',
          onTap: (ctx) async {
            final v = await _editIntSeconds(
              ctx: ctx,
              title: 'post_building_cleaner_timeout'.tr(),
              valueSeconds: (pipeline.postCleanerTimeoutMs / 1000).round(),
            );
            if (v != null) {
              await onSaved((p) => p.copyWith(postCleanerTimeoutMs: v * 1000));
            }
          },
        ),
        _NumberTile(
          label: 'post_building_cleaner_history_messages'.tr(),
          valueText: '${pipeline.postCleanerHistoryMessages}',
          subtitleKey: 'post_building_cleaner_history_messages_desc',
          onTap: (ctx) async {
            final v = await _editInt(
              ctx: ctx,
              title: 'post_building_cleaner_history_messages'.tr(),
              value: pipeline.postCleanerHistoryMessages,
              min: 0,
              max: 100,
            );
            if (v != null) {
              await onSaved(
                (p) => p.copyWith(postCleanerHistoryMessages: v),
              );
            }
          },
        ),
        _NumberTile(
          label: 'post_building_cleaner_max_chars_per_message'.tr(),
          valueText: '${pipeline.postCleanerMaxCharsPerMessage}',
          subtitleKey: 'post_building_cleaner_max_chars_per_message_desc',
          onTap: (ctx) async {
            final v = await _editInt(
              ctx: ctx,
              title: 'post_building_cleaner_max_chars_per_message'.tr(),
              value: pipeline.postCleanerMaxCharsPerMessage,
              min: 100,
              max: 50000,
            );
            if (v != null) {
              await onSaved(
                (p) => p.copyWith(postCleanerMaxCharsPerMessage: v),
              );
            }
          },
        ),
        _StyleOverrideTile(
          label: 'post_building_cleaner_banned_words'.tr(),
          subtitleKey: 'post_building_cleaner_banned_words_desc',
          value: pipeline.postCleanerBannedWords,
          onSaved: (v) =>
              onSaved((p) => p.copyWith(postCleanerBannedWords: v)),
        ),
        _StyleOverrideTile(
          label: 'post_building_cleaner_avoid_instructions'.tr(),
          subtitleKey: 'post_building_cleaner_avoid_instructions_desc',
          value: pipeline.postCleanerAvoidInstructions,
          onSaved: (v) =>
              onSaved((p) => p.copyWith(postCleanerAvoidInstructions: v)),
        ),
        _StyleOverrideTile(
          label: 'post_building_cleaner_style_instructions'.tr(),
          subtitleKey: 'post_building_cleaner_style_instructions_desc',
          value: pipeline.postCleanerStyleInstructions,
          onSaved: (v) =>
              onSaved((p) => p.copyWith(postCleanerStyleInstructions: v)),
        ),
      ],
    );
  }
}

/// Agentic write-loop + sidecar model selector + agent timeout.
class _WriteLoopSection extends StatelessWidget {
  final PipelineSettings pipeline;
  final PipelineSaver onSaved;
  final bool sidecarLocked;
  final String memoryMode;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final FetchModels onFetchModels;

  const _WriteLoopSection({
    required this.pipeline,
    required this.onSaved,
    required this.sidecarLocked,
    required this.memoryMode,
    required this.modelsByApiConfigId,
    required this.fetchingModelConfigIds,
    required this.onFetchModels,
  });

  @override
  Widget build(BuildContext context) {
    final c = Consumer(
      builder: (ctx, ref, _) {
        final activeApi = ref.read(activeApiConfigProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('post_building_write_loop'.tr()),
              subtitle: Text('post_building_write_loop_desc'.tr()),
              value: pipeline.agenticWriteEnabled,
              onChanged: (v) => onSaved(
                (p) => p.copyWith(agenticWriteEnabled: v),
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Flexible(child: Text('post_building_sidecar_enabled'.tr())),
                  if (sidecarLocked) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: context.cs.primary,
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                sidecarLocked
                    ? 'post_building_sidecar_locked'.tr(namedArgs: {
                        'arg0': 'memory_mode_$memoryMode'.tr(),
                      })
                    : 'post_building_sidecar_enabled_desc'.tr(),
              ),
              value: pipeline.sidecarEnabled,
              onChanged: sidecarLocked
                  ? null
                  : (v) => onSaved((p) => p.copyWith(sidecarEnabled: v)),
            ),
            _SourceSegment(
              source: pipeline.sidecarSource,
              onSourceChanged: (v) =>
                  onSaved((p) => p.copyWith(sidecarSource: v)),
            ),
            if (pipeline.sidecarSource == 'custom') ...[
              _PipelineModelSelector(
                labelKey: 'post_building_agent_model',
                model: pipeline.sidecarModel,
                onModelChanged: (v) =>
                    onSaved((p) => p.copyWith(sidecarModel: v)),
              ),
              _PipelineEndpointField(
                endpoint: pipeline.sidecarEndpoint,
                onEndpointChanged: (v) =>
                    onSaved((p) => p.copyWith(sidecarEndpoint: v)),
              ),
              _PipelineApiKeyField(
                apiKey: pipeline.sidecarApiKey,
                onApiKeyChanged: (v) =>
                    onSaved((p) => p.copyWith(sidecarApiKey: v)),
              ),
            ] else if (activeApi != null) ...[
              _CurrentApiModelRow(
                labelKey: 'post_building_agent_model',
                apiConfig: activeApi,
                modelsByApiConfigId: modelsByApiConfigId,
                fetchingModelConfigIds: fetchingModelConfigIds,
                onFetchModels: onFetchModels,
                selectedModel: pipeline.sidecarModel,
                fallbackModelLabel: activeApi.model,
                onModelChanged: (v) =>
                    onSaved((p) => p.copyWith(sidecarModel: v)),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'post_building_no_chat_api'.tr(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            _NumberTile(
              label: 'post_building_agent_timeout'.tr(),
              valueText: 'post_building_seconds_count'.tr(namedArgs: {
                'arg0': (pipeline.sidecarTimeoutMs / 1000)
                    .toStringAsFixed(0),
              }),
              subtitleKey: 'post_building_agent_timeout_desc',
              onTap: (ctx) async {
                final v = await _editIntSeconds(
                  ctx: ctx,
                  title: 'post_building_agent_timeout'.tr(),
                  valueSeconds: (pipeline.sidecarTimeoutMs / 1000).round(),
                  minSeconds: 1,
                );
                if (v != null) {
                  await onSaved((p) => p.copyWith(sidecarTimeoutMs: v * 1000));
                }
              },
            ),
          ],
        );
      },
    );
    return _SectionCard(
      icon: Icons.psychology_outlined,
      titleKey: 'post_building_agentic_advanced',
      subtitleKey: 'post_building_agentic_advanced_desc',
      children: [c],
    );
  }
}

/// Memory generation LLM section.
class _PipelineLlmSection extends StatelessWidget {
  final String titleKey;
  final IconData icon;
  final String source;
  final String model;
  final String endpoint;
  final String apiKey;
  final double? temperature;
  final int? maxTokens;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final FetchModels onFetchModels;
  final Future<void> Function(String) onSourceChanged;
  final Future<void> Function(String) onModelChanged;
  final Future<void> Function(String) onEndpointChanged;
  final Future<void> Function(String) onApiKeyChanged;
  final Future<void> Function(double?) onTemperatureChanged;
  final Future<void> Function(int?) onMaxTokensChanged;

  const _PipelineLlmSection({
    required this.titleKey,
    required this.icon,
    required this.source,
    required this.model,
    required this.endpoint,
    required this.apiKey,
    required this.temperature,
    required this.maxTokens,
    required this.modelsByApiConfigId,
    required this.fetchingModelConfigIds,
    required this.onFetchModels,
    required this.onSourceChanged,
    required this.onModelChanged,
    required this.onEndpointChanged,
    required this.onApiKeyChanged,
    required this.onTemperatureChanged,
    required this.onMaxTokensChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = Consumer(
      builder: (ctx, ref, _) {
        final activeApi = ref.read(activeApiConfigProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SourceSegment(
              source: source,
              onSourceChanged: onSourceChanged,
            ),
            if (source == 'custom') ...[
              _PipelineModelSelector(
                labelKey: 'post_building_model',
                model: model,
                onModelChanged: onModelChanged,
              ),
              _PipelineEndpointField(
                endpoint: endpoint,
                onEndpointChanged: onEndpointChanged,
              ),
              _PipelineApiKeyField(
                apiKey: apiKey,
                onApiKeyChanged: onApiKeyChanged,
              ),
            ] else if (activeApi != null) ...[
              _CurrentApiModelRow(
                labelKey: 'post_building_model',
                apiConfig: activeApi,
                modelsByApiConfigId: modelsByApiConfigId,
                fetchingModelConfigIds: fetchingModelConfigIds,
                onFetchModels: onFetchModels,
                selectedModel: model,
                fallbackModelLabel: activeApi.model,
                onModelChanged: onModelChanged,
              ),
            ],
            _NumberTile(
              label: 'post_building_temperature'.tr(),
              valueText: temperature == null
                  ? 'post_building_default'.tr()
                  : temperature!.toStringAsFixed(2),
              subtitleKey: 'post_building_temperature_desc',
              onTap: (ctx) async {
                final v = await _editNullableDouble(
                  ctx: ctx,
                  title: 'post_building_temperature'.tr(),
                  value: temperature,
                  min: 0,
                  max: 2,
                );
                if (v != null) {
                  await onTemperatureChanged(v);
                }
              },
            ),
            _NumberTile(
              label: 'post_building_max_tokens'.tr(),
              valueText: maxTokens == null
                  ? 'post_building_auto'.tr()
                  : 'post_building_tokens_count'
                      .tr(namedArgs: {'arg0': '$maxTokens'}),
              subtitleKey: 'post_building_max_tokens_desc',
              onTap: (ctx) async {
                final v = await _editNullableInt(
                  ctx: ctx,
                  title: 'post_building_max_tokens'.tr(),
                  value: maxTokens,
                );
                if (v != null) {
                  await onMaxTokensChanged(v);
                }
              },
            ),
          ],
        );
      },
    );
    return _SectionCard(
      icon: icon,
      titleKey: titleKey,
      children: [c],
    );
  }
}

/// Classifier LLM section.
class _ClassifierSection extends StatelessWidget {
  final PipelineSettings pipeline;
  final PipelineSaver onSaved;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final FetchModels onFetchModels;

  const _ClassifierSection({
    required this.pipeline,
    required this.onSaved,
    required this.modelsByApiConfigId,
    required this.fetchingModelConfigIds,
    required this.onFetchModels,
  });

  @override
  Widget build(BuildContext context) {
    final c = Consumer(
      builder: (ctx, ref, _) {
        final activeApi = ref.read(activeApiConfigProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('post_building_classifier_enable'.tr()),
              subtitle: Text('post_building_classifier_enable_desc'.tr()),
              value: pipeline.classifierEnabled,
              onChanged: (v) => onSaved((p) => p.copyWith(classifierEnabled: v)),
            ),
            _SourceSegment(
              source: pipeline.classifierSource,
              onSourceChanged: (v) =>
                  onSaved((p) => p.copyWith(classifierSource: v)),
            ),
            if (pipeline.classifierSource == 'custom') ...[
              _PipelineModelSelector(
                labelKey: 'post_building_classifier_model',
                model: pipeline.classifierModel,
                onModelChanged: (v) =>
                    onSaved((p) => p.copyWith(classifierModel: v)),
              ),
              _PipelineEndpointField(
                endpoint: pipeline.classifierEndpoint,
                onEndpointChanged: (v) =>
                    onSaved((p) => p.copyWith(classifierEndpoint: v)),
              ),
              _PipelineApiKeyField(
                apiKey: pipeline.classifierApiKey,
                onApiKeyChanged: (v) =>
                    onSaved((p) => p.copyWith(classifierApiKey: v)),
              ),
            ] else if (activeApi != null) ...[
              _CurrentApiModelRow(
                labelKey: 'post_building_classifier_model',
                apiConfig: activeApi,
                modelsByApiConfigId: modelsByApiConfigId,
                fetchingModelConfigIds: fetchingModelConfigIds,
                onFetchModels: onFetchModels,
                selectedModel: pipeline.classifierModel,
                fallbackModelLabel: activeApi.model,
                onModelChanged: (v) =>
                    onSaved((p) => p.copyWith(classifierModel: v)),
              ),
            ],
            _NumberTile(
              label: 'post_building_classifier_timeout'.tr(),
              valueText: 'post_building_ms_count'.tr(namedArgs: {
                'arg0': '${pipeline.classifierTimeoutMs}',
              }),
              subtitleKey: 'post_building_classifier_timeout_desc',
              onTap: (ctx) async {
                final v = await _editInt(
                  ctx: ctx,
                  title: 'post_building_classifier_timeout'.tr(),
                  value: pipeline.classifierTimeoutMs,
                  min: 500,
                  max: 10000,
                  step: 500,
                );
                if (v != null) {
                  await onSaved((p) => p.copyWith(classifierTimeoutMs: v));
                }
              },
            ),
          ],
        );
      },
    );
    return _SectionCard(
      icon: Icons.category_outlined,
      titleKey: 'post_building_classifier_llm',
      children: [c],
    );
  }
}

/// Consolidation LLM section.
class _ConsolidationSection extends StatelessWidget {
  final PipelineSettings pipeline;
  final PipelineSaver onSaved;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final FetchModels onFetchModels;

  const _ConsolidationSection({
    required this.pipeline,
    required this.onSaved,
    required this.modelsByApiConfigId,
    required this.fetchingModelConfigIds,
    required this.onFetchModels,
  });

  @override
  Widget build(BuildContext context) {
    final c = Consumer(
      builder: (ctx, ref, _) {
        final activeApi = ref.read(activeApiConfigProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: context.cs.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: context.cs.onErrorContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'post_building_consolidation_not_functional'.tr(),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('post_building_consolidation_enable'.tr()),
              subtitle: Text('post_building_consolidation_enable_desc'.tr()),
              value: pipeline.consolidationEnabled,
              onChanged: (v) =>
                  onSaved((p) => p.copyWith(consolidationEnabled: v)),
            ),
            _NumberTile(
              label: 'post_building_consolidation_threshold'.tr(),
              valueText: 'post_building_entries_count'.tr(namedArgs: {
                'arg0': '${pipeline.consolidationThreshold}',
              }),
              subtitleKey: 'post_building_consolidation_threshold_desc',
              onTap: (ctx) async {
                final v = await _editInt(
                  ctx: ctx,
                  title: 'post_building_consolidation_threshold'.tr(),
                  value: pipeline.consolidationThreshold,
                  min: 1,
                  max: 100,
                );
                if (v != null) {
                  await onSaved((p) => p.copyWith(consolidationThreshold: v));
                }
              },
            ),
            _SourceSegment(
              source: pipeline.consolidationSource,
              onSourceChanged: (v) =>
                  onSaved((p) => p.copyWith(consolidationSource: v)),
            ),
            if (pipeline.consolidationSource == 'custom') ...[
              _PipelineModelSelector(
                labelKey: 'post_building_consolidation_model',
                model: pipeline.consolidationModel,
                onModelChanged: (v) =>
                    onSaved((p) => p.copyWith(consolidationModel: v)),
              ),
              _PipelineEndpointField(
                endpoint: pipeline.consolidationEndpoint,
                onEndpointChanged: (v) =>
                    onSaved((p) => p.copyWith(consolidationEndpoint: v)),
              ),
              _PipelineApiKeyField(
                apiKey: pipeline.consolidationApiKey,
                onApiKeyChanged: (v) =>
                    onSaved((p) => p.copyWith(consolidationApiKey: v)),
              ),
            ] else if (activeApi != null) ...[
              _CurrentApiModelRow(
                labelKey: 'post_building_consolidation_model',
                apiConfig: activeApi,
                modelsByApiConfigId: modelsByApiConfigId,
                fetchingModelConfigIds: fetchingModelConfigIds,
                onFetchModels: onFetchModels,
                selectedModel: pipeline.consolidationModel,
                fallbackModelLabel: activeApi.model,
                onModelChanged: (v) =>
                    onSaved((p) => p.copyWith(consolidationModel: v)),
              ),
            ],
            _NumberTile(
              label: 'post_building_consolidation_timeout'.tr(),
              valueText: 'post_building_ms_count'.tr(namedArgs: {
                'arg0': '${pipeline.consolidationTimeoutMs}',
              }),
              subtitleKey: 'post_building_consolidation_timeout_desc',
              onTap: (ctx) async {
                final v = await _editInt(
                  ctx: ctx,
                  title: 'post_building_consolidation_timeout'.tr(),
                  value: pipeline.consolidationTimeoutMs,
                  min: 1000,
                  max: 60000,
                  step: 1000,
                );
                if (v != null) {
                  await onSaved((p) => p.copyWith(consolidationTimeoutMs: v));
                }
              },
            ),
          ],
        );
      },
    );
    return _SectionCard(
      icon: Icons.merge_outlined,
      titleKey: 'post_building_consolidation_llm',
      children: [c],
    );
  }
}

/// A bordered card that hosts a section header + children list.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String titleKey;
  final String? subtitleKey;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.titleKey,
    this.subtitleKey,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: context.cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleKey.tr(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.cs.onSurface,
                        ),
                      ),
                      if (subtitleKey != null)
                        Text(
                          subtitleKey!.tr(),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Source segmented button: 'inherit' (cleaner only), 'current', 'custom'.
class _SourceSegment extends StatelessWidget {
  final String source;
  final bool includeInherit;
  final Future<void> Function(String) onSourceChanged;

  const _SourceSegment({
    required this.source,
    required this.onSourceChanged,
    this.includeInherit = false,
  });

  @override
  Widget build(BuildContext context) {
    final segments = <ButtonSegment<String>>[
      if (includeInherit)
        ButtonSegment(
          value: 'inherit',
          label: Text('post_building_source_inherit'.tr()),
        ),
      ButtonSegment(
        value: 'current',
        label: Text('post_building_source_current'.tr()),
      ),
      ButtonSegment(
        value: 'custom',
        label: Text('post_building_source_custom'.tr()),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SegmentedButton<String>(
        segments: segments,
        selected: {source},
        onSelectionChanged: (s) => onSourceChanged(s.first),
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }
}

/// Custom-model text field used inside pipeline LLM sections.
class _PipelineModelSelector extends StatelessWidget {
  final String labelKey;
  final String model;
  final Future<void> Function(String) onModelChanged;

  const _PipelineModelSelector({
    required this.labelKey,
    required this.model,
    required this.onModelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextField(
        controller: TextEditingController(text: model),
        decoration: InputDecoration(
          labelText: labelKey.tr(),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: onModelChanged,
      ),
    );
  }
}

class _PipelineEndpointField extends StatelessWidget {
  final String endpoint;
  final Future<void> Function(String) onEndpointChanged;

  const _PipelineEndpointField({
    required this.endpoint,
    required this.onEndpointChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextField(
        controller: TextEditingController(text: endpoint),
        decoration: InputDecoration(
          labelText: 'post_building_endpoint'.tr(),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: onEndpointChanged,
      ),
    );
  }
}

class _PipelineApiKeyField extends StatelessWidget {
  final String apiKey;
  final Future<void> Function(String) onApiKeyChanged;

  const _PipelineApiKeyField({
    required this.apiKey,
    required this.onApiKeyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextField(
        controller: TextEditingController(text: apiKey),
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'post_building_api_key'.tr(),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: onApiKeyChanged,
      ),
    );
  }
}

/// Shared "current API" model dropdown + refresh button.
///
/// Used by every pipeline section (cleaner, sidecar, generation, classifier,
/// consolidation) when source='current'. Shows models fetched from the
/// active API config endpoint, plus a refresh button to fetch the list.
class _CurrentApiModelRow extends StatelessWidget {
  final String labelKey;
  final ApiConfig? apiConfig;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final FetchModels onFetchModels;
  final String selectedModel;
  final String fallbackModelLabel;
  final Future<void> Function(String) onModelChanged;

  const _CurrentApiModelRow({
    required this.labelKey,
    required this.apiConfig,
    required this.modelsByApiConfigId,
    required this.fetchingModelConfigIds,
    required this.onFetchModels,
    required this.selectedModel,
    required this.fallbackModelLabel,
    required this.onModelChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (apiConfig == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'post_building_no_chat_api'.tr(),
          style: const TextStyle(fontSize: 12),
        ),
      );
    }
    final config = apiConfig!;
    final fetched = modelsByApiConfigId[config.id] ?? const <String>[];
    final models = <String>{
      ...fetched,
      if (selectedModel.isNotEmpty && !fetched.contains(selectedModel))
        selectedModel,
    }.toList()
      ..sort();
    final selected = selectedModel.isEmpty ? '' : selectedModel;
    final isFetching = fetchingModelConfigIds.contains(config.id);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: models.contains(selected) || selected.isEmpty
                  ? selected
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: labelKey.tr(),
                helperText: fallbackModelLabel.isNotEmpty
                    ? 'post_building_empty_chat_model'.tr(namedArgs: {
                        'arg0': fallbackModelLabel,
                      })
                    : 'post_building_empty_chat_model_plain'.tr(),
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text('post_building_use_chat_model'.tr()),
                ),
                ...models.map(
                  (m) => DropdownMenuItem<String>(
                    value: m,
                    child: Text(m, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (m) => onModelChanged(m ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: IconButton.filledTonal(
              tooltip: 'post_building_fetch_models'.tr(),
              onPressed: isFetching ? null : () => onFetchModels(config),
              icon: isFetching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Audit model dropdown (Fix 2 — UI part 2). Shows models fetched from the
/// same API config the cleaner resolves to (current chat API for
/// source=current/inherit, custom endpoint for source=custom), so the audit
/// can pick a different model without re-entering endpoint/key. The first
/// item is "Use cleaner model" (value='' → [resolveConfigForAudit] falls
/// back to the cleaner-resolved model).
///
/// Models are cached in [modelsByApiConfigId] under a synthetic id derived
/// from the resolved endpoint, so the audit fetch never collides with the
/// cleaner fetch (and vice versa) even when they share the same endpoint.
class _AuditModelRow extends ConsumerWidget {
  final PipelineSettings pipeline;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final FetchModels onFetchModels;
  final Future<void> Function(String) onModelChanged;

  const _AuditModelRow({
    required this.pipeline,
    required this.modelsByApiConfigId,
    required this.fetchingModelConfigIds,
    required this.onFetchModels,
    required this.onModelChanged,
  });

  /// Builds the synthetic [ApiConfig] the audit resolves to (mirrors
  /// [SidecarLlmClient.resolveConfigForAudit] → [resolveConfigForCleaner]).
  /// Returns null when the resolved endpoint is empty (cleaner custom config
  /// incomplete) so the row can show an inline hint instead of an empty
  /// dropdown.
  ApiConfig? _resolveAuditConfig(ApiConfig? activeApi) {
    final source = pipeline.postCleanerSource == 'inherit'
        ? pipeline.sidecarSource
        : pipeline.postCleanerSource;
    final endpoint = pipeline.postCleanerEndpoint.isNotEmpty
        ? pipeline.postCleanerEndpoint
        : pipeline.sidecarEndpoint;
    final apiKey = pipeline.postCleanerApiKey.isNotEmpty
        ? pipeline.postCleanerApiKey
        : pipeline.sidecarApiKey;
    final fallbackModel = pipeline.postCleanerModel.isNotEmpty
        ? pipeline.postCleanerModel
        : pipeline.sidecarModel;

    if (source == 'custom') {
      if (endpoint.isEmpty) return null;
      return ApiConfig(
        id: 'audit-custom:$endpoint',
        name: 'Audit (custom)',
        endpoint: endpoint,
        apiKey: apiKey,
        model: fallbackModel,
        protocol: 'openai',
      );
    }
    // source == 'current' (or unknown) — audit uses the active chat API.
    if (activeApi == null) return null;
    return ApiConfig(
      id: 'audit-current:${activeApi.id}',
      name: 'Audit (current)',
      endpoint: activeApi.endpoint,
      apiKey: activeApi.apiKey,
      model: fallbackModel.isNotEmpty ? fallbackModel : activeApi.model,
      protocol: activeApi.protocol,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeApi = ref.read(activeApiConfigProvider);
    final config = _resolveAuditConfig(activeApi);
    if (config == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'post_building_cleaner_audit_model_no_endpoint'.tr(),
          style: const TextStyle(fontSize: 12),
        ),
      );
    }

    final fetched = modelsByApiConfigId[config.id] ?? const <String>[];
    final models = <String>{
      ...fetched,
      if (pipeline.postCleanerAuditModel.isNotEmpty &&
          !fetched.contains(pipeline.postCleanerAuditModel))
        pipeline.postCleanerAuditModel,
    }.toList()
      ..sort();
    final selected = pipeline.postCleanerAuditModel.isEmpty
        ? ''
        : pipeline.postCleanerAuditModel;
    final isFetching = fetchingModelConfigIds.contains(config.id);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: models.contains(selected) || selected.isEmpty
                  ? selected
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'post_building_cleaner_audit_model'.tr(),
                helperText: selected.isEmpty
                    ? 'post_building_cleaner_audit_model_helper'.tr(namedArgs: {
                        'arg0': config.model,
                      })
                    : null,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(
                    'post_building_cleaner_audit_use_cleaner_model'.tr(),
                  ),
                ),
                ...models.map(
                  (m) => DropdownMenuItem<String>(
                    value: m,
                    child: Text(m, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (m) => onModelChanged(m ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: IconButton.filledTonal(
              tooltip: 'post_building_fetch_models'.tr(),
              onPressed: isFetching ? null : () => onFetchModels(config),
              icon: isFetching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ListTile whose trailing tap opens an editor dialog.
class _NumberTile extends StatelessWidget {
  final String label;
  final String valueText;
  final String subtitleKey;
  final Future<void> Function(BuildContext) onTap;

  const _NumberTile({
    required this.label,
    required this.valueText,
    required this.subtitleKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text('$valueText — ${subtitleKey.tr()}'),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () => onTap(context),
    );
  }
}

Future<double> _editDouble({
  required BuildContext ctx,
  required String title,
  required double value,
  required double min,
  required double max,
  required Future<void> Function(double) onSaved,
}) async {
  final controller = TextEditingController(text: value.toStringAsFixed(2));
  final result = await showDialog<double>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'post_building_range'.tr(namedArgs: {
              'arg0': '$min',
              'arg1': '$max',
            }),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text('common_cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(controller.text.trim());
            if (v == null || v < min || v > max) {
              Navigator.of(c).pop();
              return;
            }
            Navigator.of(c).pop(v);
          },
          child: Text('common_save'.tr()),
        ),
      ],
    ),
  );
  if (result == null) return value;
  await onSaved(result);
  return result;
}

Future<int?> _editInt({
  required BuildContext ctx,
  required String title,
  required int value,
  int min = 0,
  int max = 999999,
  int step = 1,
}) async {
  final controller = TextEditingController(text: '$value');
  final result = await showDialog<int>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (step > 1)
            Text(
              'post_building_step'.tr(namedArgs: {'arg0': '$step'}),
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text('common_cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < min || v > max) {
              Navigator.of(c).pop();
              return;
            }
            Navigator.of(c).pop(v);
          },
          child: Text('common_save'.tr()),
        ),
      ],
    ),
  );
  return result;
}

Future<int?> _editIntSeconds({
  required BuildContext ctx,
  required String title,
  required int valueSeconds,
  int minSeconds = 0,
}) async {
  final controller =
      TextEditingController(text: '$valueSeconds');
  final result = await showDialog<int>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'post_building_seconds_min'.tr(namedArgs: {'arg0': '$minSeconds'}),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              suffixText: 'post_building_seconds_suffix'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text('common_cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            final s = int.tryParse(controller.text.trim());
            if (s == null || s < minSeconds) {
              Navigator.of(c).pop();
              return;
            }
            Navigator.of(c).pop(s);
          },
          child: Text('common_save'.tr()),
        ),
      ],
    ),
  );
  return result;
}

Future<double?> _editNullableDouble({
  required BuildContext ctx,
  required String title,
  required double? value,
  required double min,
  required double max,
}) async {
  final controller = TextEditingController(
    text: value == null ? '' : value.toStringAsFixed(2),
  );
  final result = await showDialog<double?>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'post_building_blank_default_range'.tr(namedArgs: {
              'arg0': '$min',
              'arg1': '$max',
            }),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(null),
          child: Text('common_clear'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text('common_cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            final raw = controller.text.trim();
            if (raw.isEmpty) {
              Navigator.of(c).pop(null);
              return;
            }
            final v = double.tryParse(raw);
            if (v == null || v < min || v > max) {
              Navigator.of(c).pop();
              return;
            }
            Navigator.of(c).pop(v);
          },
          child: Text('common_save'.tr()),
        ),
      ],
    ),
  );
  return result;
}

Future<int?> _editNullableInt({
  required BuildContext ctx,
  required String title,
  required int? value,
}) async {
  final controller = TextEditingController(text: value == null ? '' : '$value');
  final result = await showDialog<int?>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'post_building_blank_default'.tr(),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(null),
          child: Text('common_clear'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text('common_cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            final raw = controller.text.trim();
            if (raw.isEmpty) {
              Navigator.of(c).pop(null);
              return;
            }
            final v = int.tryParse(raw);
            if (v == null) {
              Navigator.of(c).pop();
              return;
            }
            Navigator.of(c).pop(v);
          },
          child: Text('common_save'.tr()),
        ),
      ],
    ),
  );
  return result;
}

/// A `_NumberTile`-like row for multiline text style overrides (banned
/// words, avoid/prefer instructions). Tapping opens a full-screen multiline
/// editor. Empty values display a placeholder so the tile is still tappable.
class _StyleOverrideTile extends StatelessWidget {
  final String label;
  final String subtitleKey;
  final String value;
  final Future<void> Function(String) onSaved;

  const _StyleOverrideTile({
    required this.label,
    required this.subtitleKey,
    required this.value,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        hasValue
            ? (value.length > 80 ? '${value.substring(0, 80)}…' : value)
            : subtitleKey.tr(),
        style: TextStyle(
          fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
        ),
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () async {
        final result = await _editMultiline(
          ctx: context,
          title: label,
          value: value,
        );
        if (result != null && result != value) {
          await onSaved(result);
        }
      },
    );
  }
}

Future<String?> _editMultiline({
  required BuildContext ctx,
  required String title,
  required String value,
}) async {
  final controller = TextEditingController(text: value);
  final result = await showDialog<String?>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          minLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: Text('common_cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(controller.text),
          child: Text('common_save'.tr()),
        ),
      ],
    ),
  );
  return result;
}
