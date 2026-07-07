import 'package:flutter/widgets.dart';

/// Compile-time diagnostic switches for on-device performance profiling.
///
/// Every switch is OFF by default and only activates through a
/// `--dart-define` flag, so shipping builds carry none of this (the dead
/// branches are tree-shaken). Example profiling run:
///
/// ```
/// flutter run --profile --dart-define=PERF_LOG_FRAMES=true
/// flutter run --profile --dart-define=NO_GLASS_BLUR=true
/// ```
abstract final class PerfDebug {
  /// Print every frame that misses the 60fps budget, split by thread
  /// (build = UI thread / widget rebuilds, raster = GPU thread / blur & co).
  static const bool logSlowFrames = bool.fromEnvironment('PERF_LOG_FRAMES');

  /// Disable the BackdropFilter blur of every GlassSurface.
  static const bool noGlassBlur = bool.fromEnvironment('NO_GLASS_BLUR');

  /// Disable the TopEdgeBlur header blur (sheets, drawer panels).
  static const bool noEdgeBlur = bool.fromEnvironment('NO_EDGE_BLUR');

  /// Disable the film-grain NoiseOverlay on glass surfaces and backgrounds.
  static const bool noNoise = bool.fromEnvironment('NO_NOISE');

  /// Installs the slow-frame logger; no-op unless [logSlowFrames] is set.
  static void installFrameLoggerIfEnabled() {
    if (!logSlowFrames) return;
    WidgetsBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final buildMs = t.buildDuration.inMicroseconds / 1000.0;
        final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
        if (buildMs > 17 || rasterMs > 17) {
          // ignore: avoid_print
          print(
            '[frame] build=${buildMs.toStringAsFixed(1)}ms '
            'raster=${rasterMs.toStringAsFixed(1)}ms '
            'total=${(t.totalSpan.inMicroseconds / 1000.0).toStringAsFixed(1)}ms',
          );
        }
      }
    });
  }
}
