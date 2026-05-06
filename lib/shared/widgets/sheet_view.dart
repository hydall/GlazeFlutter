import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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

class SheetView extends StatelessWidget {
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
  final FloatingActionButton? floatingActionButton;
  final bool showHandle;
  final EdgeInsetsGeometry? bodyPadding;

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
  });

  bool get _hasHeader =>
      title != null ||
      titleWidget != null ||
      showBack ||
      actions.isNotEmpty ||
      tabs.isNotEmpty ||
      headerBottom != null ||
      showHandle;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (_hasHeader) _SheetViewHeader(
          title: title,
          titleWidget: titleWidget,
          showBack: showBack,
          onBack: onBack,
          actions: actions,
          tabs: tabs,
          activeTabId: activeTabId,
          onTabSelected: onTabSelected,
          headerBottom: headerBottom,
          showHandle: showHandle,
        ),
        Expanded(
          child: Padding(
            padding: bodyPadding ?? EdgeInsets.zero,
            child: body,
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          Positioned.fill(child: content),
          if (floating != null) Positioned.fill(child: floating!),
        ],
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
  });

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: safeTop),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE619191A), Color(0x0019191A)],
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHandle)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
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
                                  foregroundColor:
                                      action.color ?? AppColors.accent,
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
        ),
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

    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class _SheetTabButton extends StatelessWidget {
  final SheetViewTab tab;
  final bool active;
  final VoidCallback? onTap;

  const _SheetTabButton({
    required this.tab,
    required this.active,
    this.onTap,
  });

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
