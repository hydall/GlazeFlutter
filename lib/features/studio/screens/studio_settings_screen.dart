import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/api_config.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/studio_build_provider.dart';
import '../../settings/api_list_provider.dart';

/// Studio Settings screen — the main entry point for Studio configuration.
///
/// Shows:
/// - Studio enable/disable toggle
/// - 3 API Config dropdowns (expensive/cheap/cleaner)
/// - Build Studio button
/// - Tracker list with enable toggles
/// - Link to Preset Editor
///
/// Replaces the old `StudioMenuDialog` as a full screen with proper
/// navigation. Session-bound — scoped to one chat session's StudioConfig.
class StudioSettingsScreen extends ConsumerStatefulWidget {
  final String charId;
  final String sessionId;

  const StudioSettingsScreen({
    super.key,
    required this.charId,
    required this.sessionId,
  });

  @override
  ConsumerState<StudioSettingsScreen> createState() =>
      _StudioSettingsScreenState();
}

class _StudioSettingsScreenState extends ConsumerState<StudioSettingsScreen> {
  StudioConfig? _config;
  List<ApiConfig> _apiConfigs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(apiListProvider.future);
    final repo = ref.read(studioConfigRepoProvider);
    final config = await repo.getBySessionId(widget.sessionId);
    final apiConfigs =
        ref.read(apiListProvider).value ?? const <ApiConfig>[];
    if (!mounted) return;
    setState(() {
      _config = config;
      _apiConfigs = apiConfigs;
      _loading = false;
    });
  }

  Future<void> _save(StudioConfig config) async {
    final repo = ref.read(studioConfigRepoProvider);
    await repo.upsert(config);
    setState(() => _config = config);
  }

  bool get _building =>
      ref.read(studioBuildProvider.notifier).isBuilding(widget.sessionId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio Settings'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chat/${widget.charId}');
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _config == null
              ? _buildNoConfig()
              : _buildBody(),
    );
  }

  Widget _buildNoConfig() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('No Studio configuration for this session.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _buildStudio,
            icon: const Icon(Icons.build),
            label: const Text('Build Studio'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final config = _config!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Enable toggle
        SwitchListTile(
          title: const Text('Studio Enabled'),
          value: config.enabled,
          onChanged: (v) => _save(config.copyWith(enabled: v)),
        ),
        const Divider(),

        // 3 API Config dropdowns
        Text('API Configuration',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _buildApiConfigDropdown(
          label: 'Expensive (Final Generator)',
          value: config.expensiveApiConfigId,
          onChanged: (v) => _save(config.copyWith(expensiveApiConfigId: v)),
        ),
        const SizedBox(height: 8),
        _buildApiConfigDropdown(
          label: 'Cheap (Trackers)',
          value: config.cheapApiConfigId,
          onChanged: (v) => _save(config.copyWith(cheapApiConfigId: v)),
        ),
        const SizedBox(height: 8),
        _buildApiConfigDropdown(
          label: 'Cleaner (Post-Processing)',
          value: config.cleanerApiConfigId,
          onChanged: (v) => _save(config.copyWith(cleanerApiConfigId: v)),
        ),
        const Divider(),

        // Build button
        if (_building)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          FilledButton.icon(
            onPressed: _buildStudio,
            icon: const Icon(Icons.build),
            label: const Text('Build Studio'),
          ),
        const Divider(),

        // Preset editor link
        ListTile(
          leading: const Icon(Icons.edit_note),
          title: const Text('Edit Preset Blocks'),
          subtitle: const Text('Customize prompt templates for all agents'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(
            '/studio/preset/${config.studioPresetId}',
          ),
        ),
        const Divider(),

        // Tracker list
        Text('Trackers', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ..._buildTrackerList(config),
      ],
    );
  }

  List<Widget> _buildTrackerList(StudioConfig config) {
    final agents = config.agents.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (agents.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text('No trackers. Build Studio to create agents.'),
        ),
      ];
    }
    return agents.map((agent) {
      return ListTile(
        title: Text(agent.name.isNotEmpty ? agent.name : agent.id),
        subtitle: Text(
          'order=${agent.order} · context=${agent.contextSize} · '
          'interval=${agent.runInterval} · phase=${agent.phase}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Switch(
          value: agent.enabled,
          onChanged: (v) => _toggleAgent(config, agent, v),
        ),
      );
    }).toList();
  }

  Widget _buildApiConfigDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value.isNotEmpty && _apiConfigs.any((c) => c.id == value)
          ? value
          : '',
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text('Use active chat API'),
        ),
        ..._apiConfigs.map(
          (c) => DropdownMenuItem<String>(
            value: c.id,
            child: Text(
              c.name.isNotEmpty ? c.name : c.id,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }

  Future<void> _toggleAgent(
    StudioConfig config,
    StudioAgent agent,
    bool enabled,
  ) async {
    final agents = config.agents.map((a) {
      return a.id == agent.id ? a.copyWith(enabled: enabled) : a;
    }).toList();
    await _save(config.copyWith(agents: agents));
  }

  void _buildStudio() {
    ref
        .read(studioBuildProvider.notifier)
        .startBuild(sessionId: widget.sessionId, charId: widget.charId);
  }
}
