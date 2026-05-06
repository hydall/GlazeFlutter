import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/shell/nav_height_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/menu_group.dart';
import '../../shared/widgets/glaze_toast.dart';
import 'about_overlay.dart';

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
              padding: EdgeInsets.only(
                top: 8,
                bottom: ref.watch(navHeightProvider) + 20,
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
                      onTap: () {
                        GlazeToast.show(context, 'Onboarding coming soon');
                      },
                    ),
                    MenuItem(
                      icon: Icons.backup_outlined,
                      label: 'Backups',
                      onTap: () {
                        GlazeToast.show(context, 'Backups coming soon');
                      },
                    ),
                    MenuItem(
                      icon: Icons.sync_rounded,
                      label: 'Cloud Sync',
                      onTap: () {
                        GlazeToast.show(context, 'Cloud sync coming soon');
                      },
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
          ),
        ],
      ),
    );
  }
}
