import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../settings/app_settings_provider.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const _version = '0.1.0+1';

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appSettingsProvider).value?.language ?? 'en';
    final cs = context.cs;
    final topPad = MediaQuery.of(context).padding.top + 74.0;

    return GlazeScaffold(
      title: 'About',
      extendBodyBehindHeader: true,
      onBack: () => context.go('/menu'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 40),
        children: [
          _HeroCard(cs: cs),
          const SizedBox(height: 12),
          _CommunitySection(cs: cs, lang: lang, onLink: _openLink),
          const SizedBox(height: 12),
          _AuthorsSection(cs: cs),
          const SizedBox(height: 12),
          _LicenseSection(cs: cs),
        ],
      ),
    );
  }
}

// ─── Hero card ──────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final ColorScheme cs;
  const _HeroCard({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.15),
            cs.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          // Logo
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            padding: const EdgeInsets.all(14),
            child: SvgPicture.string(
              '''<svg viewBox="0 0 600 600" xmlns="http://www.w3.org/2000/svg"><g transform="translate(0,600) scale(0.1,-0.1)" fill="currentColor"><path d="M2799 4916 c-2 -2 -33 -7 -69 -10 -36 -3 -76 -8 -90 -11 -14 -2 -65 -12 -115 -21 -49 -9 -116 -25 -147 -35 -32 -11 -63 -19 -71 -19 -7 0 -31 -8 -53 -19 -21 -10 -55 -22 -74 -26 -38 -8 -146 -60 -285 -136 -43 -23 -118 -79 -123 -91 -2 -5 -10 -8 -18 -8 -8 0 -14 -4 -14 -10 0 -5 -6 -10 -13 -10 -8 0 -27 -13 -43 -30 -16 -16 -34 -30 -40 -30 -7 0 -30 -20 -52 -45 -23 -25 -45 -47 -49 -48 -12 -3 -133 -139 -133 -149 0 -5 -5 -6 -10 -3 -6 3 -10 1 -10 -6 0 -6 -36 -59 -80 -117 -44 -58 -80 -111 -80 -119 0 -7 -4 -13 -9 -13 -5 0 -12 -11 -15 -24 -3 -14 -12 -31 -19 -38 -6 -7 -17 -24 -24 -38 -6 -14 -30 -64 -52 -111 -23 -48 -41 -93 -41 -101 0 -8 -4 -18 -9 -23 -4 -6 -14 -32 -20 -60 -7 -27 -21 -72 -31 -100 -17 -43 -27 -94 -55 -255 -17 -100 -27 -293 -22 -435 6 -160 38 -417 56 -439 7 -9 17 -42 26 -86 11 -56 30 -120 41 -137 8 -12 14 -31 14 -41 0 -10 4 -22 8 -28 5 -5 17 -29 26 -54 36 -92 154 -293 216 -367 5 -7 10 -16 10 -22 0 -5 7 -11 15 -15 8 -3 15 -12 15 -20 0 -9 38 -54 85 -101 47 -47 85 -90 85 -96 0 -5 4 -9 9 -9 5 0 16 -6 23 -13 7 -6 38 -32 67 -57 30 -25 65 -54 77 -65 49 -43 92 -75 102 -75 5 0 15 -7 22 -15 7 -9 15 -13 18 -11 3 3 18 -4 34 -15 36 -26 190 -103 201 -101 4 1 7 -3 7 -8 0 -6 9 -10 19 -10 11 0 21 -4 23 -8 2 -6 140 -56 183 -67 6 -1 23 -7 38 -13 15 -7 51 -16 80 -21 29 -6 72 -14 97 -19 25 -6 68 -13 95 -16 28 -4 82 -11 120 -17 46 -7 343 -9 855 -7 725 3 787 4 815 20 17 10 37 18 46 18 20 0 95 36 119 58 11 9 32 28 47 42 15 14 31 24 35 23 5 -2 8 3 8 11 0 7 11 24 23 37 51 52 100 169 108 254 2 28 4 399 4 825 0 774 0 775 -23 858 -32 115 -48 143 -140 238 -63 65 -171 122 -272 143 -37 8 -1228 5 -1278 -3 -23 -4 -61 -14 -84 -22 -47 -16 -154 -86 -181 -118 -10 -11 -15 -15 -11 -7 5 9 3 12 -4 7 -7 -4 -12 -13 -12 -21 0 -7 -6 -20 -13 -27 -7 -7 -27 -37 -45 -66 -58 -94 -77 -226 -52 -362 10 -55 38 -144 40 -125 0 6 7 -3 15 -20 7 -16 27 -45 44 -64 17 -18 31 -37 31 -40 0 -4 15 -15 33 -26 17 -10 37 -23 42 -27 100 -81 181 -96 545 -97 266 -2 296 -3 308 -19 18 -24 13 -435 -6 -454 -9 -9 -112 -12 -460 -10 -246 1 -472 6 -502 11 -30 5 -58 7 -62 4 -5 -2 -8 -1 -8 4 0 4 -13 9 -30 10 -16 1 -51 11 -77 22 -26 10 -63 25 -82 32 -18 7 -49 23 -68 36 -19 13 -38 21 -43 18 -4 -3 -10 -2 -12 3 -1 4 -25 23 -53 42 -60 42 -181 163 -201 202 -8 15 -19 28 -23 28 -5 0 -12 13 -16 30 -4 16 -11 30 -16 30 -5 0 -9 6 -9 14 0 8 -3 16 -7 18 -13 5 -43 68 -43 88 0 10 -4 20 -9 22 -22 7 -70 238 -76 366 -9 172 11 297 68 432 5 14 12 36 14 49 2 13 11 30 19 38 7 8 14 23 14 34 0 11 5 17 10 14 6 -3 10 1 10 9 0 8 6 21 13 28 8 7 26 32 40 55 14 23 49 65 76 95 28 29 51 56 51 61 0 4 4 7 10 7 10 0 38 21 76 58 13 13 28 21 33 18 4 -3 16 3 26 14 10 11 24 20 32 20 7 0 13 5 13 11 0 6 7 9 15 6 8 -4 17 -2 20 3 4 6 15 10 26 10 10 0 19 4 19 8 0 8 81 37 165 58 74 20 230 24 910 27 704 2 775 4 823 20 94 32 208 99 218 130 3 9 12 17 20 17 8 0 14 4 14 8 0 5 8 17 18 28 36 42 70 110 88 177 26 100 8 307 -32 358 -6 8 -17 29 -25 47 -8 17 -17 32 -21 32 -5 0 -8 4 -8 9 0 11 -77 91 -88 91 -4 0 -19 11 -34 25 -15 14 -29 25 -30 26 -19 0 -48 14 -48 22 0 6 -3 8 -6 4 -3 -3 -27 4 -52 16 -47 22 -50 22 -842 25 -438 2 -798 1 -801 -2z"/></g></svg>''',
              width: 44,
              height: 44,
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Glaze',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'v${AboutScreen._version}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.primary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'AI roleplay chat client.\nLocal, novice-friendly, open-source.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Community links ────────────────────────────────────────────────────────

class _CommunitySection extends StatelessWidget {
  final ColorScheme cs;
  final String lang;
  final Future<void> Function(String url) onLink;

  const _CommunitySection({
    required this.cs,
    required this.lang,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return _Section(
      cs: cs,
      title: 'Community',
      icon: Icons.people_outline_rounded,
      child: Column(
        children: [
          if (lang == 'en')
            _LinkTile(
              cs: cs,
              svgAsset: 'assets/logos/discord.svg',
              label: 'Discord',
              subtitle: 'Join the community',
              brandColor: const Color(0xFF5865F2),
              onTap: () => onLink('https://discord.gg/jnGhd7p6Ht'),
            )
          else
            _LinkTile(
              cs: cs,
              svgAsset: 'assets/logos/telegram.svg',
              label: 'Telegram',
              subtitle: 'Присоединиться к сообществу',
              brandColor: const Color(0xFF2AABEE),
              onTap: () => onLink('https://t.me/glazeapp'),
            ),
          _LinkTile(
            cs: cs,
            svgAsset: 'assets/logos/github.svg',
            label: 'GitHub',
            subtitle: lang == 'ru' ? 'Исходный код' : 'Source code & issues',
            brandColor: cs.onSurface,
            onTap: () => onLink('https://github.com/hydall/Glaze'),
          ),
          if (lang == 'ru')
            _LinkTile(
              cs: cs,
              svgAsset: 'assets/logos/boosty.svg',
              label: 'Boosty',
              subtitle: 'Поддержать проект',
              brandColor: const Color(0xFFF15F2C),
              onTap: () => onLink('https://boosty.to/hydall'),
            )
          else
            _LinkTile(
              cs: cs,
              svgAsset: 'assets/logos/bmc-logo.svg',
              label: 'Buy Me a Coffee',
              subtitle: 'Support the project',
              brandColor: const Color(0xFFFFDD00),
              useIconColor: false,
              onTap: () => onLink('https://buymeacoffee.com/hydall'),
            ),
        ],
      ),
    );
  }
}

// ─── Authors ────────────────────────────────────────────────────────────────

class _AuthorsSection extends StatelessWidget {
  final ColorScheme cs;
  const _AuthorsSection({required this.cs});

  @override
  Widget build(BuildContext context) {
    return _Section(
      cs: cs,
      title: 'Authors',
      icon: Icons.code_rounded,
      child: Column(
        children: [
          _AuthorTile(
            cs: cs,
            name: 'hydall',
            role: 'Project Lead, UX/UI Designer, Programmer',
            initial: 'H',
            accentColor: const Color(0xFF7996CE),
          ),
          _AuthorTile(
            cs: cs,
            name: 'danvitv',
            role: 'Backend Architect, Programmer',
            initial: 'D',
            accentColor: const Color(0xFF79CE96),
          ),
        ],
      ),
    );
  }
}

// ─── License ────────────────────────────────────────────────────────────────

class _LicenseSection extends StatelessWidget {
  final ColorScheme cs;
  const _LicenseSection({required this.cs});

  @override
  Widget build(BuildContext context) {
    return _Section(
      cs: cs,
      title: 'License',
      icon: Icons.gavel_rounded,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'AGPL-3.0',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'GNU Affero General Public License v3.0\n\n'
              'You are free to use, modify, and distribute this software under the terms of the AGPL-3.0 license. '
              'Any modifications must also be made available under the same license.',
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: cs.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),

          ],
        ),
      ),
    );
  }
}

