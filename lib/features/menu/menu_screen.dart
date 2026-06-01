import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/onboarding_service.dart';
import '../../core/state/dev_mode_provider.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/widgets/glaze_scaffold.dart' show GlazeAppBar;
import '../../shared/widgets/menu_group.dart';
import '../backup/backup_screen.dart';
import '../cloud_sync/widgets/sync_sheet.dart';
import '../dev/menu_group_demo_screen.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navHeight = ref.watch(navHeightProvider);
    final topPad = MediaQuery.of(context).padding.top + 66.0;
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                      onTap: () => context.push('/menu/settings'),
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
                      onTap: () => showModalBottomSheet(
                        context: context,
                        useRootNavigator: true,
                        useSafeArea: true,
                        backgroundColor: Colors.transparent,
                        barrierColor: Colors.black54,
                        isScrollControlled: true,
                        builder: (_) => const BackupScreen(),
                      ),
                    ),
                    MenuItem(
                      icon: Icons.sync_rounded,
                      label: 'Cloud Sync',
                      onTap: () => showModalBottomSheet(
                        context: context,
                        useRootNavigator: true,
                        useSafeArea: true,
                        backgroundColor: Colors.transparent,
                        barrierColor: Colors.black54,
                        isScrollControlled: true,
                        builder: (_) => const SyncSheet(),
                      ),
                    ),
                  ],
                ),
                if (ref.watch(devModeProvider))
                  MenuGroup(
                    header: 'Dev',
                    items: [
                      MenuItem(
                        icon: Icons.widgets_outlined,
                        label: 'MenuGroup Demo',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const MenuGroupDemoScreen(),
                        )),
                      ),
                    ],
                  ),
                MenuGroup(
                  header: 'Info',
                  items: [
                    MenuItem(
                      icon: Icons.menu_book_rounded,
                      label: 'Glossary',
                      onTap: () => context.push('/menu/glossary'),
                    ),
                    MenuItem(
                      icon: Icons.info_outline_rounded,
                      label: 'About',
                      onTap: () => context.push('/menu/about'),
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
