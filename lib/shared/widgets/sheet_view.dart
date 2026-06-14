import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../shell/nav_height_provider.dart';
import '../shell/shell_header_provider.dart';
import '../../features/settings/app_settings_provider.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';
import 'glaze_background.dart';
import 'glaze_scaffold.dart';

class SheetViewAction {
  final Widget icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;

  const SheetViewAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });
}

class SheetViewTab {
  final String id;
  final String label;
  final IconData? icon;

  const SheetViewTab({required this.id, required this.label, this.icon});
}

/// Draggable bottom-sheet container.
///
/// Use [showModalBottomSheet] with [isScrollControlled: true] and
/// [backgroundColor: Colors.transparent] to present this widget.
/// It manages its own height: collapsed (~55 % of screen) or expanded
/// (full screen), with a swipe gesture and snap animation.
class SheetView extends ConsumerStatefulWidget {
  final String? title;
  final Widget? titleWidget;
  final bool showBack;
  final VoidCallback? onBack;
  final List<SheetViewAction> actions;
  final List<SheetViewTab> tabs;
  final String? activeTabId;
  final ValueChanged<String>? onTabSelected;
  final Widget? headerBottom;
  final Widget body;
  final Widget? floating;
  final Widget? floatingActionButton;
  final bool showHandle;
  final EdgeInsetsGeometry? bodyPadding;
  final bool startExpanded;
  final ScrollController? scrollController;

  /// Fraction of screen height for the collapsed snap point (0.0–1.0).
  /// When null, defaults to `min(0.55 * h, 500)`.
  final double? collapsedFraction;
  final bool fitContent;
  final bool showRouteBackground;

  const SheetView({
    super.key,
    this.title,
    this.titleWidget,
    this.showBack = false,
    this.onBack,
    this.actions = const [],
    this.tabs = const [],
    this.activeTabId,
    this.onTabSelected,
    this.headerBottom,
    required this.body,
    this.floating,
    this.floatingActionButton,
    this.showHandle = true,
    this.bodyPadding,
    this.startExpanded = false,
    this.scrollController,
    this.collapsedFraction,
    this.fitContent = false,
    this.showRouteBackground = true,
  });

  @override
  ConsumerState<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends ConsumerState<SheetView>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  double _currentHeight = 0;
  bool _heightInit = false;

  /// Fallback controller used when [SheetView.scrollController] is null.
  /// Ensures the [RawScrollbar] always has a valid controller attached,
  /// even if the child [Scrollable] uses [PrimaryScrollController] or its own.
  late final ScrollController _fallbackScrollController = ScrollController();

  /// Whether this SheetView is hosted inside [showModalBottomSheet]. When
  /// false (e.g. opened as a route via GoRouter), we behave as a regular
  /// fullscreen page: no drag handle, no resize, no drag-down dismiss.
  bool _inModalSheet = true;

  /// Branch whose persistent shell header this sheet is currently suppressing
  /// (only when presented as a fullscreen route, not a modal bottom sheet).
  int? _suppressedBranch;

  /// Cached so it can be used safely in [dispose].
  ShellHeaderRegistry? _headerRegistry;

  bool _keyboardOpen = false;
  bool _wasExpandedBeforeKeyboard = false;

  /// True while the user is dragging the sheet. Combined with an active snap
  /// animation, this drops the expensive backdrop + soft-edge blur passes for
  /// the duration of the motion so the drag stays at framerate. The blur is
  /// restored the moment the sheet settles.
  bool _dragging = false;
  bool get _interacting => _dragging || _ctrl.isAnimating;

  late AnimationController _ctrl;
  Animation<double>? _anim;

  final _headerKey = GlobalKey();
  double _headerH = 0;

  double _dragStartY = 0;
  double _dragStartH = 0;

  bool get _effectiveShowHandle => widget.showHandle && _inModalSheet;

  double _collapsed(BuildContext ctx) {
    final h = MediaQuery.of(ctx).size.height;
    if (!_inModalSheet) return h;
    final f = widget.collapsedFraction;
    if (f != null) return h * f.clamp(0.0, 1.0);
    return h * 0.85;
  }

