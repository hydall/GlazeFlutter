import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gradient_blur/gradient_blur.dart';

import '../../core/models/character.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_tab_bar.dart';

// ─── Colour tokens ─────────────────────────────────────────────────────────

const _kAccent = AppColors.accent;
const _kAccentDim = Color(0x1F7996CE);
const _kAccentBorder = Color(0x337996CE);
const _kNsfw = Color(0xFFFF4444);
const _kNsfwBg = Color(0x33FF4444);
const _kNsfwBorder = Color(0x4DFF4444);
const _kSfw = Color(0xFF4CAF50);
const _kSfwBg = Color(0x334CAF50);
const _kSfwBorder = Color(0x524CAF50);
const _kSurface = Color(0x0DFFFFFF);
const _kBorderLine = Color(0x0DFFFFFF);
const _kText75 = Color(0xBFFFFFFF);
const _kText50 = Color(0x80FFFFFF);
const _kText35 = Color(0x59FFFFFF);

// ─── Tabs ──────────────────────────────────────────────────────────────────

const _kTabs = [
  GlazeTabItem(label: 'Information', icon: Icons.info_outline_rounded),
  GlazeTabItem(label: 'Prompts', icon: Icons.description_outlined),
];

// ─── Layout constants ──────────────────────────────────────────────────────

// handle pill (10 top pad + 4 pill + 10 bottom pad) = 24px
// back/menu row (4 gap + 48 height) = 52px
// total overlay height: 76px → round to 80 for scroll padding
const _kHeaderH = 80.0;

// ─── Screen ────────────────────────────────────────────────────────────────

class CharacterDetailScreen extends ConsumerStatefulWidget {
  final String charId;
  const CharacterDetailScreen({super.key, required this.charId});

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen> {
  late final Future<Character?> _charFuture;
  int _activeTabIndex = 0;
  final _sheetController = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _charFuture = ref.read(characterRepoProvider).getById(widget.charId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sheetController.addListener(_onSheetSizeChange);
    });
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _onSheetSizeChange() {
    if (!mounted || !_sheetController.isAttached) return;
    if (_sheetController.size < 0.45) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  void _toggleExpand() {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      _sheetController.size > 0.9 ? 0.78 : 1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _openActionsMenu() {
    GlazeBottomSheet.show(
      context,
      items: [
        BottomSheetItem(
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            context.go('/character/${widget.charId}/edit');
          },
        ),
        BottomSheetItem(
          icon: Icons.photo_library_outlined,
          label: 'Gallery',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            context.go('/character/${widget.charId}/gallery');
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          isDestructive: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  Future<void> _openChat(BuildContext context, String cId) async {
    final sessions = await ref.read(chatRepoProvider).getByCharacterId(cId);
    if (!context.mounted) return;

    GlazeBottomSheet.show(
      context,
      title: 'Open Chat',
      items: [
        BottomSheetItem(
          icon: Icons.add,
          label: 'New Chat',
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            context.go('/chat/$cId?new=1');
          },
        ),
        ...sessions.map(
          (s) => BottomSheetItem(
            icon: Icons.chat_bubble_outline,
            label: 'Session ${s.sessionIndex + 1}',
            hint: '${s.messages.length} messages',
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              context.go('/chat/$cId?session=${s.sessionIndex}');
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.3,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.78, 1.0],
      controller: _sheetController,
      builder: (_, scrollController) => _buildSheet(scrollController),
    );
  }

  Widget _buildSheet(ScrollController scrollController) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return ListenableBuilder(
      listenable: _sheetController,
      builder: (context, child) {
        final t = _sheetController.isAttached
            ? ((_sheetController.size - 0.78) / 0.22).clamp(0.0, 1.0)
            : 0.0;
        return ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24.0 * (1.0 - t)),
          ),
          child: child!,
        );
      },
      child: _buildInner(scrollController, safeBottom),
    );
  }

  Widget _buildInner(ScrollController scrollController, double safeBottom) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xE81A1A1A),
          border: Border(top: BorderSide(color: AppColors.glassBorder)),
        ),
        child: FutureBuilder<Character?>(
          future: _charFuture,
          builder: (context, snap) {
            final char = snap.data;
            return Stack(
              children: [
                Positioned.fill(
                  child: _buildScrollBody(
                    context,
                    snap,
                    scrollController,
                    safeBottom,
                  ),
                ),
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
                        stops: [0.0, 0.55, 1.0],
                      ),
                      child: const SizedBox(height: _kHeaderH),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _toggleExpand,
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      height: 28,
                      child: Center(child: _HandlePill()),
                    ),
                  ),
                ),
                Positioned(
                  top: 28,
                  left: 16,
                  right: 16,
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        _HeaderBtn(
                          onTap: () => Navigator.of(
                            context,
                            rootNavigator: true,
                          ).maybePop(),
                          child: const Icon(
                            Icons.arrow_back,
                            size: 20,
                            color: _kAccent,
                          ),
                        ),
                        const Spacer(),
                        if (char != null)
                          _HeaderBtn(
                            onTap: _openActionsMenu,
                            child: const Icon(
                              Icons.more_vert_rounded,
                              size: 20,
                              color: _kAccent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (char != null)
                  Positioned(
                    right: 16,
                    bottom: 16 + safeBottom,
                    child: _ChatFab(onTap: () => _openChat(context, char.id)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildScrollBody(
    BuildContext context,
    AsyncSnapshot<Character?> snap,
    ScrollController scrollController,
    double safeBottom,
  ) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    final char = snap.data;
    if (char == null) {
      return const Center(
        child: Text(
          'Character not found',
          style: TextStyle(color: AppColors.textPrimary),
        ),
      );
    }
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroSection(character: char),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: GlazeTabBar(
                tabs: _kTabs,
                activeIndex: _activeTabIndex,
                onChanged: (i) => setState(() => _activeTabIndex = i),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _activeTabIndex == 0
                  ? _InfoTab(key: const ValueKey('info'), character: char)
                  : _PromptsTab(
                      key: const ValueKey('prompts'),
                      character: char,
                    ),
            ),
            SizedBox(height: 100 + safeBottom),
          ],
        ),
      ),
    );
  }
}

