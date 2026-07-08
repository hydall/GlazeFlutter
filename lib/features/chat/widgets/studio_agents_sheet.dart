import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/studio_controller_ontology.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';

/// Agent on/off toggles for a Studio preset.
///
/// Shows one switch per controller spec (continuity, narrative, final, etc.).
/// State is persisted into `StudioPreset.agentEnabled` so it travels with
/// the preset on import/export.
class StudioAgentsSheet extends ConsumerStatefulWidget {
  final String presetId;

  const StudioAgentsSheet({super.key, required this.presetId});

  static Future<void> show(
    BuildContext context, {
    required String presetId,
  }) {
    return GlazeBottomSheet.show<void>(
      context,
      title: 'Agents',
      child: StudioAgentsSheet(presetId: presetId),
    );
  }

  @override
  ConsumerState<StudioAgentsSheet> createState() => _StudioAgentsSheetState();
}

class _StudioAgentsSheetState extends ConsumerState<StudioAgentsSheet> {
  StudioPreset? _preset;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preset =
        await ref.read(studioPresetRepoProvider).getById(widget.presetId);
    if (!mounted) return;
    setState(() {
      _preset = preset;
      _loading = false;
    });
  }

  Future<void> _toggle(String specId, bool value) async {
    if (_preset == null) return;
    final updated = Map<String, bool>.from(_preset!.agentEnabled);
    updated[specId] = value;
    final next = _preset!.copyWith(
      agentEnabled: updated,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(studioPresetRepoProvider).upsert(next);
    setState(() => _preset = next);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_preset == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Preset not found')),
      );
    }
    final enabledMap = _preset!.agentEnabled;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: StudioControllerOntology.specs.length,
        itemBuilder: (context, index) {
          final spec = StudioControllerOntology.specs[index];
          final isOn = enabledMap[spec.id] ?? true;
          return SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            secondary: Icon(
              spec.isFinal ? Icons.star_outline : Icons.smart_toy_outlined,
              color: spec.isFinal
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(spec.name),
            subtitle: Text(
              spec.purpose,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            value: isOn,
            onChanged: (v) => _toggle(spec.id, v),
          );
        },
      ),
    );
  }
}