  double _full(BuildContext ctx) => MediaQuery.of(ctx).size.height;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    // Restore the blur once a snap animation finishes (the per-tick setState in
    // _onTick handles the frames during the animation itself).
    _ctrl.addStatusListener(_onAnimStatus);
    _headerH = _estimateHeaderHeight();
  }

  double _estimateHeaderHeight() {
    if (!_hasHeader) {
      return 0;
    }
    double h = 0;
    if (_effectiveShowHandle) {
      h += 24;
    }
    if (widget.title != null ||
        widget.titleWidget != null ||
        widget.showBack ||
        widget.actions.isNotEmpty) {
      h += _inModalSheet ? 52 : 56;
    }
    if (widget.tabs.isNotEmpty) {
      h += 46;
    }
    if (widget.headerBottom != null) {
      h += 52;
    }
    return h;
  }

  void _measureHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return;
      }
      final h = box.size.height;
      if (h != _headerH) {
        setState(() => _headerH = h);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inModalSheet = ModalRoute.of(context) is ModalBottomSheetRoute;
    _syncHeaderSuppression();
    if (!_heightInit) {
      _currentHeight = (widget.startExpanded || !_inModalSheet)
          ? _full(context)
          : _collapsed(context);
      _expanded = widget.startExpanded || !_inModalSheet;
      _heightInit = true;
    }
  }

  /// When presented as a fullscreen route (not a modal bottom sheet), this
  /// sheet draws its own header, so it suppresses the shell's persistent header
  /// for the branch it lives in. A modal bottom sheet leaves the host screen's
  /// header visible behind it and must not suppress.
  void _syncHeaderSuppression() {
    final branch = _inModalSheet
        ? null
        : shellBranchForLocation(
            GoRouterState.of(context).uri.toString(),
          );
    if (branch == _suppressedBranch) return;
    _headerRegistry ??= ref.read(shellHeaderProvider.notifier);
    final notifier = _headerRegistry!;
    _suppressedBranch = branch;
    // Deferred: didChangeDependencies runs during the build phase, where
    // modifying a provider is forbidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (branch == null) {
        notifier.remove(this);
      } else if (mounted && _suppressedBranch == branch) {
        notifier.publish(this, branch, const ShellHeaderConfig(hidden: true));
      }
    });
  }

  @override
  void dispose() {
    final registry = _headerRegistry;
    if (registry != null && _suppressedBranch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => registry.remove(this));
    }
    _anim?.removeListener(_onTick);
    _ctrl.removeStatusListener(_onAnimStatus);
    _ctrl.dispose();
    _fallbackScrollController.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.fitContent) return;
    final target = _expanded ? _collapsed(context) : _full(context);
    _animateTo(target, expanding: !_expanded);
  }

  void _animateTo(double target, {required bool expanding}) {
    final start = _currentHeight;
    _anim?.removeListener(_onTick);
    _anim = Tween(begin: start, end: target).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    )..addListener(_onTick);
    _ctrl.forward(from: 0);
    setState(() => _expanded = expanding);
  }

  void _onTick() => setState(() => _currentHeight = _anim!.value);

  void _onAnimStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      // Force a rebuild so _interacting flips back to false and the blur paints.
      setState(() {});
    }
  }

  void _onDragStart(DragStartDetails d) {
    _ctrl.stop();
    _anim?.removeListener(_onTick);
    _dragStartY = d.globalPosition.dy;
    _dragStartH = _currentHeight;
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final dy = d.globalPosition.dy - _dragStartY;
    final minHeight = _collapsed(context) * 0.3;
    final h = (_dragStartH - dy).clamp(
      minHeight,
      widget.fitContent ? _collapsed(context) : _full(context),
    );
    setState(() => _currentHeight = h);
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    final vy = d.velocity.pixelsPerSecond.dy;
    final collapsed = _collapsed(context);
    final full = _full(context);
    final mid = (collapsed + full) / 2;

    if (widget.fitContent) {
      if (vy > 600 || _currentHeight < collapsed * 0.6) {
        Navigator.of(context).maybePop();
      } else {
        _animateTo(collapsed, expanding: false);
      }
      return;
    }

    if (vy < -600 || (_currentHeight > mid && vy <= 600)) {
      _animateTo(full, expanding: true);
    } else if (vy > 600 || _currentHeight < collapsed * 0.6) {
      Navigator.of(context).maybePop();
    } else {
      _animateTo(
        _currentHeight >= mid ? full : collapsed,
        expanding: _currentHeight >= mid,
      );
    }
  }

  bool get _hasHeader =>
      widget.title != null ||
      widget.titleWidget != null ||
      widget.showBack ||
      widget.actions.isNotEmpty ||
      widget.tabs.isNotEmpty ||
      widget.headerBottom != null ||
      _effectiveShowHandle;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final batterySaver =
        ref.watch(appSettingsProvider).value?.batterySaver ?? false;
    final isKeyboardOpen = bottomInset > 0;

    if (isKeyboardOpen != _keyboardOpen) {
      _keyboardOpen = isKeyboardOpen;
      if (isKeyboardOpen) {
        if (!_expanded && !widget.fitContent) {
          _wasExpandedBeforeKeyboard = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_expanded) {
              _animateTo(_full(context), expanding: true);
            }
          });
        } else {
          _wasExpandedBeforeKeyboard = true;
        }
      } else {
        if (!_wasExpandedBeforeKeyboard) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _expanded) {
              _animateTo(_collapsed(context), expanding: false);
            }
          });
        }
      }
    }

    if (!_inModalSheet) {
      if (_hasHeader) {
        _measureHeader();
      }

      final backHandler =
          widget.onBack ?? () => Navigator.of(context).maybePop();
      // When the sheet is rendered as a page route inside the Shell, the
      // GlassNavBar overlaps the body (Shell uses extendBody: true). Inject
      // its measured height into MediaQuery.padding.bottom so the body's
      // ListView can pick it up the same way it consumes paddingOf(...).top.
      // navHeight already includes the system safe-area inset (the nav bar
      // pads its own bottom by 16 + bottomPad), so use max() — not addition —
      // to avoid double-counting the inset on screens outside the Shell.
      final navHeight = ref.watch(navHeightProvider);

      final routeScaffold = Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(
              child: Builder(
                builder: (context) {
                  final mediaQuery = MediaQuery.of(context);
                  final extraTop = _hasHeader
                      ? (mediaQuery.padding.top + 10 + _headerH)
                      : mediaQuery.padding.top;
                  final newPadding = mediaQuery.padding.copyWith(
                    top: extraTop,
                    bottom: navHeight > mediaQuery.padding.bottom
                        ? navHeight
                        : mediaQuery.padding.bottom,
                  );

                  final innerChild = Padding(
                    padding: widget.bodyPadding ?? EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: isKeyboardOpen ? bottomInset + 10 : 0,
                      ),
                      child: widget.body,
                    ),
                  );

                  return MediaQuery(
                    data: mediaQuery.copyWith(padding: newPadding),
                    child: _MaybeScrollbar(
                      controller:
                          widget.scrollController ?? _fallbackScrollController,
                      child: innerChild,
                    ),
                  );
                },
              ),
            ),
            if (_hasHeader)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: KeyedSubtree(
                      key: _headerKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlazeAppBar(
                            title: widget.title,
                            titleWidget: widget.titleWidget,
                            showBack: widget.showBack,
                            onBack: widget.onBack,
                            actions: widget.actions.map((action) {
                              return _HeaderIconButton(
                                onPressed: action.onPressed,
                                tooltip: action.tooltip,
                                foregroundColor:
                                    action.color ?? context.cs.primary,
                                child: action.icon,
                              );
                            }).toList(),
                          ),
                          if (widget.tabs.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: widget.tabs
                                    .map(
                                      (tab) => Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: _SheetTabButton(
                                            tab: tab,
                                            active:
                                                widget.activeTabId == tab.id,
                                            onTap: widget.onTabSelected == null
                                                ? null
                                                : () => widget.onTabSelected!(
                                                    tab.id,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          if (widget.headerBottom != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: widget.headerBottom!,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.floating != null)
              Positioned.fill(child: widget.floating!),
            if (widget.floatingActionButton != null)
              Positioned(
                right: 16,
                bottom:
                    16 + MediaQuery.of(context).padding.bottom + bottomInset,
                child: widget.floatingActionButton!,
              ),
          ],
        ),
      );

      return PopScope(
        canPop: !widget.showBack,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          backHandler();
        },
        child: widget.showRouteBackground
            ? GlazeBackground(child: routeScaffold)
            : routeScaffold,
      );
    }

    final collapsed = _collapsed(context);
    final full = _full(context);
    final t = full > collapsed
        ? ((_currentHeight - collapsed) / (full - collapsed)).clamp(0.0, 1.0)
        : 0.0;
    final radius = 20.0 * (1.0 - t);
    final realTopPadding = MediaQueryData.fromView(
      View.of(context),
    ).padding.top;
    final topPad = realTopPadding * t;

    if (_hasHeader) {
      _measureHeader();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.fitContent ? _full(context) * 0.95 : double.infinity,
      ),
      child: SizedBox(
        height: widget.fitContent ? null : _currentHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
          // The primary backdrop blur stays live even during the drag (CSS
          // backdrop-filter parity). The frame cost is kept affordable by
          // dropping the *second* blur pass (SoftEdgeBlur) and isolating the
          // body repaint while interacting — see _buildBodyChild / _interacting.
          child: batterySaver
              ? _sheetContent(
                  context,
                  topPad,
                  bottomInset,
                  radius,
                  opaque: true,
                )
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: _sheetContent(context, topPad, bottomInset, radius),
                ),
        ),
      ),
    );
  }

  Widget _sheetContent(
    BuildContext context,
    double topPad,
    double bottomInset,
    double radius, {
    bool opaque = false,
  }) {
    final isKeyboardOpen = _keyboardOpen;
    return Container(
      color: context.cs.surface.withValues(alpha: opaque ? 1.0 : 0.8),
      child: Stack(
        children: [
          widget.fitContent
              ? _buildBodyChild(context, topPad, bottomInset, isKeyboardOpen)
              : Positioned.fill(
                  child: _buildBodyChild(
                    context,
                    topPad,
                    bottomInset,
                    isKeyboardOpen,
                  ),
                ),

          // Interactive header — rendered above the gradient so buttons
          // and drag handle are unobscured and fully hittable.
          if (_hasHeader)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: KeyedSubtree(
                key: _headerKey,
                child: _SheetViewHeader(
                  title: widget.title,
                  titleWidget: widget.titleWidget,
                  showBack: widget.showBack,
                  onBack: widget.onBack,
                  actions: widget.actions,
                  tabs: widget.tabs,
                  activeTabId: widget.activeTabId,
                  onTabSelected: widget.onTabSelected,
                  headerBottom: widget.headerBottom,
                  showHandle: _effectiveShowHandle,
                  expanded: _expanded,
                  topPad: topPad,
                  onHandleTap: _toggle,
                  onDragStart: widget.fitContent ? null : _onDragStart,
                  onDragUpdate: widget.fitContent ? null : _onDragUpdate,
                  onDragEnd: widget.fitContent ? null : _onDragEnd,
                ),
              ),
            ),
          if (widget.floating != null) Positioned.fill(child: widget.floating!),
          if (widget.floatingActionButton != null)
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom + bottomInset,
              child: widget.floatingActionButton!,
            ),
        ],
      ),
    );
  }

  Widget _buildBodyChild(
    BuildContext context,
    double topPad,
    double bottomInset,
    bool isKeyboardOpen,
  ) {
    return (_hasHeader &&
            !_interacting &&
            !(ref.watch(appSettingsProvider).value?.batterySaver ?? false))
        ? SoftEdgeBlur(
            edges: [
              EdgeBlur(
                type: EdgeType.topEdge,
                size: _headerH + 8,
                sigma: 24,
                tintColor: context.cs.surface.withValues(alpha: 0.4),
                controlPoints: [
                  ControlPoint(position: 0.5, type: ControlPointType.visible),
                  ControlPoint(
                    position: 1.0,
                    type: ControlPointType.transparent,
                  ),
                ],
              ),
            ],
            child: _buildScrollConfig(
              context,
              topPad,
              bottomInset,
              isKeyboardOpen,
            ),
          )
        : _buildScrollConfig(context, topPad, bottomInset, isKeyboardOpen);
  }

  Widget _buildScrollConfig(
    BuildContext context,
    double topPad,
    double bottomInset,
    bool isKeyboardOpen,
  ) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Builder(
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          final extraTop = _hasHeader ? _headerH : topPad;
          final newPadding = mediaQuery.padding.copyWith(top: extraTop);

          final safeBottom = widget.fitContent
              ? mediaQuery.padding.bottom
              : 0.0;
          final innerChild = Padding(
            padding: widget.bodyPadding ?? EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isKeyboardOpen ? bottomInset + 10 : safeBottom,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: widget.fitContent ? 1.0 : null,
                child: RepaintBoundary(
                  child: SizedBox(width: double.infinity, child: widget.body),
                ),
              ),
            ),
          );

          return MediaQuery(
            data: mediaQuery.copyWith(padding: newPadding),
            child: _MaybeScrollbar(
              controller: widget.scrollController ?? _fallbackScrollController,
              child: innerChild,
            ),
          );
        },
      ),
    );
  }
}

