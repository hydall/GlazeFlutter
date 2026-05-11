import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/onboarding_service.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart' show GlazeAppBar;
import '../../shared/widgets/menu_group.dart';
import 'about_overlay.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navHeight = ref.watch(navHeightProvider);
    final topPad = MediaQuery.of(context).padding.top + 66.0;
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(
              top: topPad + 8,
              bottom: navHeight + 20,
            ),
            children: [
                MenuGroup(
                  header: 'Settings',
                  items: [
                    MenuItem(
                      icon: Icons.settings_outlined,
                      label: 'App Settings',
                      onTap: () => context.go('/settings'),
                    ),
                    MenuItem(
                      icon: Icons.replay_rounded,
                      label: 'Replay Onboarding',
                      onTap: () async {
                        await resetOnboarding();
                        if (context.mounted) showOnboarding(context);
                      },
                    ),
                    MenuItem(
                      icon: Icons.backup_outlined,
                      label: 'Backups',
                      onTap: () => context.go('/backup'),
                    ),
                    MenuItem(
                      icon: Icons.sync_rounded,
                      label: 'Cloud Sync',
                      onTap: () => context.go('/sync'),
                    ),
                  ],
                ),
                MenuGroup(
                  header: 'Info',
                  items: [
                    MenuItem(
                      icon: Icons.info_outline_rounded,
                      label: 'About',
                      onTap: () => showGlazeAbout(context),
                    ),
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
                child: const GlazeAppBar(title: 'Menu'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
