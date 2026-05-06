import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/menu_group.dart';
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                MenuGroup(header: 'Settings', items: [
                  MenuItem(icon: Icons.settings_outlined, label: 'App Settings', onTap: () => context.go('/settings')),
                  MenuItem(icon: Icons.replay_rounded, label: 'Replay Onboarding', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding coming soon')));
                  }),
                  MenuItem(icon: Icons.backup_outlined, label: 'Backups', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backups coming soon')));
                  }),
                  MenuItem(icon: Icons.sync_rounded, label: 'Cloud Sync', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cloud sync coming soon')));
                  }),
                ]),
                MenuGroup(header: 'Info', items: [
                  MenuItem(icon: Icons.info_outline_rounded, label: 'About', onTap: () => showGlazeAbout(context)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
