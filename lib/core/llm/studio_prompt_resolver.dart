import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/studio_config.dart';
import '../state/db_provider.dart';
import 'studio_request_preset.dart';

/// Resolves Studio prompt blocks from the DB (`studio_preset_rows`) with
/// fallback to the hardcoded constants. Once the cleanup PR removes the
/// fallbacks, this resolver becomes the sole source of prompt text.
///
/// The resolver caches the DB preset in memory (the preset rarely changes).
/// Call [invalidate] when the user edits the preset to force a re-read.
class StudioPromptResolver {
  final Ref _ref;
  StudioPreset? _cached;
  bool _loaded = false;

  StudioPromptResolver(this._ref);

  /// Get all blocks for a section, ordered by `order`, enabled only.
  /// Falls back to hardcoded constants when the DB has no preset or the
  /// section is missing.
  Future<List<StudioPresetBlock>> blocksForSection(String section) async {
    final preset = await _ensureLoaded();
    if (preset != null) {
      final blocks = preset.blocks
          .where((b) => b.enabled && b.section == section)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (blocks.isNotEmpty) return blocks;
    }
    return _fallbackBlocksForSection(section);
  }

  /// Get a single block by id across all sections.
  /// Falls back to hardcoded constant when not found.
  Future<StudioPresetBlock?> blockById(String id) async {
    final preset = await _ensureLoaded();
    if (preset != null) {
      final block = preset.blocks.where((b) => b.id == id).firstOrNull;
      if (block != null) return block;
    }
    return _fallbackBlockById(id);
  }

  /// Get the raw text content of a block by id, or empty string when not
  /// found. Convenience wrapper for [blockById].
  Future<String> contentById(String id) async {
    final block = await blockById(id);
    return block?.content ?? '';
  }

  /// Force a re-read of the preset from the DB on the next call.
  void invalidate() {
    _loaded = false;
    _cached = null;
  }

  Future<StudioPreset?> _ensureLoaded() async {
    if (_loaded) return _cached;
    _cached = await _ref.read(studioPresetRepoProvider).getDefault();
    _loaded = true;
    return _cached;
  }

  /// Hardcoded fallback blocks. These mirror the current constants and are
  /// used only when the DB has no preset row (e.g. fresh install before the
  /// v54 migration seeds, or a corrupt row). Once the cleanup PR lands, these
  /// are removed and the resolver reads from DB only.
  List<StudioPresetBlock> _fallbackBlocksForSection(String section) {
    switch (section) {
      case 'pregen':
        return studioRequestPresets
            .firstWhere((p) => p.id == defaultAgentStudioPresetId)
            .blocks;
      case 'final':
        return studioRequestPresets
            .firstWhere((p) => p.id == defaultFinalStudioPresetId)
            .blocks;
      default:
        return const [];
    }
  }

  StudioPresetBlock? _fallbackBlockById(String id) {
    for (final preset in studioRequestPresets) {
      final block = preset.blocks.where((b) => b.id == id).firstOrNull;
      if (block != null) return block;
    }
    return null;
  }
}

final studioPromptResolverProvider = Provider<StudioPromptResolver>((ref) {
  return StudioPromptResolver(ref);
});
