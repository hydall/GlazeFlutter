import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../settings/app_settings_provider.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: const GlazeAppBar(title: 'Menu'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── Settings group ─────────────────────────────────────────
                _MenuGroup(
                  header: 'Settings',
                  items: [
                    _MenuItem(
                      icon: Icons.settings_outlined,
                      label: 'App Settings',
                      onTap: () => context.go('/settings'),
                    ),
                    _MenuItem(
                      icon: Icons.replay_rounded,
                      label: 'Replay Onboarding',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Onboarding coming soon'),
                          ),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.backup_outlined,
                      label: 'Backups',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Backups coming soon')),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.sync_rounded,
                      label: 'Cloud Sync',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cloud sync coming soon'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                // ── Info group ─────────────────────────────────────────────
                _MenuGroup(
                  header: 'Info',
                  items: [
                    _MenuItem(
                      icon: Icons.info_outline_rounded,
                      label: 'About',
                      onTap: () => _showAbout(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context, WidgetRef ref) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const _AboutOverlay();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _AboutOverlay extends ConsumerWidget {
  const _AboutOverlay();

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final lang = settingsAsync.value?.language ?? 'en';
    const version = '0.1.0+1';

    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: const TextStyle(
          decoration: TextDecoration.none,
          fontFamily: 'Inter', // Assuming standard project font
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Close button
                    Positioned(
                      top: 14,
                      right: 14,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),

                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 28),
                        // Logo
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: SvgPicture.string(
                            '''<svg viewBox="0 0 600 600" xmlns="http://www.w3.org/2000/svg"><g transform="translate(0,600) scale(0.1,-0.1)" fill="currentColor"><path d="M2799 4916 c-2 -2 -33 -7 -69 -10 -36 -3 -76 -8 -90 -11 -14 -2 -65 -12 -115 -21 -49 -9 -116 -25 -147 -35 -32 -11 -63 -19 -71 -19 -7 0 -31 -8 -53 -19 -21 -10 -55 -22 -74 -26 -38 -8 -146 -60 -285 -136 -43 -23 -118 -79 -123 -91 -2 -5 -10 -8 -18 -8 -8 0 -14 -4 -14 -10 0 -5 -6 -10 -13 -10 -8 0 -27 -13 -43 -30 -16 -16 -34 -30 -40 -30 -7 0 -30 -20 -52 -45 -23 -25 -45 -47 -49 -48 -12 -3 -133 -139 -133 -149 0 -5 -5 -6 -10 -3 -6 3 -10 1 -10 -6 0 -6 -36 -59 -80 -117 -44 -58 -80 -111 -80 -119 0 -7 -4 -13 -9 -13 -5 0 -12 -11 -15 -24 -3 -14 -12 -31 -19 -38 -6 -7 -17 -24 -24 -38 -6 -14 -30 -64 -52 -111 -23 -48 -41 -93 -41 -101 0 -8 -4 -18 -9 -23 -4 -6 -14 -32 -20 -60 -7 -27 -21 -72 -31 -100 -17 -43 -27 -94 -55 -255 -17 -100 -27 -293 -22 -435 6 -160 38 -417 56 -439 7 -9 17 -42 26 -86 11 -56 30 -120 41 -137 8 -12 14 -31 14 -41 0 -10 4 -22 8 -28 5 -5 17 -29 26 -54 36 -92 154 -293 216 -367 5 -7 10 -16 10 -22 0 -5 7 -11 15 -15 8 -3 15 -12 15 -20 0 -9 38 -54 85 -101 47 -47 85 -90 85 -96 0 -5 4 -9 9 -9 5 0 16 -6 23 -13 7 -6 38 -32 67 -57 30 -25 65 -54 77 -65 49 -43 92 -75 102 -75 5 0 15 -7 22 -15 7 -9 15 -13 18 -11 3 3 18 -4 34 -15 36 -26 190 -103 201 -101 4 1 7 -3 7 -8 0 -6 9 -10 19 -10 11 0 21 -4 23 -8 2 -6 140 -56 183 -67 6 -1 23 -7 38 -13 15 -7 51 -16 80 -21 29 -6 72 -14 97 -19 25 -6 68 -13 95 -16 28 -4 82 -11 120 -17 46 -7 343 -9 855 -7 725 3 787 4 815 20 17 10 37 18 46 18 20 0 95 36 119 58 11 9 32 28 47 42 15 14 31 24 35 23 5 -2 8 3 8 11 0 7 11 24 23 37 51 52 100 169 108 254 2 28 4 399 4 825 0 774 0 775 -23 858 -32 115 -48 143 -140 238 -63 65 -171 122 -272 143 -37 8 -1228 5 -1278 -3 -23 -4 -61 -14 -84 -22 -47 -16 -154 -86 -181 -118 -10 -11 -15 -15 -11 -7 5 9 3 12 -4 7 -7 -4 -12 -13 -12 -21 0 -7 -6 -20 -13 -27 -7 -7 -27 -37 -45 -66 -58 -94 -77 -226 -52 -362 10 -55 38 -144 40 -125 0 6 7 -3 15 -20 7 -16 27 -45 44 -64 17 -18 31 -37 31 -40 0 -4 15 -15 33 -26 17 -10 37 -23 42 -27 100 -81 181 -96 545 -97 266 -2 296 -3 308 -19 18 -24 13 -435 -6 -454 -9 -9 -112 -12 -460 -10 -246 1 -472 6 -502 11 -30 5 -58 7 -62 4 -5 -2 -8 -1 -8 4 0 4 -13 9 -30 10 -16 1 -51 11 -77 22 -26 10 -63 25 -82 32 -18 7 -49 23 -68 36 -19 13 -38 21 -43 18 -4 -3 -10 -2 -12 3 -1 4 -25 23 -53 42 -60 42 -181 163 -201 202 -8 15 -19 28 -23 28 -5 0 -12 13 -16 30 -4 16 -11 30 -16 30 -5 0 -9 6 -9 14 0 8 -3 16 -7 18 -13 5 -43 68 -43 88 0 10 -4 20 -9 22 -22 7 -70 238 -76 366 -9 172 11 297 68 432 5 14 12 36 14 49 2 13 11 30 19 38 7 8 14 23 14 34 0 11 5 17 10 14 6 -3 10 1 10 9 0 8 6 21 13 28 8 7 26 32 40 55 14 23 49 65 76 95 28 29 51 56 51 61 0 4 4 7 10 7 10 0 38 21 76 58 13 13 28 21 33 18 4 -3 16 3 26 14 10 11 24 20 32 20 7 0 13 5 13 11 0 6 7 9 15 6 8 -4 17 -2 20 3 4 6 15 10 26 10 10 0 19 4 19 8 0 8 81 37 165 58 74 20 230 24 910 27 704 2 775 4 823 20 94 32 208 99 218 130 3 9 12 17 20 17 8 0 14 4 14 8 0 5 8 17 18 28 36 42 70 110 88 177 26 100 8 307 -32 358 -6 8 -17 29 -25 47 -8 17 -17 32 -21 32 -5 0 -8 4 -8 9 0 11 -77 91 -88 91 -4 0 -19 11 -34 25 -15 14 -29 25 -30 26 -19 0 -48 14 -48 22 0 6 -3 8 -6 4 -3 -3 -27 4 -52 16 -47 22 -50 22 -842 25 -438 2 -798 1 -801 -2z" /></g></svg>''',
                            width: 48,
                            height: 48,
                            fit: BoxFit.contain,
                            colorFilter: const ColorFilter.mode(
                              AppColors.accent,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // App Name
                        const Text(
                          'Glaze',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        // Version
                        const Text(
                          version,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Action buttons
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: Column(
                            children: [
                              // Discord / Telegram
                              if (lang == 'en')
                                _ActionButton(
                                  label: 'Discord',
                                  color: const Color(0xFF5865F2),
                                  iconAsset: 'assets/logos/discord.svg',
                                  onTap: () => _openLink(
                                    'https://discord.gg/jnGhd7p6Ht',
                                  ),
                                )
                              else
                                _ActionButton(
                                  label: 'Telegram',
                                  color: const Color(0xFF2AABEE),
                                  iconAsset: 'assets/logos/telegram.svg',
                                  onTap: () =>
                                      _openLink('https://t.me/glazeapp'),
                                ),

                              const SizedBox(height: 12),

                              // GitHub
                              _ActionButton(
                                label: 'GitHub',
                                color: const Color(0xFF24292E),
                                iconAsset: 'assets/logos/github.svg',
                                onTap: () => _openLink(
                                  'https://github.com/hydall/Glaze',
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Boosty / BMC
                              if (lang == 'ru')
                                _ActionButton(
                                  label: 'Boosty',
                                  color: const Color(0xFFF15F2C),
                                  iconAsset: 'assets/logos/boosty.svg',
                                  onTap: () =>
                                      _openLink('https://boosty.to/hydall'),
                                )
                              else
                                _ActionButton(
                                  label: 'Buy Me a Coffee',
                                  color: const Color(0xFFFFDD00),
                                  textColor: const Color(0xFF0D0C22),
                                  iconAsset: 'assets/logos/bmc-logo.svg',
                                  useIconColor: false,
                                  onTap: () => _openLink(
                                    'https://buymeacoffee.com/hydall',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
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

class _ActionButton extends StatefulWidget {
  final String label;
  final Color color;
  final Color textColor;
  final String iconAsset;
  final bool useIconColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    this.textColor = Colors.white,
    required this.iconAsset,
    this.useIconColor = true,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
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
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                widget.iconAsset,
                width: 22,
                height: 22,
                colorFilter: widget.useIconColor
                    ? ColorFilter.mode(widget.textColor, BlendMode.srcIn)
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu Group (section-header + items)
// ─────────────────────────────────────────────────────────────────────────────

class _MenuGroup extends StatelessWidget {
  final String header;
  final List<_MenuItem> items;

  const _MenuGroup({required this.header, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(header),
            ...items,
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu Item (Icon + label)
// ─────────────────────────────────────────────────────────────────────────────

class _MenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
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
            ? AppColors.accent.withOpacity(0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(widget.icon, size: 22, color: AppColors.accent),
            const SizedBox(width: 16),
            Text(
              widget.label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
