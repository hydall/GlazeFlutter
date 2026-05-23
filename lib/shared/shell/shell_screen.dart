import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../widgets/glass_nav_bar.dart';
import '../widgets/glaze_background.dart';
import '../widgets/glaze_toast.dart';

class ShellScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const ShellScreen({super.key, required this.navigationShell});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _lastBackPress = 0;

  @override
  Widget build(BuildContext context) {
    return GlazeBackground(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastBackPress < 2000) {
            SystemNavigator.pop();
          } else {
            _lastBackPress = now;
            GlazeToast.show(context, 'Press again to exit');
          }
        },
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          body: widget.navigationShell,
          bottomNavigationBar: GlassNavBar(
            currentIndex: widget.navigationShell.currentIndex,
            onTap: (index) => widget.navigationShell.goBranch(
              index,
              initialLocation: index == widget.navigationShell.currentIndex,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cross-fade branch container, ported from the Vue `<Transition name="fade">`
/// used in `src/App.vue`. While switching branches both old and new are
/// visible — old fades 1 → 0 and new fades 0 → 1 simultaneously over 200ms
/// with a CSS `ease` curve.
class FadeBranchContainer extends StatefulWidget {
  final int currentIndex;
  final List<Widget> children;

  const FadeBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  @override
  State<FadeBranchContainer> createState() => _FadeBranchContainerState();
}

class _FadeBranchContainerState extends State<FadeBranchContainer>
    with SingleTickerProviderStateMixin {
  // CSS `ease` ≈ cubic-bezier(0.25, 0.1, 0.25, 1.0)
  static const _curve = Cubic(0.25, 0.1, 0.25, 1.0);
  static const _duration = Duration(milliseconds: 200);

  late final AnimationController _controller;
  late int _displayIndex;
  late int _previousIndex;

  @override
  void initState() {
    super.initState();
    _displayIndex = widget.currentIndex;
    _previousIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(FadeBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != _displayIndex) {
      _previousIndex = _displayIndex;
      _displayIndex = widget.currentIndex;
      _controller.forward(from: 0.0);
    }
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
      builder: (context, _) {
        final t = _curve.transform(_controller.value);
        final animating = _controller.status == AnimationStatus.forward;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (int i = 0; i < widget.children.length; i++)
              _buildBranch(i, widget.children[i], t, animating),
          ],
        );
      },
    );
  }

  Widget _buildBranch(int i, Widget child, double t, bool animating) {
    final isCurrent = i == _displayIndex;
    final isPrevious = i == _previousIndex && _previousIndex != _displayIndex;

    // Keep all branches in the tree (state preservation) but only paint
    // those involved in the current cross-fade.
    if (!isCurrent && !isPrevious) {
      return Offstage(
        offstage: true,
        child: TickerMode(enabled: false, child: child),
      );
    }

    final opacity = isCurrent ? t : (1.0 - t);

    return IgnorePointer(
      ignoring: !isCurrent || animating,
      child: Opacity(opacity: opacity, child: child),
    );
  }
}
