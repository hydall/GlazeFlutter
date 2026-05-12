import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PencilAnimation extends StatefulWidget {
  final double size;
  final Color? color;

  const PencilAnimation({super.key, this.size = 16, this.color});

  @override
  State<PencilAnimation> createState() => _PencilAnimationState();
}

class _PencilAnimationState extends State<PencilAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _moveAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      // Match the 1.5s from Vue's animation: pencil-write 1.5s infinite ease-in-out;
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    // Replicating the pencil-write translateX steps:
    // 0% -> 0
    // 15% -> 1px
    // 30% -> 2px
    // 45% -> 3px
    // 60% -> 4px
    // 75% -> 5px
    // 100% -> 0
    _moveAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 2.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 2.0, end: 3.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 3.0, end: 4.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: 5.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 5.0, end: 0.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_moveAnimation.value, 0),
          child: Icon(
            Icons.edit,
            size: widget.size,
            color: widget.color ?? context.cs.primary,
          ),
        );
      },
    );
  }
}