// ─── Shared building blocks ─────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final ColorScheme cs;
  final String title;
  final IconData icon;
  final Widget child;

  const _Section({
    required this.cs,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          child,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _LinkTile extends StatefulWidget {
  final ColorScheme cs;
  final String svgAsset;
  final String label;
  final String subtitle;
  final Color brandColor;
  final bool useIconColor;
  final VoidCallback onTap;

  const _LinkTile({
    required this.cs,
    required this.svgAsset,
    required this.label,
    required this.subtitle,
    required this.brandColor,
    this.useIconColor = true,
    required this.onTap,
  });

  @override
  State<_LinkTile> createState() => _LinkTileState();
}

class _LinkTileState extends State<_LinkTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _pressed
            ? widget.cs.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.brandColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(8),
              child: SvgPicture.asset(
                widget.svgAsset,
                width: 22,
                height: 22,
                colorFilter: widget.useIconColor
                    ? ColorFilter.mode(widget.brandColor, BlendMode.srcIn)
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: widget.cs.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: widget.cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorTile extends StatelessWidget {
  final ColorScheme cs;
  final String name;
  final String role;
  final String initial;
  final Color accentColor;

  const _AuthorTile({
    required this.cs,
    required this.name,
    required this.role,
    required this.initial,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor,
                  accentColor.withValues(alpha: 0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role,
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
