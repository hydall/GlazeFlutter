import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/models/character.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import 'character_card.dart';

enum SortType { name, date, lastChat }

enum SortDir { asc, desc }

class CharacterGrid extends StatelessWidget {
  final List<Character> characters;
  final int totalCount;
  final int page;
  final int pageSize;
  final SortType sortBy;
  final SortDir sortDir;
  final VoidCallback onSortDirToggle;
  final ValueChanged<SortType> onSortTypeChanged;
  final ValueChanged<int> onPageChanged;
  final double topPadding;
  final double bottomPadding;
  final Widget? tabBar;
  final bool showOurPicksCard;
  final VoidCallback? onOurPicksTap;
  final VoidCallback? onOurPicksHide;
  final bool showPaginator;

  const CharacterGrid({
    super.key,
    required this.characters,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.sortBy,
    required this.sortDir,
    required this.onSortDirToggle,
    required this.onSortTypeChanged,
    required this.onPageChanged,
    this.topPadding = 0,
    this.bottomPadding = 16,
    this.tabBar,
    this.showOurPicksCard = false,
    this.onOurPicksTap,
    this.onOurPicksHide,
    this.showPaginator = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (topPadding > 0)
          SliverToBoxAdapter(child: SizedBox(height: topPadding)),
        if (tabBar != null) SliverToBoxAdapter(child: tabBar!),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SortDirButton(
                  isAsc: sortDir == SortDir.asc,
                  onTap: onSortDirToggle,
                ),
                const SizedBox(width: 10),
                _SortTypePill(sortBy: sortBy, onChanged: onSortTypeChanged),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Text(
              '$totalCount character${totalCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11,
                color: context.cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2 / 3,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                if (showOurPicksCard && i == 0) {
                  return RepaintBoundary(
                    child: _OurPicksCard(
                      onTap: onOurPicksTap,
                      onHide: onOurPicksHide,
                    ),
                  );
                }
                final charIndex = showOurPicksCard ? i - 1 : i;
                return RepaintBoundary(
                  child: CharacterCard(character: characters[charIndex]),
                );
              },
              childCount: characters.length + (showOurPicksCard ? 1 : 0),
            ),
          ),
        ),
        if (showPaginator)
          SliverToBoxAdapter(
            child: CharacterPaginator(
              page: page,
              pageSize: pageSize,
              totalCount: totalCount,
              onPageChanged: onPageChanged,
              bottomPadding: 8,
            ),
          ),
      ],
    );
  }
}

class _SortDirButton extends StatelessWidget {
  final bool isAsc;
  final VoidCallback onTap;

