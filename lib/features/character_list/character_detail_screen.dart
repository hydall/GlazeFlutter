import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/character.dart';
import '../../core/services/chat_import_export.dart';
import '../../core/services/persona_character_converter.dart';
import '../../core/utils/html_to_markdown.dart';
import '../../core/utils/platform_paths.dart';
import '../../core/state/character_provider.dart';
import '../../core/state/chat_session_ops_provider.dart';
import '../../features/chat/chat_actions_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/theme_preset.dart';
import '../../shared/theme/theme_provider.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_tab_bar.dart';
import '../../shared/widgets/glaze_error_dialog.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/image_viewer.dart';
import '../../shared/widgets/sheet_view.dart';
import '../../shared/widgets/colored_markdown.dart';
import 'widgets/character_variations_sheet.dart';

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

Border _detailHeaderBorder(BuildContext context, ThemePreset preset) {
  final base = preset.borderParsed ?? context.cs.onSurface;
  return Border.all(
    color: base.withValues(alpha: preset.borderOpacity.clamp(0.0, 1.0)),
    width: preset.borderWidth,
  );
}

// ─── Tabs ──────────────────────────────────────────────────────────────────

List<GlazeTabItem> _detailTabs(BuildContext context) => [
  GlazeTabItem(label: 'section_info'.tr(), icon: Icons.info_outline_rounded),
  GlazeTabItem(
    label: 'section_prompt_blocks'.tr(),
    icon: Icons.description_outlined,
  ),
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

  /// External URL of the character's source page (e.g. its Janitor page).
  /// When set in preview mode, an "open in browser" button replaces the
  /// three-dots actions menu in the floating header.
  final String? previewSourceUrl;

  /// External URL of the creator's profile page. When set, tapping the
  /// `@creator` label in the hero opens it in the browser.
  final String? previewAuthorUrl;
  final Future<void> Function()? onImport;
  final bool importing;

  const CharacterDetailScreen({
    super.key,
    required this.charId,
    this.previewCharacter,
    this.previewAvatarUrl,
    this.previewSourceUrl,
    this.previewAuthorUrl,
    this.onImport,
    this.importing = false,
  });

  bool get isPreview => previewCharacter != null;

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen> {
  int _activeTabIndex = 0;

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

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openActionsMenu() {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final char = ref.read(characterByIdProvider(widget.charId));
    final isHidden = char?.hidden ?? false;
    final catalogUrl = char?.extensions['catalogUrl'];
    final hasCatalogUrl = catalogUrl is String && catalogUrl.isNotEmpty;
    GlazeBottomSheet.show<void>(
      context,
      items: [
        BottomSheetItem(
          icon: Icons.edit_outlined,
          label: 'action_edit'.tr(),
          onTap: () {
            rootNav.pop();
            if (!mounted) return;
            context.push('/character/${widget.charId}/edit');
          },
        ),
        BottomSheetItem(
          icon: isHidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          label: isHidden ? 'action_unhide'.tr() : 'action_hide'.tr(),
          onTap: () {
            rootNav.pop();
            _toggleHidden(isHidden);
          },
        ),
        BottomSheetItem(
          icon: Icons.photo_library_outlined,
          label: 'menu_image_viewer'.tr(),
          onTap: () {
            rootNav.pop();
            if (!mounted) return;
            context.push('/character/${widget.charId}/gallery');
          },
        ),
        BottomSheetItem(
          icon: Icons.dynamic_feed_rounded,
          label: 'variations_title'.tr(),
          onTap: () {
            rootNav.pop();
            if (!mounted) return;
            _showVariations(context);
          },
        ),
        if (hasCatalogUrl)
          BottomSheetItem(
            icon: Icons.travel_explore_outlined,
            label: 'action_open_in_catalog'.tr(),
            onTap: () {
              rootNav.pop();
              _openExternal(catalogUrl);
            },
          ),
        BottomSheetItem(
          icon: Icons.badge_outlined,
          label: 'action_convert_to_persona'.tr(),
          onTap: () async {
            rootNav.pop();
            if (char == null || !mounted) return;
            await convertCharacterToPersona(ref, char);
            if (!mounted) return;
            GlazeToast.show(context, 'convert_to_persona_done'.tr());
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'action_delete_msg'.tr(),
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
    final char = widget.isPreview
        ? widget.previewCharacter
        : ref.read(characterByIdProvider(widget.charId));
    if (char == null) return;
    if (!context.mounted) return;

    final rootNav = Navigator.of(context, rootNavigator: true);
    unawaited(GlazeBottomSheet.show<void>(
      context,
      title: 'action_delete_char'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description:
            '${'confirm_delete_character'.tr().replaceAll('?', '')} "${char.displayName?.trim().isNotEmpty == true ? char.displayName!.trim() : char.name}"?',
      ),
      items: [
        BottomSheetItem(
          label: 'action_delete_msg'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () async {
            await ref.read(charactersProvider.notifier).remove(char.id);
            if (!context.mounted) return;
            _closeSheetAndNavigate('/characters');
          },
        ),
        BottomSheetItem(
          label: 'btn_cancel'.tr(),
          centered: true,
          onTap: () => rootNav.pop(),
        ),
      ],
    ));
  }

  Future<void> _toggleHidden(bool wasHidden) async {
    await ref
        .read(charactersProvider.notifier)
        .setHidden(widget.charId, !wasHidden);
    if (!mounted) return;
    GlazeToast.show(
      context,
      wasHidden ? 'char_unhidden_toast'.tr() : 'char_hidden_toast'.tr(),
    );
  }

  void _showVariations(BuildContext context) {
    final char = ref.read(characterByIdProvider(widget.charId));
    final groupId = (char == null || char.variantGroupId.isEmpty)
        ? widget.charId
        : char.variantGroupId;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CharacterVariationsSheet(groupId: groupId),
    );
  }

  Future<void> _openChat(BuildContext context, String cId) async {
    // When the character has multiple variations, choose which one to start the
    // chat with. The chosen variation is a distinct character id, so its chat
    // sessions (and history group) are independent and can't be switched later.
    final all = ref.read(charactersProvider).value ?? const <Character>[];
    final current = all.where((c) => c.id == cId).firstOrNull;
    if (current != null) {
      final groupId = current.variantGroupId.isEmpty
          ? current.id
          : current.variantGroupId;
      final variants = all
          .where((c) =>
              (c.variantGroupId.isEmpty ? c.id : c.variantGroupId) == groupId)
          .toList()
        ..sort((a, b) => a.variantOrder.compareTo(b.variantOrder));
      if (variants.length > 1) {
        final pickedId = await _pickVariation(context, variants);
        if (pickedId == null || !context.mounted) return;
        cId = pickedId;
      }
    }

    final sessions = await ref
        .read(chatSessionOpsProvider.notifier)
        .getSessionMetadataByCharacter(cId);
    if (!context.mounted) return;

    // Inner sheet pops with a value; the outer CharacterDetailScreen modal
    // is popped exactly once afterwards. Two chained Navigator.pop() calls
    // (one immediate + one via addPostFrameCallback) race against the inner
    // sheet's exit animation and can drop the route on the floor.
    final result = await GlazeBottomSheet.show<String>(
      context,
      title: 'btn_open_chat'.tr(),
      items: [
        BottomSheetItem(
          icon: Icons.add,
          label: 'btn_new_chat'.tr(),
          onTap: () => Navigator.of(context, rootNavigator: true).pop('new'),
        ),
        BottomSheetItem(
          icon: Icons.file_download,
          label: 'action_import'.tr(),
          onTap: () => Navigator.of(context, rootNavigator: true).pop('import'),
        ),
        ...sessions.map(
          (s) => BottomSheetItem(
            icon: Icons.chat_bubble_outline,
            label: 'session_name'.tr(
              namedArgs: {'id': '${s.sessionIndex + 1}'},
            ),
            hint:
                '${s.messageCount} ${'count_messages'.plural(s.messageCount)}',
            onTap: () => Navigator.of(context, rootNavigator: true)
                .pop('session:${s.sessionIndex}'),
          ),
        ),
      ],
    );

    if (result == null) return;
    if (!context.mounted) return;

    if (result == 'import') {
      unawaited(_importChat(cId));
      return;
    }

    final route = result == 'new'
        ? (sessions.isEmpty ? '/chat/$cId' : '/chat/$cId?new=1')
        : '/chat/$cId?session=${result.substring('session:'.length)}';
    Navigator.of(context, rootNavigator: true).pop<String>(route);
  }

  Future<String?> _pickVariation(
    BuildContext context,
    List<Character> variants,
  ) {
    return GlazeBottomSheet.show<String>(
      context,
      title: 'variation_pick_title'.tr(),
      items: [
        for (final v in variants)
          BottomSheetItem(
            icon: Icons.person_outline_rounded,
            label: v.variantName?.trim().isNotEmpty == true
                ? v.variantName!.trim()
                : 'variation_original'.tr(),
            onTap: () =>
                Navigator.of(context, rootNavigator: true).pop(v.id),
          ),
      ],
    );
  }

  Future<void> _importChat(String charId) async {
    final result = await FilePicker.pickFiles(
      type: Platform.isIOS ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isIOS ? null : ['jsonl', 'json'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final filePath = file.path;
    try {
      ChatImportSaveResult saveResult;
      if (file.bytes != null) {
        final importResult = importChatFromJsonlString(
          utf8.decode(file.bytes!),
        );
        saveResult = await ref.read(chatActionsServiceProvider)
            .importChatFromResult(charId, importResult);
      } else if (filePath != null) {
        saveResult = await ref.read(chatActionsServiceProvider)
            .importChat(charId, filePath);
      } else {
        return;
      }
      if (!mounted) return;
      final count = saveResult.count;
      final sessionIndex = saveResult.sessionIndex;
      GlazeToast.show(
        context,
        count == 0 ? 'no_results'.tr() : 'import_success'.tr(),
      );
      if (count > 0 && sessionIndex != null) {
        // The inner "Open chat" sheet was already popped (with the value
        // 'import') before _importChat ran, so only the outer
        // CharacterDetailScreen modal remains. Pop it once, returning the chat
        // route so the launcher (_showDetailSheet) navigates via context.go.
        // Using _closeSheetAndNavigate here popped twice — the first pop closed
        // the modal with a null result, so the launcher never navigated and the
        // chat opened as a blank dark screen.
        Navigator.of(context, rootNavigator: true)
            .pop<String>('/chat/$charId?session=$sessionIndex');
      }
    } catch (e) {
      if (mounted) GlazeErrorDialog.show(context, e, prefix: '${'settings_err_failed'.tr()} ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final charactersAsync = widget.isPreview
        ? const AsyncData<List<Character>>(<Character>[])
        : ref.watch(charactersProvider);
    final char = widget.isPreview
        ? widget.previewCharacter
        : ref.watch(characterByIdProvider(widget.charId));

    return SheetView(
      floating: _buildFloatingHeader(char),
      bodyPadding: EdgeInsets.zero,
      body: _buildBody(charactersAsync, char),
      floatingActionButton: char == null
          ? null
          : widget.isPreview
              ? _ImportFab(
                  importing: widget.importing,
                  onTap: () => widget.onImport?.call(),
                )
              : _ChatFab(onTap: () => _openChat(context, char.id)),
    );
  }

  Widget _buildBody(
    AsyncValue<List<Character>> charactersAsync,
    Character? char,
  ) {
    if (!widget.isPreview && charactersAsync.isLoading && char == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (char == null) {
      return Center(
        child: Text(
          'no_results'.tr(),
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
              authorUrl: widget.previewAuthorUrl,
              onOpenAuthor: _openExternal,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: GlazeTabBar(
                tabs: _detailTabs(context),
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

  Widget _buildFloatingHeader(Character? char) {
    final safeTop = MediaQueryData.fromView(View.of(context)).padding.top;
    return IgnorePointer(
      ignoring: char == null,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: safeTop + 12, left: 16, right: 16),
          child: Row(
            children: [
              _DetailHeaderButton(
                icon: Icons.arrow_back,
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/characters');
                  }
                },
              ),
              const Spacer(),
              if (!widget.isPreview && char != null)
                _DetailHeaderButton(
                  icon: Icons.more_vert_rounded,
                  onTap: _openActionsMenu,
                )
              else if (widget.isPreview &&
                  char != null &&
                  widget.previewSourceUrl != null)
                _DetailHeaderButton(
                  icon: Icons.open_in_new_rounded,
                  onTap: () => _openExternal(widget.previewSourceUrl!),
                ),
            ],
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
          color: context.cs.primary,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(blurRadius: 16, color: Color(0x80000000)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              'btn_open_chat'.tr(),
              style: const TextStyle(
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
            Text(
              'catalog_import'.tr(),
              style: const TextStyle(
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

class _DetailHeaderButton extends ConsumerStatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _DetailHeaderButton({required this.icon, this.onTap});

  @override
  ConsumerState<_DetailHeaderButton> createState() =>
      _DetailHeaderButtonState();
}

class _DetailHeaderButtonState extends ConsumerState<_DetailHeaderButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preset = ref.watch(themeProvider.select((s) => s.activePreset));
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap != null ? (_) => _press.forward() : null,
      onTapUp: widget.onTap != null ? (_) => _press.reverse() : null,
      onTapCancel: widget.onTap != null ? () => _press.reverse() : null,
      child: ScaleTransition(
        scale: _scale,
        child: SizedBox(
          width: 40,
          height: 40,
          child: GlassSurface(
            borderRadius: BorderRadius.circular(20),
            tint: context.cs.surface,
            border: _detailHeaderBorder(context, preset),
            child: Center(
              child: Icon(widget.icon, color: context.cs.primary, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final Character character;
  final String? previewAvatarUrl;
  final String? authorUrl;
  final void Function(String url)? onOpenAuthor;
  const _HeroSection({
    required this.character,
    this.previewAvatarUrl,
    this.authorUrl,
    this.onOpenAuthor,
  });

  String get _displayName {
    final displayName = character.displayName?.trim();
    return (displayName != null && displayName.isNotEmpty)
        ? displayName
        : character.name;
  }

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
            provider = FileImage(File(resolveGlazeFilePath(character.avatarPath!)!));
          }
          if (provider != null) {
            ImageViewer.show(
              context,
              imageProvider: provider,
              description: _displayName,
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
                  _displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 6, color: Color(0xCC000000))],
                  ),
                ),
                if (character.creator != null && character.creator!.isNotEmpty)
                  _buildAuthorLabel(context),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildAuthorLabel(BuildContext context) {
    final hasLink = authorUrl != null &&
        authorUrl!.isNotEmpty &&
        onOpenAuthor != null;
    final label = Text(
      '@${character.creator}',
      style: TextStyle(
        fontSize: 13,
        color: hasLink ? context.cs.primary : _kText50,
        fontWeight: hasLink ? FontWeight.w600 : FontWeight.w400,
        shadows: const [Shadow(blurRadius: 3, color: Color(0xCC000000))],
      ),
    );
    if (!hasLink) return label;
    return GestureDetector(
      onTap: () => onOpenAuthor!(authorUrl!),
      behavior: HitTestBehavior.opaque,
      child: label,
    );
  }

  Widget _buildImage() {
    if (previewAvatarUrl != null && previewAvatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: previewAvatarUrl!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        placeholder: (_, _) => _HeroPlaceholder(name: _displayName),
        errorWidget: (_, _, _) => _HeroPlaceholder(name: _displayName),
      );
    }
    if (character.avatarPath != null && character.avatarPath!.isNotEmpty) {
      return Image.file(
        File(resolveGlazeFilePath(character.avatarPath!)!),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (_, _, _) => _HeroPlaceholder(name: _displayName),
      );
    }
    return _HeroPlaceholder(name: _displayName);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'label_description'.tr().toUpperCase(),
              style: const TextStyle(
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
              onLinkTap: (url, title) async {
                final uri = Uri.tryParse(url);
                if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              imageBuilder: (context, url, width, height) {
                if (url.startsWith('http://') || url.startsWith('https://')) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: width,
                      height: height,
                      fit: BoxFit.contain,
                    ),
                  );
                }
                if (url.startsWith('data:')) {
                  final commaIdx = url.indexOf(',');
                  if (commaIdx > 0) {
                    try {
                      final bytes = Uri.parse(url).data!.contentAsBytes();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          bytes,
                          width: width,
                          height: height,
                          fit: BoxFit.contain,
                        ),
                      );
                    } catch (_) {}
                  }
                }
                final file = File(url);
                if (file.existsSync()) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      file,
                      width: width,
                      height: height,
                      fit: BoxFit.contain,
                    ),
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
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                'no_preview_available'.tr(),
                style: const TextStyle(color: _kText35),
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
      (key: 'description', label: 'label_description'.tr(), text: c.description ?? ''),
      (key: 'personality', label: 'label_personality'.tr(), text: c.personality ?? ''),
      (key: 'scenario', label: 'label_scenario'.tr(), text: c.scenario ?? ''),
      (key: 'mesExample', label: 'label_mes_example'.tr(), text: c.mesExample ?? ''),
      (key: 'systemPrompt', label: 'role_system'.tr(), text: c.systemPrompt ?? ''),
      (
        key: 'postHistory',
        label: 'role_system'.tr(),
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
            label: 'label_first_mes'.tr(),
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
              label: '${'placeholder_greeting'.tr()} ${i + 2}',
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
