import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/block_config.dart';
import '../models/extension_preset.dart';
import '../providers/extension_presets_provider.dart';
import '../providers/extensions_settings_provider.dart';
import 'extension_post_gen_service.dart';

/// In-process scheduler for `BlockTrigger.periodic` blocks.
///
/// The scheduler watches:
///   * `extensionPresetsProvider` — to discover new/updated/changed blocks.
///   * `extensionsSettingsProvider` — to pause/resume with the master
///     extensions toggle and the active preset selection.
///
/// For each enabled block with `trigger == BlockTrigger.periodic` the
/// scheduler starts a per-block [Timer.periodic]. The tick handler
/// delegates to [ExtensionPostGenService.runJsBlock] which already
/// prefers the headless engine and falls back to the visual bridge.
///
/// Lifecycle:
///   * One scheduler per app (singleton).
///   * `start()` is idempotent.
///   * `dispose()` cancels all timers.
///
/// Battery / lifecycle hooks are intentionally out of scope for the
/// first implementation (see plan item #20). The scheduler simply runs
/// while the app is alive; pausing on background requires a
/// `WidgetsBindingObserver` and is a follow-up.
class PeriodicTriggerScheduler {
  PeriodicTriggerScheduler(this._ref);

  final Ref _ref;
  final Map<String, Timer> _timers = {};
  ProviderSubscription<List<ExtensionPreset>>? _presetSub;
  ProviderSubscription<dynamic>? _settingsSub;
  bool _started = false;

  /// Starts the scheduler. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    // Rebuild the timer set whenever the preset list OR the settings
    // change. Both providers are watched via subscriptions so the
    // scheduler itself doesn't need to be a Riverpod consumer.
    _presetSub = _ref.listen<List<ExtensionPreset>>(
      extensionPresetsProvider,
      (_, __) => _rebuildTimers(),
      fireImmediately: true,
    );
    _settingsSub = _ref.listen<dynamic>(
      extensionsSettingsProvider,
      (_, __) => _rebuildTimers(),
      fireImmediately: true,
    );
  }

  void _rebuildTimers() {
    final settings = _ref.read(extensionsSettingsProvider);
    final activeId = settings.activePresetId;
    if (!settings.enabled || activeId == null || activeId.isEmpty) {
      _cancelAll();
      return;
    }
    final presets = _ref.read(extensionPresetsProvider);
    final preset = presets.where((p) => p.id == activeId).firstOrNull;
    if (preset == null) {
      _cancelAll();
      return;
    }

    final activeBlocks = {
      for (final b in preset.blocks.where(
        (b) =>
            b.enabled &&
            b.type == BlockType.jsRunner &&
            b.trigger == BlockTrigger.periodic,
      ))
        b.id: b,
    };

    // Drop timers for removed/disabled blocks.
    for (final key in _timers.keys.toList()) {
      if (!activeBlocks.containsKey(key)) {
        _timers.remove(key)?.cancel();
      }
    }

    // Start or restart timers for current blocks. The interval may have
    // changed, so we always cancel-then-recreate.
    for (final entry in activeBlocks.entries) {
      final block = entry.value;
      final seconds = block.periodicIntervalSeconds <= 0
          ? 60
          : block.periodicIntervalSeconds;
      _timers.remove(entry.key)?.cancel();
      _timers[entry.key] = Timer.periodic(
        Duration(seconds: seconds),
        (_) => _tick(block),
      );
    }
  }

  Future<void> _tick(BlockConfig block) async {
    try {
      final post = _ref.read(extensionPostGenServiceProvider);
      // `runJsBlock` is the existing entry point — it handles headless /
      // visual fallback and the cancel token. We don't need a
      // continuation on the returned future; periodic ticks are
      // fire-and-forget.
      unawaited(
        post.runJsBlock(
          charId: _ref.read(extensionsSettingsProvider).activePresetId ?? '',
          block: block,
          contextMessages: const [],
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PeriodicTrigger] tick failed for ${block.name}: $e');
      }
    }
  }

  void _cancelAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }

  /// Visible for tests.
  int get activeTimerCount => _timers.length;

  void dispose() {
    _cancelAll();
    _presetSub?.close();
    _settingsSub?.close();
    _started = false;
  }
}

final periodicTriggerSchedulerProvider =
    Provider<PeriodicTriggerScheduler>((ref) {
  final scheduler = PeriodicTriggerScheduler(ref);
  scheduler.start();
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