  const _SortDirButton({required this.isAsc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: AnimatedRotation(
            turns: isAsc ? 0.5 : 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 18,
              color: context.cs.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class CharacterPaginator extends StatelessWidget {
  final int page;
  final int pageSize;
  final int totalCount;
  final ValueChanged<int> onPageChanged;
  final double bottomPadding;

  const CharacterPaginator({
    super.key,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.onPageChanged,
    this.bottomPadding = 8,
  });

  int get _pageCount {
    if (totalCount == 0) return 0;
    return (totalCount + pageSize - 1) ~/ pageSize;
  }

  List<int> get _visiblePages {
    final count = _pageCount;
    if (count <= 5) {
      return [for (var i = 1; i <= count; i++) i];
    }
    final set = <int>{1, 2, count - 1, count};
    if (page - 1 >= 1) set.add(page - 1);
    if (page + 1 <= count) set.add(page + 1);
    set.add(page);
    final sorted = set.where((p) => p >= 1 && p <= count).toList()..sort();
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final count = _pageCount;
    if (count <= 1) return const SizedBox.shrink();

    final visible = _visiblePages;
    final canGoBack = page > 1;
    final canGoForward = page < count;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PaginatorButton(
            icon: Icons.first_page_rounded,
            enabled: canGoBack,
            onTap: () => onPageChanged(1),
            semanticsLabel: 'First page',
          ),
          const SizedBox(width: 4),
          _PaginatorButton(
            icon: Icons.chevron_left_rounded,
            enabled: canGoBack,
            onTap: () => onPageChanged(page - 1),
            semanticsLabel: 'Previous page',
          ),
          const SizedBox(width: 8),
          for (int i = 0; i < visible.length; i++) ...[
            if (i > 0 && visible[i] - visible[i - 1] > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '…',
                  style: TextStyle(
                    color: context.cs.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            _PageNumberButton(
              page: visible[i],
              isActive: visible[i] == page,
              onTap: () => onPageChanged(visible[i]),
            ),
            const SizedBox(width: 4),
          ],
          const SizedBox(width: 4),
          _PaginatorButton(
            icon: Icons.chevron_right_rounded,
            enabled: canGoForward,
            onTap: () => onPageChanged(page + 1),
            semanticsLabel: 'Next page',
          ),
          const SizedBox(width: 4),
          _PaginatorButton(
            icon: Icons.last_page_rounded,
            enabled: canGoForward,
            onTap: () => onPageChanged(count),
            semanticsLabel: 'Last page',
          ),
          const SizedBox(width: 8),
          _JumpToPageButton(
            page: page,
            pageCount: count,
            onSubmit: onPageChanged,
          ),
          const SizedBox(width: 8),
          Text(
            'Page $page of $count',
            style: TextStyle(
              fontSize: 11,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaginatorButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String semanticsLabel;

  const _PaginatorButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? context.cs.primary
        : context.cs.onSurfaceVariant.withValues(alpha: 0.3);
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.cs.primary.withValues(alpha: enabled ? 0.15 : 0.05),
            shape: BoxShape.circle,
            border: Border.all(
              color: context.cs.primary.withValues(alpha: enabled ? 0.2 : 0.05),
            ),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  final int page;
  final bool isActive;
  final VoidCallback onTap;

  const _PageNumberButton({
    required this.page,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isActive
        ? context.cs.primary
        : context.cs.primary.withValues(alpha: 0.12);
    final fg = isActive ? Colors.white : context.cs.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          '$page',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _JumpToPageButton extends StatelessWidget {
  final int page;
  final int pageCount;
  final ValueChanged<int> onSubmit;

  const _JumpToPageButton({
    required this.page,
    required this.pageCount,
    required this.onSubmit,
  });

  Future<void> _open(BuildContext context) async {
    int? target;
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Go to page',
      input: BottomSheetInput(
        placeholder: 'Page (1–$pageCount)',
        confirmLabel: 'Go',
        onConfirm: (v) {
          final n = int.tryParse(v.trim());
          if (n == null) {
            Navigator.of(context, rootNavigator: true).pop();
            return;
          }
          target = n;
          Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    );
    if (target == null) return;
    final clamped = target!.clamp(1, pageCount);
    if (clamped == page) return;
    if (clamped != target) {
      GlazeToast.showWithoutContext('Page $clamped of $pageCount');
    }
    onSubmit(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Jump to page',
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.cs.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: context.cs.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(
            Icons.tag_rounded,
            size: 16,
            color: context.cs.primary,
          ),
        ),
      ),
    );
  }
}

class _OurPicksCard extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onHide;

  const _OurPicksCard({this.onTap, this.onHide});

  @override
  State<_OurPicksCard> createState() => _OurPicksCardState();
}

class _OurPicksCardState extends State<_OurPicksCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _hovered = false;
  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    final curve = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _fadeAnim = curve;
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(curve);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.96 : (_hovered ? 1.01 : 1.0);
    final dy = _hovered && !_pressed ? -4.0 : 0.0;
    final shadowAlpha = _hovered ? 0.3 : 0.1;
    final shadowColor = Colors.black.withValues(alpha: shadowAlpha);

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              transform: Matrix4.identity()
                ..translateByDouble(0.0, dy, 0.0, 1.0)
                ..scaleByDouble(scale, scale, 1.0, 1.0),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: _hovered ? 24 : 6,
                    offset: Offset(0, _hovered ? 12 : 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedScale(
                      scale: _hovered ? 1.05 : 1.0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              context.cs.primary,
                              context.cs.secondary,
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.star_rounded,
                            size: 72,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 150,
                      child: _OurPicksBottomGradient(),
                    ),
                    const Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _OurPicksCardInfo(),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _OurPicksCardMenuButton(
                        onTap: () {
                          GlazeBottomSheet.show<void>(
                            context,
                            title: 'Our Picks',
                            items: [
                              BottomSheetItem(
                                icon: Icons.visibility_off_rounded,
                                label: 'action_hide_msg'.tr(),
                                hint: 'our_picks_restore_hint'.tr(),
                                onTap: () {
                                  Navigator.of(context, rootNavigator: true).pop();
                                  widget.onHide?.call();
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OurPicksBottomGradient extends StatelessWidget {
  const _OurPicksBottomGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF2000000), Color(0x99000000), Colors.transparent],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _OurPicksCardInfo extends StatelessWidget {
  const _OurPicksCardInfo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Our Picks',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                    shadows: [
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Hand-picked featured characters from the Glaze team!',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.3,
              shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
            ),
          ),
        ],
      ),
    );
  }
}

class _OurPicksCardMenuButton extends StatelessWidget {
  final VoidCallback onTap;
  const _OurPicksCardMenuButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          size: 18,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SortTypePill extends StatelessWidget {
  final SortType sortBy;
  final ValueChanged<SortType> onChanged;

  const _SortTypePill({required this.sortBy, required this.onChanged});

  String get _label => switch (sortBy) {
        SortType.name => 'Name',
        SortType.date => 'Date added',
        SortType.lastChat => 'Last chat',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.cs.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cs.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: context.cs.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    BottomSheetItem build(String label, SortType type) => BottomSheetItem(
          label: label,
          actions: sortBy == type
              ? [
                  BottomSheetAction(
                    icon: Icons.check_rounded,
                    color: context.cs.primary,
                    onTap: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      onChanged(type);
                    },
                  ),
                ]
              : const [],
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            onChanged(type);
          },
        );

    GlazeBottomSheet.show<void>(
      context,
      title: 'Sort by',
      items: [
        build('Name', SortType.name),
        build('Date added', SortType.date),
        build('Last chat', SortType.lastChat),
      ],
    );
  }
}
