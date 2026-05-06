import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/preset.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../presets/widgets/regex_tile.dart';

class RegexListScreen extends ConsumerWidget {
  const RegexListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetsAsync = ref.watch(presetRepoProvider);

    return GlazeScaffold(
      title: 'Regex Scripts',
      onBack: () => context.go('/tools'),
      body: FutureBuilder<List<Preset>>(
        future: presetsAsync.getAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final presets = snap.data ?? [];
          final allRegexes = <MapEntry<String, PresetRegex>>[];
          for (final p in presets) {
            for (final r in p.regexes) {
              allRegexes.add(MapEntry(p.id, r));
            }
          }

          if (allRegexes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.code, size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  const Text('No regex scripts yet'),
                  const SizedBox(height: 8),
                  const Text(
                    'Add regex scripts inside presets',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 40),
            itemCount: allRegexes.length,
            itemBuilder: (_, i) {
              final entry = allRegexes[i];
              final regex = entry.value;
              final presetId = entry.key;
              return _EditableRegexItem(
                regex: regex,
                presetId: presetId,
                presets: presets,
              );
            },
          );
        },
      ),
    );
  }
}

class _EditableRegexItem extends ConsumerWidget {
  final PresetRegex regex;
  final String presetId;
  final List<Preset> presets;

  const _EditableRegexItem({
    required this.regex,
    required this.presetId,
    required this.presets,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetName = presets.firstWhere((p) => p.id == presetId).name;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Icon(
                    regex.disabled ? Icons.code_off : Icons.code,
                    size: 16,
                    color: regex.disabled ? AppColors.textSecondary : AppColors.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text('From: $presetName', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                  Switch(
                    value: !regex.disabled,
                    onChanged: (v) => _updateRegex(ref, regex.copyWith(disabled: !v)),
                    activeColor: AppColors.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
            RegexTile(
              regex: regex,
              onChanged: (updated) => _updateRegex(ref, updated),
            ),
          ],
        ),
      ),
    );
  }

  void _updateRegex(WidgetRef ref, PresetRegex updated) async {
    final preset = presets.firstWhere((p) => p.id == presetId);
    final updatedRegexes = preset.regexes.map((r) {
      if (r.id == regex.id) return updated;
      return r;
    }).toList();
    await ref.read(presetRepoProvider).put(preset.copyWith(regexes: updatedRegexes));
    ref.invalidate(presetRepoProvider);
  }
}
