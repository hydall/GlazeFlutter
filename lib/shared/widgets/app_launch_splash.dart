import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppLaunchSplash extends StatefulWidget {
  final bool isReady;
  final Widget child;

  const AppLaunchSplash({
    super.key,
    required this.isReady,
    required this.child,
  });

  @override
  State<AppLaunchSplash> createState() => _AppLaunchSplashState();
}

class _AppLaunchSplashState extends State<AppLaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  Future<String>? _svgFuture;
  Color? _svgColor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      value: widget.isReady ? 1 : 0,
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant AppLaunchSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isReady && widget.isReady) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accent = Theme.of(context).colorScheme.primary;
    if (_svgColor?.toARGB32() == accent.toARGB32()) return;
    _svgColor = accent;
    _svgFuture = rootBundle
        .loadString('assets/logos/glaze.svg')
        .then((svg) => _retintSvg(svg, accent));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = widget.isReady ? _curve.value : 0.0;
        final splashOpacity = widget.isReady
            ? (1 - Curves.easeIn.transform(_interval(t, 0.30, 0.78))).clamp(
                0.0,
                1.0,
              )
            : 1.0;
        final logoIntroScale = Tween<double>(
          begin: 0.78,
          end: 1,
        ).transform(Curves.easeOutBack.transform(_interval(t, 0, 0.22)));
        final logoExitScale = widget.isReady
            ? Tween<double>(
                begin: 1,
                end: 1.12,
              ).transform(Curves.easeInCubic.transform(_interval(t, 0.30, 0.78)))
            : 1.0;
        final logoScale = logoIntroScale * logoExitScale;
        final childOpacity = widget.isReady
            ? Curves.easeOut.transform(_interval(t, 0.08, 0.58))
            : 0.0;
        final childScale = widget.isReady
            ? Tween<double>(
                begin: 0.82,
                end: 1,
              ).transform(
                Curves.easeOutCubic.transform(_interval(t, 0.04, 0.72)),
              )
            : 0.82;

        return ColoredBox(
          color: background,
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                ignoring: childOpacity < 0.999,
                child: Opacity(
                  opacity: childOpacity,
                  child: Transform.scale(
                    scale: childScale,
                    child: widget.child,
                  ),
                ),
              ),
              if (splashOpacity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: splashOpacity,
                      child: Center(
                        child: Transform.scale(
                          scale: logoScale,
                          child: FutureBuilder<String>(
                            future: _svgFuture,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const SizedBox(
                                  width: 176,
                                  height: 176,
                                );
                              }
                              return SvgPicture.string(
                                snapshot.data!,
                                width: 176,
                                height: 176,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _interval(double t, double start, double end) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return (t - start) / (end - start);
  }

  String _retintSvg(String svg, Color accent) {
    final hex = _toHex(accent);
    final fillPattern = RegExp(r'fill="(?!none)[^"]+"', caseSensitive: false);
    final strokePattern = RegExp(
      r'stroke="(?!none)[^"]+"',
      caseSensitive: false,
    );
    var retinted = svg.replaceAll(fillPattern, 'fill="$hex"');
    retinted = retinted.replaceAll(strokePattern, 'stroke="$hex"');
    return retinted;
  }

  String _toHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
