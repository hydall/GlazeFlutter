import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/glass_nav_bar.dart';
import '../widgets/glaze_background.dart';
import '../widgets/glaze_scaffold.dart' show GlazeAppBar;
import '../widgets/glaze_toast.dart';
import 'shell_header_provider.dart';

class ShellScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const ShellScreen({super.key, required this.navigationShell});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  int _currentIndex = 0;
  int _lastBackPress = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.navigationShell.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(ShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationShell.currentIndex != _currentIndex) {
      _currentIndex = widget.navigationShell.currentIndex;
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
    final currentIndex = widget.navigationShell.currentIndex;
    final location = GoRouterState.of(context).uri.toString();
    final isIosLikeTargetPlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final hideNavBarRoutes = <String>{
      '/menu/about',
    };
    final showNavBar = currentIndex < 4 && !hideNavBarRoutes.contains(location);
    return GlazeBackground(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (isIosLikeTargetPlatform) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastBackPress < 2000) {
            SystemNavigator.pop();
          } else {
            _lastBackPress = now;
            GlazeToast.show(context, 'nav_press_again_to_exit'.tr());
          }
        },
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: FadeTransition(
                  opacity: _fade,
                  child: widget.navigationShell,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _PersistentHeader(branchIndex: currentIndex),
              ),
            ],
          ),
          bottomNavigationBar: showNavBar
              ? GlassNavBar(
                  currentIndex: currentIndex,
                  onTap: (index) => widget.navigationShell.goBranch(
                    index,
                    initialLocation: index == currentIndex,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// The shell's single persistent header. Stays mounted across tab switches and
/// pushed sub-screens; only its content cross-fades, driven by whichever screen
/// of [branchIndex] currently owns the header (see [shellHeaderProvider]).
class _PersistentHeader extends ConsumerWidget {
  final int branchIndex;
  const _PersistentHeader({required this.branchIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(
      shellHeaderProvider.select((e) => resolveShellHeader(e, branchIndex)),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: entry == null || entry.config.hidden
          ? const SizedBox.shrink(key: ValueKey('shell-header-empty'))
          : KeyedSubtree(
              key: ObjectKey(entry.key),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlazeAppBar(
                        title: entry.config.title,
                        titleWidget: entry.config.titleWidget,
                        actions: entry.config.actions,
                        showBack: entry.config.showBack,
                        onBack: entry.config.onBack,
                      ),
                      if (entry.config.below != null) entry.config.below!,
                    ],
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
    final involved = isCurrent || isPrevious;

    final opacity = isCurrent ? t : (isPrevious ? (1.0 - t) : 0.0);

    // Detach the branch (state is preserved by the shell) when it is not part
    // of the active cross-fade, or once the outgoing branch's fade-out has
    // fully settled. Detaching only after the animation completes — from an
    // already-faded state — avoids a one-frame full-opacity blink of native
    // platform views (the chat WebView) that snapping to Offstage mid-fade
    // produced.
    final offstage = !involved || (isPrevious && !animating);

    // A single, stable widget structure for every state (only the booleans
    // change) so the InAppWebView element is never re-parented as a branch
    // moves between idle / fading / detached — re-parenting re-attaches the
    // native surface and flashes a stale frame.
    return IgnorePointer(
      ignoring: !isCurrent || animating,
      child: Offstage(
        offstage: offstage,
        child: TickerMode(
          enabled: involved,
          child: Opacity(opacity: opacity, child: child),
        ),
      ),
    );
  }
}
