import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/models/character.dart';
import '../../../core/utils/platform_paths.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/card_tag_chips.dart';
import '../../../shared/widgets/glaze_logo.dart';

/// Opens the randomizing character-discovery overlay.
///
/// A holographic "Holocard" (mirrors Glaze's `HoloCardViewer`) floats above the
/// character list on a dimmed, blurred backdrop. Swiping the card right (or
/// tapping the chat button) starts a brand-new chat with that character; swiping
/// left (or the skip button) discards it and deals the next random card. The
/// holographic tilt tracks the device gyroscope (or the mouse on desktop), not
/// the drag.
Future<void> showRandomizingCardOverlay(
  BuildContext context,
  List<Character> pool,
) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    barrierLabel: 'randomizing_discovery',
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (_, _, _) => RandomizingCardOverlay(pool: pool),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: child,
      );
    },
  );
}

class RandomizingCardOverlay extends StatefulWidget {
  final List<Character> pool;
  const RandomizingCardOverlay({super.key, required this.pool});

  @override
  State<RandomizingCardOverlay> createState() => _RandomizingCardOverlayState();
}

class _RandomizingCardOverlayState extends State<RandomizingCardOverlay>
    with TickerProviderStateMixin {
  /// Shuffled deck we deal from; reshuffled (endlessly) when exhausted.
  late List<Character> _deck;
  int _index = 0;

  /// Live drag offset of the top card, in logical pixels from its rest spot.
  Offset _drag = Offset.zero;
  bool _dragging = false;

  /// Set once a chat is being opened (right fling / chat button): hides the
  /// peeking next cards so nothing shows behind the card as it flies away.
  bool _openingChat = false;

  /// Drives fly-off / spring-back of the top card by tweening [_drag].
  late final AnimationController _swipeCtrl;
  Animation<Offset>? _swipeTween;

  /// Endless idle shimmer that sweeps the holographic sheen at rest.
  late final AnimationController _shimmerCtrl;

  /// Entry pop of the whole stack.
  late final AnimationController _entryCtrl;

  /// Last direction we haptically "armed" so we buzz only on threshold crossings.
  int _armedDir = 0;

  // ─── Holographic tilt (gyroscope / mouse), smoothed into −1..1 ──────────────
  //
  // The sensor (or the mouse) writes a raw *target*; the actual [_tiltX]/[_tiltY]
  // used for rendering eases toward it once per frame (see [_onTiltFrame]).
  // Smoothing per-frame instead of per-sample keeps the motion fluid regardless
  // of the sensor's irregular delivery rate and filters out its jitter.
  double _tiltX = 0;
  double _tiltY = 0;
  double _targetTiltX = 0;
  double _targetTiltY = 0;

  /// Per-frame easing factor toward the target tilt. Lower = smoother but laggier.
  static const double _kTiltEase = 0.12;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  /// Calibration reference captured on first sample after opening; the reading
  /// is expressed relative to it so the "flat" pose is wherever the phone was
  /// held. Slowly drifts back if the user tilts past [_kTiltLimit] (mirrors the
  /// Vue `HoloCardViewer` "catch-up" behaviour).
  double _calRoll = 0;
  double _calPitch = 0;
  bool _needsCalibration = true;
  static const double _kTiltLimit = 26; // degrees mapped to full ±1
  static const double _kDrift = 0.05;

  double get _screenW => MediaQuery.of(context).size.width;

  @override
  void initState() {
    super.initState();
    _deck = List<Character>.of(widget.pool)..shuffle();
    if (_deck.isEmpty) _deck = List<Character>.of(widget.pool);

    _swipeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(_onSwipeTick);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )
      // Doubles as the per-frame clock that eases the tilt toward its target.
      ..addListener(_onTiltFrame)
      ..repeat();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();

    // Drive the holographic tilt from the device gyroscope. On platforms with
    // no accelerometer (most desktops / web) the stream simply errors out and
    // the mouse fallback (see [_onHoverTilt]) takes over instead.
    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onAccelerometer, onError: (_) {});
    } catch (_) {
      _accelSub = null;
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _swipeCtrl.dispose();
    _shimmerCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  /// Converts the gravity vector into roll/pitch angles, re-bases them against
  /// the calibration pose (with slow drift), clamps to ±[_kTiltLimit] and
  /// smooths the normalised result into [_tiltX]/[_tiltY]. Runs off-frame; the
  /// per-frame shimmer rebuild renders whatever value is current.
  void _onAccelerometer(AccelerometerEvent e) {
    final rollDeg =
        math.atan2(e.x, math.sqrt(e.y * e.y + e.z * e.z)) * 180 / math.pi;
    final pitchDeg =
        math.atan2(e.y, math.sqrt(e.x * e.x + e.z * e.z)) * 180 / math.pi;

    if (_needsCalibration) {
      _calRoll = rollDeg;
      _calPitch = pitchDeg;
      _needsCalibration = false;
    }

    // Catch-up drift so the neutral pose follows the phone if it's held tilted.
    final rawR = rollDeg - _calRoll;
    if (rawR > _kTiltLimit) {
      _calRoll += (rawR - _kTiltLimit) * _kDrift;
    } else if (rawR < -_kTiltLimit) {
      _calRoll += (rawR + _kTiltLimit) * _kDrift;
    }
    final rawP = pitchDeg - _calPitch;
    if (rawP > _kTiltLimit) {
      _calPitch += (rawP - _kTiltLimit) * _kDrift;
    } else if (rawP < -_kTiltLimit) {
      _calPitch += (rawP + _kTiltLimit) * _kDrift;
    }

    final tx = ((rollDeg - _calRoll) / _kTiltLimit).clamp(-1.0, 1.0);
    final ty = ((pitchDeg - _calPitch) / _kTiltLimit).clamp(-1.0, 1.0);
    // Only record the target; [_onTiltFrame] eases the rendered value toward it
    // once per frame so the foil glides instead of snapping on each sample.
    _targetTiltX = tx.toDouble();
    _targetTiltY = -ty.toDouble();
  }

  /// Eases the rendered tilt toward the latest target. Runs every shimmer frame
  /// (~60fps), just before the deck's [AnimatedBuilder] reads [_tiltX]/[_tiltY].
  void _onTiltFrame() {
    _tiltX += (_targetTiltX - _tiltX) * _kTiltEase;
    _tiltY += (_targetTiltY - _tiltY) * _kTiltEase;
  }

  /// Desktop / web fallback: tilt tracks the pointer over the card.
  void _onHoverTilt(Offset local, Size size) {
    if (size.width == 0 || size.height == 0) return;
    final tx = (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0);
    final ty = (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0);
    _targetTiltX = tx.toDouble();
    _targetTiltY = ty.toDouble();
  }

  void _onHoverExit() {
    _targetTiltX = 0;
    _targetTiltY = 0;
  }

  void _onSwipeTick() {
    final t = _swipeTween;
    if (t != null) setState(() => _drag = t.value);
  }

  Character? get _current =>
      (_index >= 0 && _index < _deck.length) ? _deck[_index] : null;

  Character? get _next =>
      (_index + 1 < _deck.length) ? _deck[_index + 1] : null;

  // ─── Gesture handling ──────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails _) {
    if (_swipeCtrl.isAnimating) return;
    setState(() => _dragging = true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    setState(() => _drag += d.delta);
    final dir = _drag.dx > _threshold
        ? 1
        : _drag.dx < -_threshold
            ? -1
            : 0;
    if (dir != _armedDir) {
      _armedDir = dir;
      if (dir != 0) HapticFeedback.selectionClick();
    }
  }

  double get _threshold => (_screenW * 0.28).clamp(70.0, 160.0);

  void _onPanEnd(DragEndDetails d) {
    _dragging = false;
    final vx = d.velocity.pixelsPerSecond.dx;
    final decideRight = _drag.dx > _threshold || vx > 900;
    final decideLeft = _drag.dx < -_threshold || vx < -900;
    if (decideRight) {
      _flyOff(1);
    } else if (decideLeft) {
      _flyOff(-1);
    } else {
      _springBack();
    }
  }

  void _springBack() {
    _armedDir = 0;
    _swipeTween = Tween<Offset>(begin: _drag, end: Offset.zero).animate(
      CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutBack),
    );
    _swipeCtrl
      ..reset()
      ..forward();
  }

  void _flyOff(int dir) {
    final card = _current;
    if (card == null) return;
    _armedDir = 0;
    // Opening a chat: hide the deck behind the fly-off (the next tick's setState
    // from the swipe controller applies it).
    if (dir > 0) _openingChat = true;
    HapticFeedback.mediumImpact();
    final target = Offset(
      dir * (_screenW + 240),
      _drag.dy + (_drag.dy.abs() < 20 ? -40 : _drag.dy * 0.6),
    );
    _swipeTween = Tween<Offset>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic),
    );
    _swipeCtrl
      ..reset()
      ..forward().whenCompleteOrCancel(() {
        if (!mounted) return;
        if (dir > 0) {
          _startChat(card);
        } else {
          _advance();
        }
      });
  }

  void _advance() {
    setState(() {
      _drag = Offset.zero;
      _index++;
      if (_index >= _deck.length) {
        // Endless discovery: reshuffle and keep dealing, avoiding an immediate
        // repeat of the card that was just on top.
        final last = _deck.isNotEmpty ? _deck.last : null;
        _deck = List<Character>.of(widget.pool)..shuffle();
        if (_deck.length > 1 && _deck.first.id == last?.id) {
          _deck.add(_deck.removeAt(0));
        }
        _index = 0;
      }
    });
  }

  void _startChat(Character c) {
    // Capture the router before popping — this widget's context is torn down by
    // the pop, but the app-level router stays valid.
    final router = GoRouter.of(context);
    Navigator.of(context, rootNavigator: true).pop();
    router.go('/chat/${c.id}?new=1');
  }

  void _close() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardW = math.min(size.width * 0.82, 350.0);
    final cardH = math.min(cardW * 1.5, size.height * 0.62);
    final progress = (_drag.dx / _threshold).clamp(-1.0, 1.0).toDouble();

    // A transparent Material provides the ambient DefaultTextStyle the overlay
    // sits on. `showGeneralDialog` doesn't insert one, so without it every Text
    // inherits the framework's "missing style" debug paint (the yellow
    // double-underline) instead of the app's Inter theme text.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
      children: [
        // Dimmed, blurred backdrop over the character list. Isolated in its own
        // AnimatedBuilder so it only repaints during the entry fade — not on
        // every idle-shimmer frame (a per-frame blur recompute would be janky).
        Positioned.fill(
          child: GestureDetector(
            onTap: _close,
            child: AnimatedBuilder(
              animation: _entryCtrl,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_entryCtrl.value);
                return BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.72 * t),
                  ),
                );
              },
            ),
          ),
        ),
        // Directional tint: as the card is dragged toward an action, half the
        // screen washes into that button's colour (green-ish primary for chat,
        // red for skip).
        Positioned.fill(
          child: IgnorePointer(
            child: _EdgeTint(progress: progress, chatColor: context.cs.primary),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              _TopBar(onClose: _close),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: cardW,
                    height: cardH,
                    // Only the deck rebuilds per shimmer/swipe frame.
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_shimmerCtrl, _swipeCtrl]),
                      builder: (context, _) => _buildDeck(
                        cardW,
                        cardH,
                        (_drag.dx / _threshold).clamp(-1.0, 1.0).toDouble(),
                        Curves.easeOut.transform(_entryCtrl.value),
                      ),
                    ),
                  ),
                ),
              ),
              _ActionBar(
                progress: progress,
                onSkip: () {
                  if (_current != null && !_swipeCtrl.isAnimating) {
                    _drag = const Offset(-30, 0);
                    _flyOff(-1);
                  }
                },
                onChat: () {
                  if (_current != null && !_swipeCtrl.isAnimating) {
                    _drag = const Offset(30, 0);
                    _flyOff(1);
                  }
                },
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'randomizing_hint'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildDeck(
    double cardW,
    double cardH,
    double progress,
    double entry,
  ) {
    final current = _current;
    if (current == null) {
      return _EmptyDeck(onClose: _close);
    }

    final absProgress = progress.abs();

    final children = <Widget>[];

    // Peek of the next card, growing toward full size as the top card leaves.
    final next = _next;
    if (next != null) {
      final peekScale = 0.9 + 0.1 * absProgress;
      final peekOpacity = 0.55 + 0.45 * absProgress;
      // When a chat is opening, fade the deck out smoothly — in step with the
      // top card's fly-off (driven by the swipe controller) — instead of
      // popping it away. `_swipeCtrl` runs 0→1 over the fling, so the peek
      // dissolves as the card leaves.
      final openingFade =
          _openingChat ? (1.0 - _swipeCtrl.value).clamp(0.0, 1.0) : 1.0;
      children.add(
        Center(
          child: Opacity(
            opacity: (peekOpacity * openingFade).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: peekScale,
              child: RepaintBoundary(
                child: HoloCard(
                  key: ValueKey('peek_${next.id}'),
                  character: next,
                  tiltX: 0,
                  tiltY: 0,
                  width: cardW,
                  height: cardH,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // The active top card. The drag only translates/swings it (swipe-to-fling
    // fling); the holographic tilt of the foil comes from the gyroscope (or the
    // mouse on desktop) via [_tiltX]/[_tiltY].
    final swing = (_drag.dx / _screenW) * 0.32;
    // Subtle entry pop for the top card.
    final entryScale = 0.86 + 0.14 * entry;

    children.add(
      Center(
        child: Transform.translate(
          offset: _drag,
          child: Transform.rotate(
            angle: swing,
            child: Transform.scale(
              scale: _dragging || _swipeCtrl.isAnimating ? 1.0 : entryScale,
              child: MouseRegion(
                onHover: (e) =>
                    _onHoverTilt(e.localPosition, Size(cardW, cardH)),
                onExit: (_) => _onHoverExit(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: RepaintBoundary(
                    child: HoloCard(
                      key: ValueKey('top_${current.id}'),
                      character: current,
                      tiltX: _tiltX,
                      tiltY: _tiltY,
                      width: cardW,
                      height: cardH,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(children: children);
  }
}

// ─── Top bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VoidCallback onClose;
  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          const Spacer(),
          _RoundButton(
            icon: Icons.close_rounded,
            size: 44,
            iconSize: 22,
            background: Colors.black.withValues(alpha: 0.5),
            iconColor: Colors.white,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

// ─── Action bar ──────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final double progress;
  final VoidCallback onSkip;
  final VoidCallback onChat;
  const _ActionBar({
    required this.progress,
    required this.onSkip,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    const skipColor = Color(0xFFFF5A6E);
    final chatColor = context.cs.primary;
    // Grow the button the drag is heading toward for live feedback.
    final skipScale = 1.0 + (progress < 0 ? -progress * 0.18 : 0.0);
    final chatScale = 1.0 + (progress > 0 ? progress * 0.18 : 0.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform.scale(
          scale: skipScale,
          child: _RoundButton(
            icon: Icons.close_rounded,
            size: 78,
            iconSize: 38,
            background: const Color(0xFF1C1C22),
            iconColor: skipColor,
            border: Border.all(color: skipColor.withValues(alpha: 0.6), width: 2),
            glow: skipColor.withValues(alpha: (0.3 + (skipScale - 1.0)).clamp(0.0, 1.0)),
            onTap: onSkip,
          ),
        ),
        const SizedBox(width: 52),
        Transform.scale(
          scale: chatScale,
          child: _RoundButton(
            icon: Icons.chat_bubble_rounded,
            size: 78,
            iconSize: 34,
            background: const Color(0xFF1C1C22),
            iconColor: chatColor,
            border: Border.all(color: chatColor.withValues(alpha: 0.6), width: 2),
            glow: chatColor.withValues(alpha: (0.35 + (chatScale - 1.0)).clamp(0.0, 1.0)),
            onTap: onChat,
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color background;
  final Color iconColor;
  final BoxBorder? border;
  final Color? glow;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.iconColor,
    required this.onTap,
    this.border,
    this.glow,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: border,
          boxShadow: [
            if (glow != null)
              BoxShadow(color: glow!, blurRadius: 22, spreadRadius: 1),
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}

class _EmptyDeck extends StatelessWidget {
  final VoidCallback onClose;
  const _EmptyDeck({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.style_outlined, size: 48, color: Colors.white38),
          const SizedBox(height: 16),
          Text(
            'randomizing_empty'.tr(),
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: onClose,
            child: Text('btn_close'.tr()),
          ),
        ],
      ),
    );
  }
}

// ─── Holographic card ────────────────────────────────────────────────────────

/// A holographic character card mirroring Glaze's `HoloCardViewer`: a parallax
/// portrait under a diagonal rainbow-foil band, a white sheen and a centred
/// glare — all driven purely by the device tilt, with no idle animation (the
/// Vue original uses `transition: none` and only moves on input). [tiltX]/
/// [tiltY] (−1..1) drive the 3D tilt, the band position and the glare opacity.
class HoloCard extends StatelessWidget {
  final Character character;
  final double tiltX;
  final double tiltY;
  final double width;
  final double height;

  const HoloCard({
    super.key,
    required this.character,
    required this.tiltX,
    required this.tiltY,
    required this.width,
    required this.height,
  });

  String get _displayName {
    final dn = character.displayName?.trim();
    return (dn != null && dn.isNotEmpty) ? dn : character.name;
  }

  /// Short blurb shown under the name — the creator's notes when present (the
  /// user-facing tagline), falling back to the character description.
  String? get _shortDescription {
    final notes = character.creatorNotes?.trim();
    if (notes != null && notes.isNotEmpty) return notes;
    final desc = character.description?.trim();
    if (desc != null && desc.isNotEmpty) return desc;
    return null;
  }

  Color get _avatarColor {
    final c = character.color;
    if (c != null) {
      try {
        return Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
      } catch (_) {}
    }
    return const Color(0xFF7996CE);
  }

  @override
  Widget build(BuildContext context) {
    // Purely tilt-driven — no idle animation (that constant sweep was the
    // "jelly" wobble). `pos` (0..1) is where the diagonal light band sits, moved
    // by the left/right tilt only, mirroring the Vue `sheenPos = 50 + xNorm*40`.
    // The glare fades in with the tilt magnitude (`min(1, |x| + |y|*0.5)`).
    final pos = (0.5 + tiltX * 0.34).clamp(0.16, 0.84).toDouble();
    final glareMag = math.min(1.0, tiltX.abs() + tiltY.abs() * 0.5).toDouble();

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1 — Parallax portrait. The overscan gives the parallax shift room to
          // move without exposing the card edge; everything stays clipped below.
          Transform.scale(
            scale: 1.12,
            child: Transform.translate(
              offset: Offset(tiltX * 6, tiltY * 6),
              child: _buildImage(),
            ),
          ),

          // 2 — Rainbow foil, masked to the moving diagonal band so the colour
          // is only ever visible inside the light streak (color-dodge). The band
          // slides along the diagonal as the card is tilted left/right.
          _BlendMask(
            blendMode: BlendMode.colorDodge,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) =>
                  _bandGradient(pos, const Color(0xFFFFFFFF)).createShader(rect),
              child: const _RainbowFoil(),
            ),
          ),

          // 3 — The white light band itself (screen/plus).
          _BlendMask(
            blendMode: BlendMode.plus,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: _bandGradient(pos, const Color(0x40FFFFFF)),
              ),
            ),
          ),

          // 4 — Bottom legibility gradient.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0.0, 0.55, 1.0],
                  colors: [
                    Color(0xF2000000),
                    Color(0x99000000),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 5 — Centred round glare; only its opacity tracks the tilt magnitude,
          // so it reads as a highlight that appears as the card turns to the
          // light (matching the Vue glare fixed at 50% 50%).
          _BlendMask(
            blendMode: BlendMode.plus,
            child: _Glare(opacity: glareMag),
          ),

          // 6 — Inner border frame.
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            bottom: 10,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // 7 — Name / creator / short description, counter-parallaxed.
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Transform.translate(
              offset: Offset(tiltX * 12, tiltY * 12),
              child: _CardInfo(
                name: _displayName,
                creator: character.creator,
                description: _shortDescription,
              ),
            ),
          ),

          // 8 — Tags in the top-left corner, colour-coded like the list cards.
          if (character.tags.isNotEmpty)
            Positioned(
              top: 18,
              left: 18,
              right: 64, // clear the "G" badge
              child: Transform.translate(
                offset: Offset(tiltX * 10, tiltY * 10),
                child: IgnorePointer(
                  child: CardTagChips(tags: character.tags, max: 3),
                ),
              ),
            ),

          // 9 — Top badge: the filled Glaze logo, tinted with the card's accent.
          Positioned(
            top: 18,
            right: 18,
            child: Transform.translate(
              offset: Offset(tiltX * 12, tiltY * 12),
              child: _TopBadge(accent: _avatarColor),
            ),
          ),
        ],
      ),
    );

    // Outer casing + 3D tilt. The rotation is kept gentle so the projected card
    // stays within its footprint; `clipBehavior` trims the 4px frame + holo
    // layers to the rounded casing so nothing bleeds past the corners.
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0011)
        ..rotateX(tiltY * 0.11)
        ..rotateY(tiltX * 0.11),
      child: Container(
        padding: const EdgeInsets.all(4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x26FFFFFF), Color(0x05FFFFFF), Color(0x1AFFFFFF)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 40,
              offset: const Offset(0, 22),
            ),
            BoxShadow(
              color: _avatarColor.withValues(alpha: 0.25),
              blurRadius: 30,
              spreadRadius: -6,
            ),
          ],
        ),
        child: card,
      ),
    );
  }

  Widget _buildImage() {
    final path = resolveGlazeFilePath(character.avatarPath) ??
        resolveGlazeThumbnailPath(character.avatarPath);
    if (path == null) return _placeholder();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: _avatarColor.withValues(alpha: 0.25),
      child: Center(
        child: Text(
          _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w800,
            color: _avatarColor.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

// ─── Holographic sub-layers ──────────────────────────────────────────────────

/// Composites [child] against the layers beneath it using [blendMode]
/// (Flutter's `Stack` normally paints children with `srcOver` only).
class _BlendMask extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;
  const _BlendMask({required this.blendMode, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBlendMask(blendMode);

  @override
  void updateRenderObject(BuildContext context, _RenderBlendMask ro) {
    ro.blendMode = blendMode;
  }
}

class _RenderBlendMask extends RenderProxyBox {
  _RenderBlendMask(this._blendMode);
  BlendMode _blendMode;
  set blendMode(BlendMode v) {
    if (v == _blendMode) return;
    _blendMode = v;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.canvas.saveLayer(offset & size, Paint()..blendMode = _blendMode);
    super.paint(context, offset);
    context.canvas.restore();
  }
}

class _RainbowFoil extends StatelessWidget {
  const _RainbowFoil();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1.4, -1),
          end: Alignment(1.4, 1),
          colors: [
            Color(0x00000000),
            Color(0x33FF3B6B),
            Color(0x33FFD23B),
            Color(0x333BFF9E),
            Color(0x333BC8FF),
            Color(0x33B23BFF),
            Color(0x00000000),
          ],
          stops: [0.0, 0.18, 0.34, 0.5, 0.66, 0.82, 1.0],
        ),
      ),
    );
  }
}

/// A soft diagonal light band centred at [pos] (0..1) along the card diagonal,
/// filled with [color] and fading to fully transparent on both sides (using the
/// same hue at 0 alpha so the fade stays neutral). Used both as the rainbow-foil
/// mask and, filled with translucent white, as the sheen itself.
LinearGradient _bandGradient(double pos, Color color) {
  final c = pos.clamp(0.16, 0.84);
  final edge = color.withValues(alpha: 0);
  return LinearGradient(
    begin: const Alignment(-1, -0.7),
    end: const Alignment(1, 0.7),
    colors: [edge, edge, color, edge, edge],
    stops: [0.0, c - 0.16, c, c + 0.16, 1.0],
  );
}

class _Glare extends StatelessWidget {
  final double opacity;
  const _Glare({required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.75,
            colors: [Color(0xCCFFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)],
            stops: [0.0, 0.2, 0.6],
          ),
        ),
      ),
    );
  }
}

/// Directional wash shown while the top card is dragged toward an action: the
/// half of the screen the card is heading to fills with that button's colour,
/// its strength tracking the drag [progress] (−1 = full skip, +1 = full chat).
class _EdgeTint extends StatelessWidget {
  final double progress;
  final Color chatColor;
  const _EdgeTint({required this.progress, required this.chatColor});

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(-1.0, 1.0);
    if (p == 0) return const SizedBox.shrink();
    final right = p > 0;
    final color = right ? chatColor : const Color(0xFFFF5A6E);
    final strength = p.abs();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: right ? Alignment.centerRight : Alignment.centerLeft,
          end: Alignment.center,
          colors: [
            color.withValues(alpha: 0.5 * strength),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _TopBadge extends StatelessWidget {
  /// The card's accent colour (derived from the character), used to tint the
  /// logo. Lightened a touch so it stays legible on the dark badge.
  final Color accent;
  const _TopBadge({required this.accent});

  @override
  Widget build(BuildContext context) {
    final tint = Color.lerp(accent, Colors.white, 0.25)!;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SvgPicture.string(
          glazeFilledLogoSvg,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
        ),
      ),
    );
  }
}

class _CardInfo extends StatelessWidget {
  final String name;
  final String? creator;
  final String? description;
  const _CardInfo({required this.name, this.creator, this.description});

  @override
  Widget build(BuildContext context) {
    final desc = description?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Metallic gradient name, uppercase, à la Holocard.
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFDADADA),
              Color(0xFFFFFFFF),
              Color(0xFFCFCFCF),
            ],
            stops: [0.0, 0.35, 0.65, 1.0],
          ).createShader(bounds),
          child: Text(
            name.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              height: 1.05,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 6, color: Color(0xCC000000))],
            ),
          ),
        ),
        if (creator != null && creator!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '@${creator!}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
              shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
            ),
          ),
        ],
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            desc,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              color: Colors.white.withValues(alpha: 0.82),
              shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
            ),
          ),
        ],
      ],
    );
  }
}