// ─── Handle pill ───────────────────────────────────────────────────────────

class _HandlePill extends StatelessWidget {
  const _HandlePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ─── Header button ─────────────────────────────────────────────────────────

class _HeaderBtn extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _HeaderBtn({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xCC1E1E1E),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

// ─── Chat FAB ──────────────────────────────────────────────────────────────

class _ChatFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ChatFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: _kAccent,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(blurRadius: 16, color: Color(0x80000000)),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'Open Chat',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero ──────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final Character character;
  const _HeroSection({required this.character});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 310,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.35, 0.60, 1.0],
                colors: [
                  Colors.transparent,
                  Color(0x33000000),
                  Color(0xBF000000),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  character.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 6, color: Color(0xCC000000))],
                  ),
                ),
                if (character.creator != null && character.creator!.isNotEmpty)
                  Text(
                    '@${character.creator}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _kText50,
                      shadows: [
                        Shadow(blurRadius: 3, color: Color(0xCC000000)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
      return Image.file(
        File(character.avatarPath!),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (_, _, _) => _HeroPlaceholder(name: character.name),
      );
    }
    return _HeroPlaceholder(name: character.name);
  }
}

class _HeroPlaceholder extends StatelessWidget {
  final String name;
  const _HeroPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x147996CE),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w700,
            color: _kText35,
          ),
        ),
      ),
    );
  }
}

// ─── Info tab ──────────────────────────────────────────────────────────────

class _InfoTab extends StatelessWidget {
  final Character character;
  const _InfoTab({super.key, required this.character});

  @override
  Widget build(BuildContext context) {
    final tags = character.tags;
    final notes = character.creatorNotes;
    final hasNotes = notes != null && notes.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags.map((t) => _TagChip(tag: t)).toList(),
            ),
          ),
        if (hasNotes) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'CREATOR NOTES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.77,
                color: _kText35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SelectableText(
              notes,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: _kText75,
              ),
            ),
          ),
        ],
        if (tags.isEmpty && !hasNotes)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                'No information available',
                style: TextStyle(color: _kText35),
              ),
            ),
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final Color bg, fg, border;
    if (tag == 'NSFW') {
      bg = _kNsfwBg;
      fg = _kNsfw;
      border = _kNsfwBorder;
    } else if (tag == 'SFW') {
      bg = _kSfwBg;
      fg = _kSfw;
      border = _kSfwBorder;
    } else if (tag.startsWith('#')) {
      bg = const Color(0x1A00FFFF);
      fg = const Color(0xFF00CCCC);
      border = const Color(0x3300FFFF);
    } else {
      bg = _kAccentDim;
      fg = _kAccent;
      border = _kAccentBorder;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Text(
        tag,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ─── Prompts tab ───────────────────────────────────────────────────────────

class _PromptsTab extends StatefulWidget {
  final Character character;
  const _PromptsTab({super.key, required this.character});

  @override
  State<_PromptsTab> createState() => _PromptsTabState();
}

class _PromptsTabState extends State<_PromptsTab> {
  final Map<String, bool> _expanded = {};

  List<({String key, String label, String text})> get _sections {
    final c = widget.character;
    return [
      (key: 'description', label: 'Description', text: c.description ?? ''),
      (key: 'personality', label: 'Personality', text: c.personality ?? ''),
      (key: 'scenario', label: 'Scenario', text: c.scenario ?? ''),
      (key: 'mesExample', label: 'Example Dialogue', text: c.mesExample ?? ''),
      (key: 'systemPrompt', label: 'System Prompt', text: c.systemPrompt ?? ''),
      (
        key: 'postHistory',
        label: 'Post-History Instructions',
        text: c.postHistoryInstructions ?? '',
      ),
    ].where((s) => s.text.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    final firstMes = widget.character.firstMes ?? '';

    return Column(
      children: [
        ...sections.map(
          (s) => _AccordionCard(
            key: ValueKey(s.key),
            label: s.label,
            text: s.text,
            expanded: _expanded[s.key] ?? false,
            onToggle: () =>
                setState(() => _expanded[s.key] = !(_expanded[s.key] ?? false)),
          ),
        ),
        if (firstMes.isNotEmpty)
          _AccordionCard(
            key: const ValueKey('firstMes'),
            label: 'First Message',
            text: firstMes,
            expanded: _expanded['firstMes'] ?? false,
            onToggle: () => setState(
              () => _expanded['firstMes'] = !(_expanded['firstMes'] ?? false),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _AccordionCard extends StatelessWidget {
  final String label;
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  const _AccordionCard({
    super.key,
    required this.label,
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.65,
                        color: _kAccent,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.0 : 0.5,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: _kText50,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 280),
            sizeCurve: Curves.easeOutCubic,
            firstChild: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.45, 1.0],
                colors: [Colors.white, Colors.transparent],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: _kText75,
                  ),
                ),
              ),
            ),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.55,
                  color: _kText75,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
