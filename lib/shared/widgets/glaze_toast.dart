import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart' show rootNavigatorKey;

enum ToastPosition { top, bottom }

// ── Public API ────────────────────────────────────────────────────────────────

class GlazeToast {
  static _ActiveToast? _current;

  static void show(
    BuildContext context,
    String text, {
    int duration = 2500,
    ToastPosition position = ToastPosition.bottom,
    bool isError = false,
  }) {
    _current?.cancel();

    final key = GlobalKey<_ToastAnimatorState>();
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _ToastAnimator(
        key: key,
        text: text,
        position: position,
        isError: isError,
        onRemove: () {
          entry.remove();
          if (_current?.entry == entry) _current = null;
        },
      ),
    );

    final rootOverlay = rootNavigatorKey.currentState?.overlay;
    if (rootOverlay != null) {
      rootOverlay.insert(entry);
    } else {
      Overlay.of(context).insert(entry);
    }

    final timer = Timer(
      Duration(milliseconds: duration),
      () => key.currentState?.dismiss(),
    );

    _current = _ActiveToast(entry: entry, key: key, timer: timer);
  }

  static void hide() => _current?.cancel();

  static void error(BuildContext context, String prefix, Object error) {
    final text = '$prefix$error';
    final ctx = rootNavigatorKey.currentContext ?? context;
    show(
      ctx,
      text,
      duration: 4000,
      position: ToastPosition.top,
      isError: true,
    );
  }
}

// ── Internal state tracker ────────────────────────────────────────────────────

class _ActiveToast {
  final OverlayEntry entry;
  final GlobalKey<_ToastAnimatorState> key;
  final Timer timer;

  _ActiveToast({required this.entry, required this.key, required this.timer});

  void cancel() {
    timer.cancel();
    key.currentState?.dismiss();
  }
}

// ── Animated toast widget ─────────────────────────────────────────────────────

class _ToastAnimator extends StatefulWidget {
  final String text;
  final ToastPosition position;
  final bool isError;
  final VoidCallback onRemove;

  const _ToastAnimator({
    super.key,
    required this.text,
    required this.position,
    this.isError = false,
    required this.onRemove,
  });

  @override
  State<_ToastAnimator> createState() => _ToastAnimatorState();
}

class _ToastAnimatorState extends State<_ToastAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<double> _translateY;

  static const _enterCurve = Cubic(0.34, 1.56, 0.64, 1);
  static const _enterDuration = Duration(milliseconds: 300);
  static const _leaveDuration = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _enterDuration);

    _opacity = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _scale = Tween(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: _enterCurve));

    // Bottom toasts enter from below, top toasts enter from above
    final enterOffset = widget.position == ToastPosition.bottom ? 20.0 : -20.0;
    _translateY = Tween(
      begin: enterOffset,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: _enterCurve));

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> dismiss() async {
    if (!mounted) return;
    _ctrl.duration = _leaveDuration;
    await _ctrl.animateBack(0.0, curve: Curves.easeIn);
    if (mounted) widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isBottom = widget.position == ToastPosition.bottom;

    // bottom: above nav bar (~80px) + margin; top: below status bar + header
    final double positionValue = isBottom
        ? mq.padding.bottom + 80 + 24
        : mq.padding.top + 56 + 16;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: isBottom ? positionValue : null,
          top: isBottom ? null : positionValue,
          child: IgnorePointer(
            ignoring: false,
            child: Center(
              child: Transform.translate(
                offset: Offset(0, _translateY.value),
                child: Transform.scale(
                  scale: _scale.value,
                  child: Opacity(
                    opacity: _opacity.value,
                    child: _ToastChip(text: widget.text, onTap: dismiss, isError: widget.isError),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Visual chip ───────────────────────────────────────────────────────────────

class _ToastChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool isError;

  const _ToastChip({required this.text, required this.onTap, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 48,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isError ? const Color(0xEB5C1A1A) : const Color(0xEB1E1E1E),
                border: isError ? Border.all(color: const Color(0x80FF4444), width: 1) : null,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x401A1A1A),
                    blurRadius: 20,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  height: 1.3,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
