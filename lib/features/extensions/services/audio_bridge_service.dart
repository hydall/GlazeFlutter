import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Minimal audio facade for the JS extension `glaze.playAudio(source, options)`
/// bridge.
///
/// The MVP implementation does **not** stream arbitrary audio files
/// (the `audioplayers` package is intentionally not in `pubspec.yaml`
/// for the first cut). The bridge supports three built-in cues:
///
///   * `'click'`   — `SystemSoundType.click` (a short click on supported
///     platforms).
///   * `'alert'`   — `SystemSoundType.alert` (a system alert sound).
///   * `'haptic'`  — `HapticFeedback.mediumImpact()` (no sound, a
///     vibration on supported devices).
///
/// Any other `source` string is treated as a no-op (logged) so the JS
/// side can still pass a URL or file path without breaking — the
/// extension can later swap the implementation for a real audio backend
/// without changing the bridge contract.
///
/// `volume` and `loop` options are accepted but currently ignored; they
/// are reserved for the future `audioplayers` integration.
class AudioBridgeService {
  AudioBridgeService();

  /// Plays a built-in audio cue. Returns when the request has been
  /// handed off to the platform.
  Future<void> play(
    String? source,
    Map<String, dynamic> options,
  ) async {
    final resolved = (source ?? 'click').trim().toLowerCase();
    if (kDebugMode) {
      debugPrint('[AudioBridge] play source="$resolved" options=$options');
    }
    switch (resolved) {
      case 'click':
        await SystemSound.play(SystemSoundType.click);
      case 'alert':
        await SystemSound.play(SystemSoundType.alert);
      case 'haptic':
        await HapticFeedback.mediumImpact();
      case '':
        return;
      default:
        // Unknown source — log and ignore. Reserved for the future
        // file/URL backend.
        if (kDebugMode) {
          debugPrint(
            '[AudioBridge] unknown source "$resolved" — no-op. '
            'Built-in cues: click, alert, haptic.',
          );
        }
        return;
    }
  }
}
