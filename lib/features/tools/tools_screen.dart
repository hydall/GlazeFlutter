import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPad = ref.watch(navHeightProvider) + 20;
    final personaInfo = ref.watch(_activePersonaInfoProvider).value;
    final presetName = ref.watch(_activePresetNameProvider).value ?? 'Default';
    final topPad = MediaQuery.of(context).padding.top + 66.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(16, topPad + 16, 16, bottomPad),
            children: [
                _HeroCard(
                  icon: Icons.face,
                  title: 'Personas',
                  subtitle: personaInfo?.name ?? 'user',
                  avatarPath: personaInfo?.avatarPath,
                  isAvatar: true,
                  onTap: () => context.go('/tools/personas'),
                ),
                const SizedBox(height: 12),
                _HeroCard(
                  icon: Icons.tune,
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
                          icon: Icons.api,
                          title: 'API',
                          subtitle: 'Endpoints & models',
                          onTap: () => context.go('/tools/api'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GridTile(
                          icon: Icons.menu_book,
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
                        icon: Icons.code,
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
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isAvatar;
  final String? avatarPath;
  final VoidCallback onTap;

  const _HeroCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isAvatar = false,
    this.avatarPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
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
                        errorBuilder: (_, __, ___) => _AvatarGradientPlaceholder(subtitle: subtitle),
                      )
                    : _AvatarGradientPlaceholder(subtitle: subtitle),
              ),
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black38, Colors.black87],
                    ),
                  ),
                ),
              ),
            ] else ...[
              Positioned.fill(
                child: Container(
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
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: Colors.white70,
                        ),
                      ),
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
            color: Colors.white60,
          ),
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _GridTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 22),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.accent,
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
