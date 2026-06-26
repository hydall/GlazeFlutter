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
      final pipeline = await ref
          .read(pipelineSettingsProvider(widget.sessionId).future);
      if (mounted) {
        setState(() {
          _pipeline = pipeline;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePipeline(
    PipelineSettings Function(PipelineSettings) mutator,
  ) async {
    final repo = ref.read(pipelineSettingsRepoProvider);
    final updated = mutator(_pipeline);
    await repo.updateSettings(widget.sessionId, updated);
    ref.invalidate(pipelineSettingsProvider(widget.sessionId));
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
          const Text('Post-Building'),
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
              ),
              const SizedBox(height: 8),
              _WriteLoopSection(
                pipeline: _pipeline,
                onSaved: _savePipeline,
                modelsByApiConfigId: _modelsByApiConfigId,
                fetchingModelConfigIds: _fetchingModelConfigIds,
                onFetchModels: _fetchProviderModels,
              ),
              const SizedBox(height: 8),
              _PipelineLlmSection(
                title: 'Memory generation LLM',
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
          child: const Text('Close'),
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
        GlazeToast.show(context, 'Fetch models failed: $e');
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

/// POST-cleaner section: enable, continuity, character audit, model/endpoint/
/// key/source, temperature, max tokens, timeout, history window.
class _CleanerSection extends StatelessWidget {
  final PipelineSettings pipeline;
  final PipelineSaver onSaved;
  final int inheritedTimeoutMs;

  const _CleanerSection({
    required this.pipeline,
    required this.onSaved,
    required this.inheritedTimeoutMs,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.cleaning_services_outlined,
      title: 'POST-cleaner (anti-cliche rewrite)',
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable POST-cleaner'),
          subtitle: const Text(
            'After generation, silently rewrites the response to remove '
            'cliches and repetition. Original preserved as a swipe.',
          ),
          value: pipeline.postCleanerEnabled,
          onChanged: (v) => onSaved((p) => p.copyWith(postCleanerEnabled: v)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Continuity check (recent history)'),
          subtitle: const Text(
            'Includes recent chat history in the cleaner prompt for local '
            'continuity checks: who said what, positions, clothing, recent '
            'actions. No extra LLM call.',
          ),
          value: pipeline.postCleanerContinuityEnabled,
          onChanged: (v) => onSaved(
            (p) => p.copyWith(postCleanerContinuityEnabled: v),
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Character & world audit (extra sidecar call)'),
          subtitle: const Text(
            'Opt-in. A diagnostic sidecar pass checks the response against '
            'character card, persona, lorebooks, and memory. Returns '
            'contradictions that the cleaner then fixes.',
          ),
          value: pipeline.postCleanerCharacterCheckEnabled,
          onChanged: (v) => onSaved(
            (p) => p.copyWith(postCleanerCharacterCheckEnabled: v),
          ),
        ),
        _SourceSegment(
          source: pipeline.postCleanerSource,
          includeInherit: true,
          onSourceChanged: (v) =>
              onSaved((p) => p.copyWith(postCleanerSource: v)),
        ),
        if (pipeline.postCleanerSource == 'custom') ...[
          _PipelineModelSelector(
            label: 'Cleaner model',
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
        ],
        _NumberTile(
          label: 'Cleaner temperature',
          valueText: pipeline.postCleanerTemperature.toStringAsFixed(2),
          subtitle:
              'Lower = more faithful rewrite, higher = more creative. '
              '0.3 default.',
          onTap: (ctx) async {
            await _editDouble(
              ctx: ctx,
              title: 'Cleaner temperature',
              value: pipeline.postCleanerTemperature,
              min: 0,
              max: 2,
              onSaved: (v) =>
                  onSaved((p) => p.copyWith(postCleanerTemperature: v)),
            );
          },
        ),
        _NumberTile(
          label: 'Cleaner max tokens',
          valueText: pipeline.postCleanerMaxTokens == 0
              ? 'Auto (half original length)'
              : '${pipeline.postCleanerMaxTokens} tokens',
          subtitle: '0 = auto (half the original text length).',
          onTap: (ctx) async {
            final v = await _editInt(
              ctx: ctx,
              title: 'Cleaner max tokens',
              value: pipeline.postCleanerMaxTokens,
            );
            if (v != null) {
              await onSaved((p) => p.copyWith(postCleanerMaxTokens: v));
            }
          },
        ),
        _NumberTile(
          label: 'Cleaner timeout',
          valueText: pipeline.postCleanerTimeoutMs == 0
              ? 'Inherit (${(inheritedTimeoutMs / 1000).toStringAsFixed(0)}s)'
              : '${(pipeline.postCleanerTimeoutMs / 1000).toStringAsFixed(0)}s',
          subtitle: '0 = inherit from write-loop sidecar timeout.',
          onTap: (ctx) async {
            final v = await _editIntSeconds(
              ctx: ctx,
              title: 'Cleaner timeout',
              valueSeconds: (pipeline.postCleanerTimeoutMs / 1000).round(),
            );
            if (v != null) {
              await onSaved((p) => p.copyWith(postCleanerTimeoutMs: v * 1000));
            }
          },
        ),
        _NumberTile(
          label: 'History messages',
          valueText: '${pipeline.postCleanerHistoryMessages}',
          subtitle:
              'Number of recent messages included for continuity checks.',
          onTap: (ctx) async {
            final v = await _editInt(
              ctx: ctx,
              title: 'History messages',
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
          label: 'Max chars per message',
          valueText: '${pipeline.postCleanerMaxCharsPerMessage}',
          subtitle:
              'Each history message is trimmed to this many characters.',
          onTap: (ctx) async {
            final v = await _editInt(
              ctx: ctx,
              title: 'Max chars per message',
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
      ],
    );
  }
}

/// Agentic write-loop + sidecar model selector + agent timeout.
class _WriteLoopSection extends StatelessWidget {
  final PipelineSettings pipeline;
  final PipelineSaver onSaved;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final Future<void> Function(ApiConfig) onFetchModels;

  const _WriteLoopSection({
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
        final config = pipeline.sidecarSource == 'custom' ? null : activeApi;
        final fetched = config == null
            ? const <String>[]
            : modelsByApiConfigId[config.id] ?? const <String>[];
        final models = <String>{
          ...fetched,
          if (pipeline.sidecarModel.isNotEmpty &&
              !fetched.contains(pipeline.sidecarModel))
            pipeline.sidecarModel,
        }.toList()
          ..sort();
        final selected = pipeline.sidecarModel.isEmpty
            ? ''
            : pipeline.sidecarModel;
        final isFetching = config == null
            ? false
            : fetchingModelConfigIds.contains(config.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Write-loop (trackers + memory drafts)'),
              subtitle: const Text(
                'After each accepted turn, the memory agent writes lightweight '
                'trackers and pending memory drafts.',
              ),
              value: pipeline.agenticWriteEnabled,
              onChanged: (v) => onSaved(
                (p) => p.copyWith(agenticWriteEnabled: v),
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Sidecar enabled'),
              subtitle: const Text(
                'Enables the sidecar LLM used by the write-loop, reranker, and '
                'cleaner (when not custom).',
              ),
              value: pipeline.sidecarEnabled,
              onChanged: (v) => onSaved((p) => p.copyWith(sidecarEnabled: v)),
            ),
            _SourceSegment(
              source: pipeline.sidecarSource,
              onSourceChanged: (v) =>
                  onSaved((p) => p.copyWith(sidecarSource: v)),
            ),
            if (pipeline.sidecarSource == 'custom') ...[
              _PipelineModelSelector(
                label: 'Agent model (sidecar)',
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
            ] else if (config != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: models.contains(selected) || selected.isEmpty
                          ? selected
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Agent model (sidecar)',
                        helperText: 'Empty = use chat model. A cheaper/faster '
                            'model is recommended for trackers + cleaner.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('(use chat model)'),
                        ),
                        ...models.map(
                          (m) => DropdownMenuItem<String>(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (m) =>
                          onSaved((p) => p.copyWith(sidecarModel: m ?? '')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IconButton.filledTonal(
                      tooltip: 'Fetch models',
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
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No chat API config available for the agent.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            _NumberTile(
              label: 'Agent timeout',
              valueText:
                  '${(pipeline.sidecarTimeoutMs / 1000).toStringAsFixed(0)}s',
              subtitle:
                  'How long to wait for the sidecar agent before giving up.',
              onTap: (ctx) async {
                final v = await _editIntSeconds(
                  ctx: ctx,
                  title: 'Agent timeout',
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
      title: 'Agentic memory (advanced)',
      subtitle: 'Memory agent writes trackers + drafts.',
      children: [c],
    );
  }
}

/// Memory generation LLM section.
class _PipelineLlmSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String source;
  final String model;
  final String endpoint;
  final String apiKey;
  final double? temperature;
  final int? maxTokens;
  final Map<String, List<String>> modelsByApiConfigId;
  final Set<String> fetchingModelConfigIds;
  final Future<void> Function(ApiConfig) onFetchModels;
  final Future<void> Function(String) onSourceChanged;
  final Future<void> Function(String) onModelChanged;
  final Future<void> Function(String) onEndpointChanged;
  final Future<void> Function(String) onApiKeyChanged;
  final Future<void> Function(double?) onTemperatureChanged;
  final Future<void> Function(int?) onMaxTokensChanged;

  const _PipelineLlmSection({
    required this.title,
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
        final config = source == 'custom' ? null : activeApi;
        final fetched = config == null
            ? const <String>[]
            : modelsByApiConfigId[config.id] ?? const <String>[];
        final models = <String>{
          ...fetched,
          if (model.isNotEmpty && !fetched.contains(model)) model,
        }.toList()
          ..sort();
        final selected = model.isEmpty ? '' : model;
        final isFetching = config == null
            ? false
            : fetchingModelConfigIds.contains(config.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SourceSegment(
              source: source,
              onSourceChanged: onSourceChanged,
            ),
            if (source == 'custom') ...[
              _PipelineModelSelector(
                label: 'Model',
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
            ] else if (config != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: models.contains(selected) || selected.isEmpty
                          ? selected
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Model',
                        helperText: 'Empty = use chat model (${config.model}).',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('(use chat model)'),
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
                      tooltip: 'Fetch models',
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
            ],
            _NumberTile(
              label: 'Temperature',
              valueText: temperature == null
                  ? 'Default'
                  : temperature!.toStringAsFixed(2),
              subtitle: 'Optional. Blank = provider default.',
              onTap: (ctx) async {
                final v = await _editNullableDouble(
                  ctx: ctx,
                  title: 'Temperature',
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
              label: 'Max tokens',
              valueText: maxTokens == null
                  ? 'Auto'
                  : '$maxTokens tokens',
              subtitle: 'Optional. Blank = provider default.',
              onTap: (ctx) async {
                final v = await _editNullableInt(
                  ctx: ctx,
                  title: 'Max tokens',
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
      title: title,
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
  final Future<void> Function(ApiConfig) onFetchModels;

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
        final config = pipeline.classifierSource == 'custom' ? null : activeApi;
        final fetched = config == null
            ? const <String>[]
            : modelsByApiConfigId[config.id] ?? const <String>[];
        final models = <String>{
          ...fetched,
          if (pipeline.classifierModel.isNotEmpty &&
              !fetched.contains(pipeline.classifierModel))
            pipeline.classifierModel,
        }.toList()
          ..sort();
        final selected = pipeline.classifierModel.isEmpty
            ? ''
            : pipeline.classifierModel;
        final isFetching = config == null
            ? false
            : fetchingModelConfigIds.contains(config.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable classifier'),
              subtitle: const Text(
                'A sidecar LLM that classifies memory importance before '
                'injection. Off = plain key match only.',
              ),
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
                label: 'Classifier model',
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
            ] else if (config != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: models.contains(selected) || selected.isEmpty
                          ? selected
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Classifier model',
                        helperText: 'Empty = use chat model (${config.model}).',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('(use chat model)'),
                        ),
                        ...models.map(
                          (m) => DropdownMenuItem<String>(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (m) =>
                          onSaved((p) => p.copyWith(classifierModel: m ?? '')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IconButton.filledTonal(
                      tooltip: 'Fetch models',
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
            ],
            _NumberTile(
              label: 'Classifier timeout (ms)',
              valueText: '${pipeline.classifierTimeoutMs}',
              subtitle: '500–10000ms, step 500.',
              onTap: (ctx) async {
                final v = await _editInt(
                  ctx: ctx,
                  title: 'Classifier timeout (ms)',
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
      title: 'Classifier LLM',
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
  final Future<void> Function(ApiConfig) onFetchModels;

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
        final config = pipeline.consolidationSource == 'custom' ? null : activeApi;
        final fetched = config == null
            ? const <String>[]
            : modelsByApiConfigId[config.id] ?? const <String>[];
        final models = <String>{
          ...fetched,
          if (pipeline.consolidationModel.isNotEmpty &&
              !fetched.contains(pipeline.consolidationModel))
            pipeline.consolidationModel,
        }.toList()
          ..sort();
        final selected = pipeline.consolidationModel.isEmpty
            ? ''
            : pipeline.consolidationModel;
        final isFetching = config == null
            ? false
            : fetchingModelConfigIds.contains(config.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable consolidation'),
              subtitle: const Text(
                'Periodically merges memory entries past a threshold via a '
                'sidecar LLM.',
              ),
              value: pipeline.consolidationEnabled,
              onChanged: (v) =>
                  onSaved((p) => p.copyWith(consolidationEnabled: v)),
            ),
            _NumberTile(
              label: 'Consolidation threshold',
              valueText: '${pipeline.consolidationThreshold} entries',
              subtitle: 'Merge when entries exceed this count.',
              onTap: (ctx) async {
                final v = await _editInt(
                  ctx: ctx,
                  title: 'Consolidation threshold',
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
                label: 'Consolidation model',
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
            ] else if (config != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: models.contains(selected) || selected.isEmpty
                          ? selected
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Consolidation model',
                        helperText: 'Empty = use chat model (${config.model}).',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('(use chat model)'),
                        ),
                        ...models.map(
                          (m) => DropdownMenuItem<String>(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (m) => onSaved(
                        (p) => p.copyWith(consolidationModel: m ?? ''),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IconButton.filledTonal(
                      tooltip: 'Fetch models',
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
            ],
            _NumberTile(
              label: 'Consolidation timeout (ms)',
              valueText: '${pipeline.consolidationTimeoutMs}',
              subtitle: 'How long to wait for the consolidation LLM.',
              onTap: (ctx) async {
                final v = await _editInt(
                  ctx: ctx,
                  title: 'Consolidation timeout (ms)',
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
      title: 'Consolidation LLM',
      children: [c],
    );
  }
}

/// A bordered card that hosts a section header + children list.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
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
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.cs.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
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
        const ButtonSegment(value: 'inherit', label: Text('Inherit')),
      const ButtonSegment(value: 'current', label: Text('Current API')),
      const ButtonSegment(value: 'custom', label: Text('Custom')),
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
  final String label;
  final String model;
  final Future<void> Function(String) onModelChanged;

  const _PipelineModelSelector({
    required this.label,
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
          labelText: label,
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
        decoration: const InputDecoration(
          labelText: 'Endpoint',
          border: OutlineInputBorder(),
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
        decoration: const InputDecoration(
          labelText: 'API key',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: onApiKeyChanged,
      ),
    );
  }
}

/// A ListTile whose trailing tap opens an editor dialog.
class _NumberTile extends StatelessWidget {
  final String label;
  final String valueText;
  final String subtitle;
  final Future<void> Function(BuildContext) onTap;

  const _NumberTile({
    required this.label,
    required this.valueText,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text('$valueText — $subtitle'),
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
            'Range: $min–$max.',
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
          child: const Text('Cancel'),
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
          child: const Text('Save'),
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
            Text('Step: $step.', style: const TextStyle(fontSize: 12)),
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
          child: const Text('Cancel'),
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
          child: const Text('Save'),
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
            'Seconds to wait. Min: $minSeconds.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              suffixText: 'seconds',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('Cancel'),
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
          child: const Text('Save'),
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
            'Blank = provider default. Range: $min–$max.',
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
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('Cancel'),
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
          child: const Text('Save'),
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
          const Text(
            'Blank = provider default.',
            style: TextStyle(fontSize: 12),
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
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('Cancel'),
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
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return result;
}
