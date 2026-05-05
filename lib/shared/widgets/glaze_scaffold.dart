import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Scaffold with a floating glassmorphic header — use for screens OUTSIDE
/// the shell (character editor, chat screen, etc.) that need a back button.
///
/// Screens inside the shell (history, character list, menu) build their own
/// header inline in their body since they share the shell's bottom nav.
class GlazeScaffold extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;
  final bool extendBodyBehindHeader;

  const GlazeScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.body,
    this.actions,
    this.showBack = true,
    this.onBack,
    this.extendBodyBehindHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final header = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: GlazeAppBar(
          title: title,
          titleWidget: titleWidget,
          actions: actions,
          showBack: showBack,
          onBack: onBack ?? () => Navigator.of(context).maybePop(),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: extendBodyBehindHeader
          ? Stack(
              children: [
                Positioned.fill(child: body),
                Positioned(top: 0, left: 0, right: 0, child: header),
              ],
            )
          : Column(
              children: [
                header,
                Expanded(child: body),
              ],
            ),
    );
  }
}

/// Standalone floating glassmorphic app bar — use this directly when you
/// need to embed the header inside a body Column (e.g. shell-tab screens).
class GlazeAppBar extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;

  /// Optional custom left widget (shown when showBack is false).
  /// Defaults to the Glaze logo mark.
  final Widget? leading;

  const GlazeAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.showBack = false,
    this.onBack,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              // Left: back button OR logo
              SizedBox(
                width: 52,
                child: showBack
                    ? IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                        ),
                        color: AppColors.accent,
                        onPressed:
                            onBack ?? () => Navigator.of(context).maybePop(),
                      )
                    : leading ??
                          Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: _GlazeLogo(),
                          ),
              ),
              // Title
              Expanded(
                child:
                    titleWidget ??
                    (title != null
                        ? Text(
                            title!,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          )
                        : const SizedBox.shrink()),
              ),
              // Right actions
              if (actions != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions!,
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glaze logo mark — styled "G" matching the brand accent colour.
class _GlazeLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 26,
      height: 26,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ─── Shared ghost pill button ──────────────────────────────────────────────

/// Accent-tinted ghost pill button — matches Glaze's `tabs-add-btn` style.
class GlazePillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const GlazePillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
