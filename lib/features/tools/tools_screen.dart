import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/active_selection_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart' show GlazeAppBar;

class PersonaInfo {
  final String name;
  final String? avatarPath;
  const PersonaInfo({required this.name, this.avatarPath});
}

final _activePersonaInfoProvider = FutureProvider<PersonaInfo?>((ref) async {
  final activeId = ref.watch(activePersonaIdProvider);
  if (activeId == null) return null;
  final persona = await ref.read(personaRepoProvider).getById(activeId);
  if (persona == null) return null;
  return PersonaInfo(name: persona.name, avatarPath: persona.avatarPath);
});

final _activePresetNameProvider = FutureProvider<String>((ref) async {
  final activeId = ref.watch(activePresetIdProvider);
  if (activeId == null) return 'Default';
  final preset = await ref.read(presetRepoProvider).getById(activeId);
  return preset?.name ?? 'Default';
});

// SVG paths matching ToolsView.vue
const _kIconPersonas =
    'M19 3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 3c1.66 0 3 1.34 3 3s-1.34 3-3 3-3-1.34-3-3 1.34-3 3-3zm6 12H6v-1c0-2 4-3.1 6-3.1s6 1.1 6 3.1v1z';
const _kIconPresets =
    'M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6h-6V2zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z';
const _kIconApi =
    'M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z';
const _kIconLorebook =
    'M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9H9V9h10v2zm-4 4H9v-2h6v2zm4-8H9V5h10v2z';
const _kIconRegex =
    'M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z';

Widget _svgPath(String d, {Color fill = Colors.white, double size = 20}) =>
    SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="$d"/></svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(fill, BlendMode.srcIn),
    );

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPad = ref.watch(navHeightProvider) + 20;
    final personaInfo = ref.watch(_activePersonaInfoProvider).value;
    final presetName = ref.watch(_activePresetNameProvider).value ?? 'Default';
    final topPad = MediaQuery.of(context).padding.top + 66.0;
    return Scaffold(
      backgroundColor: context.cs.surface,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(16, topPad + 16, 16, bottomPad),
            children: [
              _HeroCard(
                iconPath: _kIconPersonas,
                title: 'Personas',
                subtitle: personaInfo?.name ?? 'user',
                avatarPath: personaInfo?.avatarPath,
                isAvatar: true,
                onTap: () => context.go('/tools/personas'),
              ),
              const SizedBox(height: 16),
              _HeroCard(
                iconPath: _kIconPresets,
                title: 'Presets',
                subtitle: presetName,
                onTap: () => context.go('/tools/presets'),
              ),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _GridTile(
                        iconPath: _kIconApi,
                        title: 'API',
                        subtitle: 'Endpoints & models',
                        showStatusDot: true,
                        onTap: () => context.go('/tools/api'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GridTile(
                        iconPath: _kIconLorebook,
                        title: 'Lorebooks',
                        subtitle: 'World info',
                        onTap: () => context.go('/tools/lorebooks'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _GridTile(
                      iconPath: _kIconRegex,
                      title: 'Regex Scripts',
                      subtitle: 'Find & replace scripts',
                      onTap: () => context.go('/tools/regex'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: const GlazeAppBar(title: 'Tools'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String iconPath;
  final String title;
  final String subtitle;
  final bool isAvatar;
  final String? avatarPath;
  final VoidCallback onTap;

  const _HeroCard({
    required this.iconPath,
    required this.title,
    required this.subtitle,
    this.isAvatar = false,
    this.avatarPath,
    required this.onTap,
  });

  static const _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
    letterSpacing: 1,
    color: Color(0xE6FFFFFF), // rgba(255,255,255,0.9)
  );

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      onTap: onTap,
      child: Container(
        height: isAvatar ? null : 140,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (isAvatar) ...[
              Positioned.fill(
                child: avatarPath != null && avatarPath!.isNotEmpty
                    ? Image.file(
                        File(avatarPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _AvatarGradientPlaceholder(subtitle: subtitle),
                      )
                    : _AvatarGradientPlaceholder(subtitle: subtitle),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.05),
                        Colors.white.withValues(alpha: 0.01),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isAvatar)
                    Text(title.toUpperCase(), style: _labelStyle)
                  else
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: _svgPath(iconPath, fill: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(title.toUpperCase(), style: _labelStyle),
                      ],
                    ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isAvatar) return AspectRatio(aspectRatio: 1, child: card);
    return card;
  }
}

class _AvatarGradientPlaceholder extends StatelessWidget {
  final String subtitle;
  const _AvatarGradientPlaceholder({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF66CCFF), Color(0xFF7996CE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          subtitle.isNotEmpty ? subtitle[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 80,
            fontWeight: FontWeight.w800,
            color: Color(0xCCFFFFFF), // rgba(255,255,255,0.8)
          ),
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  final String iconPath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showStatusDot;

  const _GridTile({
    required this.iconPath,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showStatusDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.cs.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: _svgPath(iconPath, fill: context.cs.onSurfaceVariant, size: 22),
                  ),
                ),
                if (showStatusDot)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.cs.onSurfaceVariant,
                        border: Border.all(color: context.cs.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.cs.primary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
