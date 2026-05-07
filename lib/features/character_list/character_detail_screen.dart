import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/character.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';

// ─── Colour tokens (mirror CharacterCardSheet.vue) ─────────────────────────

const _kAccent = AppColors.accent; // #7996CE
const _kAccentDim = Color(0x1F7996CE); // 12 %
const _kAccentBorder = Color(0x337996CE); // 20 %
const _kNsfw = Color(0xFFFF4444);
const _kNsfwBg = Color(0x33FF4444);
const _kNsfwBorder = Color(0x4DFF4444);
const _kSfw = Color(0xFF4CAF50);
const _kSfwBg = Color(0x334CAF50);
const _kSfwBorder = Color(0x524CAF50);
const _kSurface = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)
const _kBorderLine = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)
const _kText75 = Color(0xBFFFFFFF);
const _kText50 = Color(0x80FFFFFF);
const _kText35 = Color(0x59FFFFFF);

// ─── Screen ────────────────────────────────────────────────────────────────

class CharacterDetailScreen extends ConsumerStatefulWidget {
  final String charId;
  const CharacterDetailScreen({super.key, required this.charId});

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState
    extends ConsumerState<CharacterDetailScreen> {
  int _activeTab = 0;

  void _openActionsMenu() {
    GlazeBottomSheet.show(
      context,
      items: [
        BottomSheetItem(
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: () {
            Navigator.pop(context);
            context.go('/character/${widget.charId}/edit');
          },
        ),
        BottomSheetItem(
          icon: Icons.photo_library_outlined,
          label: 'Gallery',
          onTap: () {
            Navigator.pop(context);
            context.go('/character/${widget.charId}/gallery');
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          isDestructive: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlazeScaffold(
      extendBodyBehindHeader: true,
      title: '',
      actions: [_HeaderMenuButton(onTap: _openActionsMenu)],
      onBack: () => context.go('/characters'),
      body: FutureBuilder<Character?>(
        future: ref.read(characterRepoProvider).getById(widget.charId),
        builder: (context, snap) {
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
          return _CharacterDetailBody(
            character: char,
            charId: widget.charId,
            activeTab: _activeTab,
            onTabChange: (i) => setState(() => _activeTab = i),
          );
        },
      ),
    );
  }
}

// ─── Body ──────────────────────────────────────────────────────────────────

class _CharacterDetailBody extends ConsumerWidget {
  final Character character;
  final String charId;
  final int activeTab;
  final ValueChanged<int> onTabChange;

  const _CharacterDetailBody({
    required this.character,
    required this.charId,
    required this.activeTab,
    required this.onTabChange,
  });

  static const _tabLabels = ['Information', 'Prompts'];
  static const _tabIcons = [
    Icons.info_outline_rounded,
    Icons.description_outlined,
  ];

  Future<void> _openChat(BuildContext context, WidgetRef ref, String cId) async {
    final sessions = await ref.read(chatRepoProvider).getByCharacterId(cId);
    if (!context.mounted) return;

    if (sessions.isEmpty) {
      context.go('/chat/$cId');
      return;
    }

    if (sessions.length == 1) {
      context.go('/chat/$cId');
      return;
    }

    GlazeBottomSheet.show(
      context,
      title: 'Open Chat',
      items: [
        BottomSheetItem(
          icon: Icons.add,
          label: 'New Chat',
          onTap: () {
            Navigator.pop(context);
            context.go('/chat/$cId?new=1');
          },
        ),
        ...sessions.map((s) => BottomSheetItem(
          icon: Icons.chat_bubble_outline,
          label: 'Session ${s.sessionIndex + 1}',
          hint: '${s.messages.length} messages',
          onTap: () {
            Navigator.pop(context);
            context.go('/chat/$cId?session=${s.sessionIndex}');
          },
        )),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sab = MediaQuery.of(context).padding.bottom;
    return Stack(
      children: [
        Column(
          children: [
            _HeroSection(character: character),
            _TabsRow(
              labels: _tabLabels,
              icons: _tabIcons,
              activeIndex: activeTab,
              onTabChange: onTabChange,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: activeTab == 0
                    ? _InfoTab(key: const ValueKey('info'), character: character)
                    : _PromptsTab(
                        key: const ValueKey('prompts'),
                        character: character,
                      ),
              ),
            ),
          ],
        ),
        // Chat FAB
        Positioned(
          right: 16,
          bottom: 16 + sab,
          child: _ChatFab(onTap: () => _openChat(context, ref, charId)),
        ),
      ],
    );
  }
}

// ─── Hero ──────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final Character character;
  const _HeroSection({required this.character});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: 310 + topPad,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(),
          // Bottom gradient
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
          // Name + creator overlay
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
                      shadows: [Shadow(blurRadius: 3, color: Color(0xCC000000))],
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
        errorBuilder: (_, __, _) => _HeroPlaceholder(name: character.name),
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

// ─── Tab bar ───────────────────────────────────────────────────────────────

class _TabsRow extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int activeIndex;
  final ValueChanged<int> onTabChange;

  const _TabsRow({
    required this.labels,
    required this.icons,
    required this.activeIndex,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final totalW = constraints.maxWidth;
          final tabW = totalW / labels.length;
          return SizedBox(
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x0DFFFFFF)),
              ),
              child: Stack(
                children: [
                  // Animated slider
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: activeIndex * tabW + 2,
                    top: 2,
                    bottom: 2,
                    width: tabW - 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: _kAccent.withValues(alpha: 0.28),
                        ),
                      ),
                    ),
                  ),
                  // Tab items
                  Row(
                    children: List.generate(labels.length, (i) {
                      final active = i == activeIndex;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onTabChange(i),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icons[i],
                                size: 15,
                                color: active ? _kAccent : _kText50,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: active ? _kAccent : _kText50,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          );
        },
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

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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
      ),
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
      (
        key: 'systemPrompt',
        label: 'System Prompt',
        text: c.systemPrompt ?? '',
      ),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        children: [
          ...sections.map(
            (s) => _AccordionCard(
              key: ValueKey(s.key),
              label: s.label,
              text: s.text,
              expanded: _expanded[s.key] ?? false,
              onToggle: () => setState(
                () => _expanded[s.key] = !(_expanded[s.key] ?? false),
              ),
            ),
          ),
          if (firstMes.isNotEmpty)
            _AccordionCard(
              key: const ValueKey('firstMes'),
              label: 'First Message',
              text: firstMes,
              expanded: _expanded['firstMes'] ?? false,
              onToggle: () => setState(
                () =>
                    _expanded['firstMes'] = !(_expanded['firstMes'] ?? false),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
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
          // Header row
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
          // Body
          AnimatedCrossFade(
            crossFadeState:
                expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 280),
            sizeCurve: Curves.easeOutCubic,
            firstChild: ShaderMask(
              shaderCallback:
                  (bounds) => const LinearGradient(
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

// ─── Header menu button ────────────────────────────────────────────────────

class _HeaderMenuButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HeaderMenuButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xCC1E1E1E),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          color: _kAccent,
          size: 20,
        ),
      ),
    );
  }
}