class _SheetViewHeader extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final bool showBack;
  final VoidCallback? onBack;
  final List<SheetViewAction> actions;
  final List<SheetViewTab> tabs;
  final String? activeTabId;
  final ValueChanged<String>? onTabSelected;
  final Widget? headerBottom;
  final bool showHandle;
  final bool expanded;
  final double topPad;
  final VoidCallback onHandleTap;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  const _SheetViewHeader({
    this.title,
    this.titleWidget,
    required this.showBack,
    this.onBack,
    required this.actions,
    required this.tabs,
    this.activeTabId,
    this.onTabSelected,
    this.headerBottom,
    required this.showHandle,
    required this.expanded,
    required this.topPad,
    required this.onHandleTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHandle)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onHandleTap,
              onVerticalDragStart: onDragStart,
              onVerticalDragUpdate: onDragUpdate,
              onVerticalDragEnd: onDragEnd,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: expanded ? 24.0 : 36.0,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: expanded ? 0.6 : 0.35,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (title != null ||
              titleWidget != null ||
              showBack ||
              actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  if (showBack)
                    _HeaderIconButton(
                      onPressed:
                          onBack ?? () => Navigator.of(context).maybePop(),
                      child: Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: context.cs.primary,
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                  const SizedBox(width: 8),
                  Expanded(
                    child:
                        titleWidget ??
                        (title != null
                            ? Text(
                                title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.cs.onSurface,
                                ),
                              )
                            : const SizedBox.shrink()),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions
                        .map(
                          (action) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _HeaderIconButton(
                              tooltip: action.tooltip,
                              onPressed: action.onPressed,
                              foregroundColor:
                                  action.color ?? context.cs.primary,
                              child: action.icon,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          if (tabs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: tabs
                    .map(
                      (tab) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _SheetTabButton(
                            tab: tab,
                            active: activeTabId == tab.id,
                            onTap: onTabSelected == null
                                ? null
                                : () => onTabSelected!(tab.id),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (headerBottom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: headerBottom!,
            ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? foregroundColor;

  const _HeaderIconButton({
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? context.cs.primary;
    final button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: IconTheme(
            data: IconThemeData(color: fg),
            child: DefaultTextStyle(
              style: TextStyle(color: fg),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _SheetTabButton extends StatelessWidget {
  final SheetViewTab tab;
  final bool active;
  final VoidCallback? onTap;

  const _SheetTabButton({required this.tab, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    final foreground = active
        ? context.cs.primary
        : context.cs.onSurfaceVariant;
    return Material(
      color: active
          ? context.cs.primary.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? context.cs.primary.withValues(alpha: 0.28)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (tab.icon != null) ...[
                Icon(tab.icon, size: 18, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] in a [RawScrollbar] with a persistent thumb, but only
/// when the subtree actually contains a [Scrollable] using the same
/// [controller]. If the child has no matching scrollable (e.g. a static
/// placeholder while async data is loading), the bar is omitted to avoid
/// Flutter's "no ScrollPosition attached" assertion in debug builds.
class _MaybeScrollbar extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  const _MaybeScrollbar({required this.controller, required this.child});

  @override
  State<_MaybeScrollbar> createState() => _MaybeScrollbarState();
}

class _MaybeScrollbarState extends State<_MaybeScrollbar> {
  bool _hasAttached = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _MaybeScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() => _sync();

  void _sync() {
    final has = widget.controller.hasClients;
    if (has != _hasAttached) {
      if (mounted) setState(() => _hasAttached = has);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAttached) return widget.child;
    return RawScrollbar(
      controller: widget.controller,
      thumbVisibility: true,
      thickness: 6,
      radius: const Radius.circular(3),
      child: widget.child,
    );
  }
}
