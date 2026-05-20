import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/models/character.dart';
import '../../core/utils/html_to_markdown.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
import '../../shared/widgets/image_viewer.dart';
import '../../shared/widgets/sheet_view.dart';
import '../../shared/widgets/colored_markdown.dart';

// ─── Colour tokens ─────────────────────────────────────────────────────────

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

// ─── Screen ────────────────────────────────────────────────────────────────

class CharacterDetailSheetLauncher extends StatefulWidget {
  final String charId;
  const CharacterDetailSheetLauncher({super.key, required this.charId});

  @override
  State<CharacterDetailSheetLauncher> createState() =>
      _CharacterDetailSheetLauncherState();
}

class _CharacterDetailSheetLauncherState
    extends State<CharacterDetailSheetLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    final location = GoRouterState.of(context).uri.path;
    final isSubRoute = location.endsWith('/edit') || location.endsWith('/gallery');
    if (isSubRoute) return;
    String? navTarget;
    try {
      navTarget = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CharacterDetailScreen(charId: widget.charId),
      );
    } catch (_) {}
    if (!mounted) return;
    if (navTarget != null && navTarget.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(navTarget!);
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/characters');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class CharacterDetailScreen extends ConsumerStatefulWidget {
  final String charId;

  /// When set, the screen runs in catalog preview mode: it skips the DB
  /// lookup, shows an Import FAB instead of Open Chat, and hides destructive
  /// actions like edit/delete/gallery.
  final Character? previewCharacter;
  final String? previewAvatarUrl;
  final Future<void> Function()? onImport;
  final bool importing;

  const CharacterDetailScreen({
    super.key,
    required this.charId,
    this.previewCharacter,
    this.previewAvatarUrl,
    this.onImport,
    this.importing = false,
  });

  bool get isPreview => previewCharacter != null;

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen> {
  late final Future<Character?> _charFuture;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _charFuture = widget.isPreview
        ? Future.value(widget.previewCharacter)
        : ref.read(characterRepoProvider).getById(widget.charId);
  }

  /// Pops the GlazeBottomSheet, then pops this modal sheet returning [route]
  /// so the caller (launcher / card / drawer) can navigate safely.
  void _closeSheetAndNavigate(String route) {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.pop(); // pop the top-most sheet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        nav.pop<String>(route); // pop CharacterDetailScreen modal
      }
    });
  }

  void _openActionsMenu() {
    final rootNav = Navigator.of(context, rootNavigator: true);
    GlazeBottomSheet.show(
      context,
      items: [
        BottomSheetItem(
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: () {
            rootNav.pop();
            if (!mounted) return;
            context.push('/character/${widget.charId}/edit');
          },
        ),
        BottomSheetItem(
          icon: Icons.photo_library_outlined,
          label: 'Gallery',
          onTap: () {
            rootNav.pop();
            if (!mounted) return;
            context.push('/character/${widget.charId}/gallery');
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          isDestructive: true,
          onTap: () {
            rootNav.pop();
            if (!mounted) return;
            _confirmDelete(context);
          },
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context) async {
    final char = await _charFuture;
    if (char == null) return;
    if (!context.mounted) return;

    final rootNav = Navigator.of(context, rootNavigator: true);
    GlazeBottomSheet.show(
      context,
      title: 'Delete Character',
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'Delete ${char.name}? This cannot be undone.',
      ),
      items: [
        BottomSheetItem(
          label: 'Delete',
          isDestructive: true,
          centered: true,
          onTap: () async {
            await ref.read(charactersProvider.notifier).remove(char.id);
            if (!context.mounted) return;
            _closeSheetAndNavigate('/characters');
          },
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => rootNav.pop(),
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
          onTap: () => _closeSheetAndNavigate('/chat/$cId?new=1'),
        ),
        ...sessions.map(
          (s) => BottomSheetItem(
            icon: Icons.chat_bubble_outline,
            label: 'Session ${s.sessionIndex + 1}',
            hint: '${s.messages.length} messages',
            onTap: () => _closeSheetAndNavigate(
              '/chat/$cId?session=${s.sessionIndex}',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Character?>(
      future: _charFuture,
      builder: (context, snap) {
        final char = snap.data;
        return SheetView(
          showBack: true,
          actions: (char == null || widget.isPreview)
              ? const []
              : [
                  SheetViewAction(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: context.cs.primary,
                    ),
                    onPressed: _openActionsMenu,
                  ),
                ],
          bodyPadding: EdgeInsets.zero,
          body: _buildBody(snap),
          floatingActionButton: char == null
              ? null
              : widget.isPreview
                  ? _ImportFab(
                      importing: widget.importing,
                      onTap: () => widget.onImport?.call(),
                    )
                  : _ChatFab(onTap: () => _openChat(context, char.id)),
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<Character?> snap) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    final char = snap.data;
    if (char == null) {
      return Center(
        child: Text(
          'Character not found',
          style: TextStyle(color: context.cs.onSurface),
        ),
      );
    }
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroSection(
              character: char,
              previewAvatarUrl: widget.previewAvatarUrl,
            ),
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
          color: context.cs.primary,
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

class _ImportFab extends StatelessWidget {
  final bool importing;
  final VoidCallback onTap;
  const _ImportFab({required this.importing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: importing ? null : onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: importing
              ? context.cs.primary.withValues(alpha: 0.5)
              : context.cs.primary,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(blurRadius: 16, color: Color(0x80000000)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (importing)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.download_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Import Character',
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
  final String? previewAvatarUrl;
  const _HeroSection({required this.character, this.previewAvatarUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 310,
      width: double.infinity,
      child: GestureDetector(
        onTap: () {
          ImageProvider? provider;
          if (previewAvatarUrl != null && previewAvatarUrl!.isNotEmpty) {
            provider = CachedNetworkImageProvider(previewAvatarUrl!);
          } else if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
            provider = FileImage(File(character.avatarPath!));
          }
          if (provider != null) {
            ImageViewer.show(
              context,
              imageProvider: provider,
              description: character.name,
            );
          }
        },
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
      ),
    );
  }

  Widget _buildImage() {
    if (previewAvatarUrl != null && previewAvatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: previewAvatarUrl!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        placeholder: (_, _) => _HeroPlaceholder(name: character.name),
        errorWidget: (_, _, _) => _HeroPlaceholder(name: character.name),
      );
    }
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
              'SHORT DESCRIPTION',
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
            child: GptMarkdown(
              hasHtmlTags(notes) ? htmlToMarkdown(notes) : notes,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: _kText75,
              ),
              imageBuilder: (context, url) {
                if (url.startsWith('http://') || url.startsWith('https://')) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
                  );
                }
                if (url.startsWith('data:')) {
                  final commaIdx = url.indexOf(',');
                  if (commaIdx > 0) {
                    try {
                      final bytes = Uri.parse(url).data!.contentAsBytes();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      );
                    } catch (_) {}
                  }
                }
                final file = File(url);
                if (file.existsSync()) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(file, fit: BoxFit.contain),
                  );
                }
                return const SizedBox.shrink();
              },
              inlineComponents: [
                HtmlColorMd(),
                GlowTextMd(),
                ColorGlowTextMd(),
                GradientTextMd(),
                BackgroundTextMd(),
                ImageMd(),
              ],
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
      fg = context.cs.primary;
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
    final altGreetings = widget.character.alternateGreetings;

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
        for (int i = 0; i < altGreetings.length; i++)
          if (altGreetings[i].isNotEmpty)
            _AccordionCard(
              key: ValueKey('altGreeting_$i'),
              label: 'Greeting ${i + 2}',
              text: altGreetings[i],
              expanded: _expanded['altGreeting_$i'] ?? false,
              onToggle: () => setState(
                () => _expanded['altGreeting_$i'] =
                    !(_expanded['altGreeting_$i'] ?? false),
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.65,
                        color: context.cs.primary,
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
