import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gradient_blur/gradient_blur.dart';

import '../theme/app_colors.dart';
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
class SheetView extends StatefulWidget {
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
  });

  @override
  State<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<SheetView>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  double _currentHeight = 0;
  bool _heightInit = false;

  /// Whether this SheetView is hosted inside [showModalBottomSheet]. When
  /// false (e.g. opened as a route via GoRouter), we behave as a regular
  /// fullscreen page: no drag handle, no resize, no drag-down dismiss.
  bool _inModalSheet = true;

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
    return math.min(h * 0.55, 500.0);
  }

  double _full(BuildContext ctx) => MediaQuery.of(ctx).size.height;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
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
    if (!_heightInit) {
      _currentHeight = (widget.startExpanded || !_inModalSheet)
          ? _full(context)
          : _collapsed(context);
      _expanded = widget.startExpanded || !_inModalSheet;
      _heightInit = true;
    }
  }

  @override
  void dispose() {
    _anim?.removeListener(_onTick);
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
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

  void _onDragStart(DragStartDetails d) {
    _ctrl.stop();
    _anim?.removeListener(_onTick);
    _dragStartY = d.globalPosition.dy;
    _dragStartH = _currentHeight;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final dy = d.globalPosition.dy - _dragStartY;
    final h = (_dragStartH - dy).clamp(
      _collapsed(context) * 0.3,
      _full(context),
    );
    setState(() => _currentHeight = h);
  }

  void _onDragEnd(DragEndDetails d) {
    final vy = d.velocity.pixelsPerSecond.dy;
    final collapsed = _collapsed(context);
    final full = _full(context);
    final mid = (collapsed + full) / 2;

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
    if (!_inModalSheet) {
      if (_hasHeader) {
        _measureHeader();
      }

      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: Builder(
                builder: (context) {
                  final mediaQuery = MediaQuery.of(context);
                  final extraTop = _hasHeader ? (mediaQuery.padding.top + 10 + _headerH) : mediaQuery.padding.top;
                  final newPadding = mediaQuery.padding.copyWith(top: extraTop);
                  
                  final innerChild = Padding(
                    padding: widget.bodyPadding ?? EdgeInsets.zero,
                    child: widget.body,
                  );

                  return MediaQuery(
                    data: mediaQuery.copyWith(padding: newPadding),
                    child: widget.scrollController != null
                        ? RawScrollbar(
                            controller: widget.scrollController,
                            thumbColor: Colors.white.withValues(alpha: 0.15),
                            radius: const Radius.circular(3),
                            thickness: 4,
                            padding: EdgeInsets.only(top: extraTop, right: 3),
                            child: innerChild,
                          )
                        : innerChild,
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
                                foregroundColor: action.color ?? AppColors.accent,
                                child: action.icon,
                              );
                            }).toList(),
                          ),
                          if (widget.tabs.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: widget.tabs.map((tab) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: _SheetTabButton(
                                      tab: tab,
                                      active: widget.activeTabId == tab.id,
                                      onTap: widget.onTabSelected == null ? null : () => widget.onTabSelected!(tab.id),
                                    ),
                                  ),
                                )).toList(),
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
                bottom: 16 + MediaQuery.of(context).padding.bottom,
                child: widget.floatingActionButton!,
              ),
          ],
        ),
      );
    }

    final collapsed = _collapsed(context);
    final full = _full(context);
    final t = full > collapsed
        ? ((_currentHeight - collapsed) / (full - collapsed)).clamp(0.0, 1.0)
        : 0.0;
    final radius = 20.0 * (1.0 - t);
    final topPad = MediaQuery.of(context).padding.top * t;

    if (_hasHeader) {
      _measureHeader();
    }

    return SizedBox(
      height: _currentHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: AppColors.background.withValues(alpha: 0.8),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: Builder(
                      builder: (context) {
                        final mediaQuery = MediaQuery.of(context);
                        final extraTop = _hasHeader ? _headerH : topPad;
                        final newPadding = mediaQuery.padding.copyWith(
                          top: extraTop,
                        );

                        final innerChild = Padding(
                          padding: widget.bodyPadding ?? EdgeInsets.zero,
                          child: widget.body,
                        );

                        return MediaQuery(
                          data: mediaQuery.copyWith(padding: newPadding),
                          child: widget.scrollController != null
                              ? RawScrollbar(
                                  controller: widget.scrollController,
                                  thumbColor: Colors.white.withValues(
                                    alpha: 0.15,
                                  ),
                                  radius: const Radius.circular(3),
                                  thickness: 4,
                                  padding: EdgeInsets.only(
                                    top: extraTop,
                                    right: 3,
                                  ),
                                  child: innerChild,
                                )
                              : innerChild,
                        );
                      },
                    ),
                  ),
                ),
                // Gradient blur overlay — IgnorePointer so touches pass through
                // to the header layer above. Extends slightly past the header to
                // fade body content in as the user scrolls.
                if (_hasHeader)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: GradientBlur(
                        maxBlur: 8,
                        curve: Curves.easeIn,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xEB141416),
                            Color(0x88141416),
                            Color(0x00141416),
                          ],
                          stops: [0.0, 0.4, 0.85],
                        ),
                        child: SizedBox(height: _headerH + 8),
                      ),
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
                        onDragStart: _onDragStart,
                        onDragUpdate: _onDragUpdate,
                        onDragEnd: _onDragEnd,
                      ),
                    ),
                  ),
                if (widget.floating != null)
                  Positioned.fill(child: widget.floating!),
                if (widget.floatingActionButton != null)
                  Positioned(
                    right: 16,
                    bottom: 16 + MediaQuery.of(context).padding.bottom,
                    child: widget.floatingActionButton!,
                  ),
              ],
            ),
          ),
        ),
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
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

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
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
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
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: AppColors.accent,
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
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
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
                              foregroundColor: action.color ?? AppColors.accent,
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
  final Color foregroundColor;

  const _HeaderIconButton({
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.foregroundColor = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withValues(alpha: 0.06),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: IconTheme(
            data: IconThemeData(color: foregroundColor),
            child: DefaultTextStyle(
              style: TextStyle(color: foregroundColor),
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
    final foreground = active ? AppColors.accent : AppColors.textSecondary;
    return Material(
      color: active
          ? AppColors.accent.withValues(alpha: 0.12)
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
                  ? AppColors.accent.withValues(alpha: 0.28)
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
