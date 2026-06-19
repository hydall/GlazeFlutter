import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/models/character.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../character_sort.dart';
import 'character_card.dart';

class CharacterGrid extends StatelessWidget {
  final List<Character> characters;
  final int totalCount;
  final SortType sortBy;
  final SortDir sortDir;
  final VoidCallback onSortDirToggle;
  final ValueChanged<SortType> onSortTypeChanged;
  final double topPadding;
  final double bottomPadding;
  final Widget? tabBar;
  final bool showOurPicksCard;
  final VoidCallback? onOurPicksTap;
  final VoidCallback? onOurPicksHide;
  final bool isLoadingMore;
  final bool hasMore;
  final int filterCount;
  final VoidCallback? onFilterTap;

  /// Optional sliver inserted right after [tabBar] (e.g. the folders section).
  final Widget? headerSliver;

  /// When set, cards are rendered inside this folder and expose "Remove from
  /// folder".
  final String? folderId;

  const CharacterGrid({
    super.key,
    required this.characters,
    required this.totalCount,
    required this.sortBy,
    required this.sortDir,
    required this.onSortDirToggle,
    required this.onSortTypeChanged,
    this.topPadding = 0,
    this.bottomPadding = 16,
    this.tabBar,
    this.showOurPicksCard = false,
    this.onOurPicksTap,
    this.onOurPicksHide,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.filterCount = 0,
    this.onFilterTap,
    this.headerSliver,
    this.folderId,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (topPadding > 0)
          SliverToBoxAdapter(child: SizedBox(height: topPadding)),
        if (tabBar != null) SliverToBoxAdapter(child: tabBar!),
        ?headerSliver,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onFilterTap != null) ...[
                  _FilterButton(count: filterCount, onTap: onFilterTap!),
                  const SizedBox(width: 10),
                ],
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
              '$totalCount ${'count_characters'.plural(totalCount)}',
              style: TextStyle(
                fontSize: 11,
                color: context.cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2 / 3,
            ),
            delegate: SliverChildBuilderDelegate(
              // No explicit RepaintBoundary: SliverChildBuilderDelegate already
              // wraps each child in one (addRepaintBoundaries: true by default).
              (ctx, i) {
                if (showOurPicksCard && i == 0) {
                  return _OurPicksCard(
                    onTap: onOurPicksTap,
                    onHide: onOurPicksHide,
                  );
                }
                final charIndex = showOurPicksCard ? i - 1 : i;
                return CharacterCard(
                  character: characters[charIndex],
                  folderId: folderId,
                );
              },
              childCount: characters.length + (showOurPicksCard ? 1 : 0),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: hasMore || isLoadingMore ? 56 : 0,
            child: isLoadingMore
                ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.cs.primary,
                      ),
                    ),
                  )
                : null,
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
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
      child: SizedBox(
        width: 32,
        height: 32,
        child: GlassSurface(
          borderRadius: BorderRadius.circular(16),
          tint: context.cs.surface,
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.18)),
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
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            GlassSurface(
              borderRadius: BorderRadius.circular(16),
              tint: context.cs.surface,
              border: Border.all(
                color: context.cs.primary.withValues(alpha: 0.18),
              ),
              child: Center(
                child: Icon(
                  Icons.filter_list_rounded,
                  size: 18,
                  color: context.cs.primary,
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: context.cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
                            colors: [context.cs.primary, context.cs.secondary],
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
                                  Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).pop();
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
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
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
    SortType.name => 'sort_name'.tr(),
    SortType.date => 'sort_date'.tr(),
    SortType.lastChat => 'Last chat',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: SizedBox(
        height: 32,
        child: GlassSurface(
          borderRadius: BorderRadius.circular(16),
          tint: context.cs.surface,
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.18)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
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
      title: 'sort_by'.tr(),
      items: [
        build('sort_name'.tr(), SortType.name),
        build('sort_date'.tr(), SortType.date),
        build('Last chat', SortType.lastChat),
      ],
    );
  }
}
