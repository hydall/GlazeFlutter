import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/studio_decomposition_service.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/memory_agent_providers.dart';
import '../../../core/utils/time_helpers.dart';
import '../../../shared/theme/app_colors.dart';
import '../chat_provider.dart';

/// Studio Mode menu dialog. Session-bound.
///
/// Flow:
/// 1. User opens from MagicDrawer "Studio" item.
/// 2. If no config exists → shows "Build Studio" button.
/// 3. User clicks "Build Studio" → LLM decomposes the active preset into agents.
/// 4. Menu shows: agent list with editable prompts + per-agent model config.
/// 5. Toggle to enable/disable Studio for this session.
class StudioMenuDialog extends ConsumerStatefulWidget {
  final String charId;
  final String sessionId;

  const StudioMenuDialog({
    super.key,
    required this.charId,
    required this.sessionId,
  });

  @override
  ConsumerState<StudioMenuDialog> createState() => _StudioMenuDialogState();
}

class _StudioMenuDialogState extends ConsumerState<StudioMenuDialog> {
  StudioConfig? _config;
  bool _loading = true;
  bool _building = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await ref
          .read(studioConfigRepoProvider)
          .getBySessionId(widget.sessionId);
      if (mounted) {
        setState(() {
          _config = config;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _buildStudio() async {
    setState(() {
      _building = true;
      _error = null;
    });

    try {
      final chatState = ref.read(chatProvider(widget.charId)).value;
      if (chatState?.session == null) {
        throw Exception('No active session');
      }
      final session = chatState!.session!;
      final charId = session.characterId;

      final presetRepo = ref.read(presetRepoProvider);
      final connections = ref.read(presetConnectionsProvider);
      final presetId = connections.chat[widget.sessionId] ??
          connections.character[charId];
      if (presetId == null) {
        throw Exception('No preset bound to this session');
      }

      final preset = await presetRepo.getById(presetId);
      if (preset == null) {
        throw Exception('Preset not found');
      }

      final decompositionService = ref.read(studioDecompositionServiceProvider);
      final agents = await decompositionService.decompose(
        preset: preset,
        sessionId: widget.sessionId,
      );

      if (agents.isEmpty) {
        throw Exception('Decomposition returned no agents');
      }

      final now = currentTimestampSeconds();
      final newConfig = StudioConfig(
        sessionId: widget.sessionId,
        enabled: true,
        agents: agents,
        sourcePresetId: presetId,
        sourcePresetHash: StudioDecompositionService.computePresetHash(
          preset.blocks.where((b) => b.enabled).toList(),
        ),
        createdAt: now,
        updatedAt: now,
      );

      await ref.read(studioConfigRepoProvider).upsert(newConfig);

      if (mounted) {
        setState(() {
          _config = newConfig;
          _building = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _building = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 650,
        height: 600,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.movie_filter_outlined, color: context.cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'menu_studio'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (_config != null)
            Switch(
              value: _config!.enabled,
              onChanged: (v) async {
                final updated = _config!.copyWith(enabled: v);
                await ref.read(studioConfigRepoProvider).upsert(updated);
                setState(() => _config = updated);
              },
            ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    }

    if (_config == null || _config!.agents.isEmpty) {
      return _buildEmptyState();
    }

    return _buildAgentList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_filter_outlined,
              size: 64,
              color: context.cs.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Studio Mode decomposes your preset into agent tasks.\n'
              'Each agent gets its own instructions and model config.\n'
              'Agents collaborate to produce the final RP response.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cs.onSurfaceVariant,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _building ? null : _buildStudio,
              icon: _building
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_building ? 'Building...' : 'Build Studio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_config!.agents.length} agents',
                style: TextStyle(
                  color: context.cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _building ? null : _buildStudio,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Rebuild'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _config!.agents.length,
            onReorderItem: (oldIndex, newIndex) {
              final agents = List<StudioAgent>.from(_config!.agents);
              final item = agents.removeAt(oldIndex);
              agents.insert(newIndex, item);
              for (var i = 0; i < agents.length; i++) {
                agents[i] = agents[i].copyWith(order: i);
              }
              final updated = _config!.copyWith(agents: agents);
              ref.read(studioConfigRepoProvider).upsert(updated);
              setState(() => _config = updated);
            },
            itemBuilder: (context, index) {
              final agent = _config!.agents[index];
              return _buildAgentTile(agent, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAgentTile(StudioAgent agent, int index) {
    final isLast = index == _config!.agents.length - 1;
    return Card(
      key: ValueKey(agent.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        title: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle, size: 20),
              ),
            ),
            Icon(
              isLast
                  ? Icons.edit_outlined
                  : index == 0
                      ? Icons.psychology_outlined
                      : Icons.tune_outlined,
              size: 20,
              color: context.cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                agent.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isLast)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.cs.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'FINAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: context.cs.onPrimaryContainer,
                  ),
                ),
              ),
            Switch(
              value: agent.enabled,
              onChanged: (v) => _updateAgent(agent.copyWith(enabled: v)),
            ),
          ],
        ),
        subtitle: Text(
          agent.sourceBlockNames.isNotEmpty
              ? 'From: ${agent.sourceBlockNames}'
              : 'Order: ${agent.order}',
          style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
        ),
        children: [
          _buildAgentDetails(agent),
        ],
      ),
    );
  }

  Widget _buildAgentDetails(StudioAgent agent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prompt shard:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.cs.onSurfaceVariant,
              )),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: agent.promptShard,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (value) => _updateAgent(agent.copyWith(promptShard: value)),
          ),
          const SizedBox(height: 16),
          Text('Model:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.cs.onSurfaceVariant,
              )),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'current', label: Text('Current')),
              ButtonSegment(value: 'custom', label: Text('Custom')),
            ],
            selected: {agent.modelSource},
            onSelectionChanged: (s) =>
                _updateAgent(agent.copyWith(modelSource: s.first)),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          if (agent.modelSource == 'custom') ...[
            const SizedBox(height: 8),
            TextFormField(
              initialValue: agent.model,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => _updateAgent(agent.copyWith(model: v)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: agent.endpoint,
              decoration: const InputDecoration(
                labelText: 'Endpoint',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => _updateAgent(agent.copyWith(endpoint: v)),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: agent.temperature.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Temp',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    final temp = double.tryParse(v);
                    if (temp != null) {
                      _updateAgent(agent.copyWith(temperature: temp));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: agent.maxTokens.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Max tokens',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final tokens = int.tryParse(v);
                    if (tokens != null) {
                      _updateAgent(agent.copyWith(maxTokens: tokens));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: agent.timeoutMs.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Timeout ms',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final ms = int.tryParse(v);
                    if (ms != null) {
                      _updateAgent(agent.copyWith(timeoutMs: ms));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _updateAgent(StudioAgent updated) {
    final agents = _config!.agents.map((a) {
      return a.id == updated.id ? updated : a;
    }).toList();
    final newConfig = _config!.copyWith(
      agents: agents,
      updatedAt: currentTimestampSeconds(),
    );
    ref.read(studioConfigRepoProvider).upsert(newConfig);
    setState(() => _config = newConfig);
  }
}
