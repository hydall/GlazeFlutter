import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/onboarding_service.dart';
import '../../shared/widgets/glaze_error_dialog.dart';
import '../../core/state/dev_mode_provider.dart';
import '../../shared/shell/nav_height_provider.dart';
import '../../shared/shell/shell_header_provider.dart';
import '../../shared/widgets/menu_group.dart';
import '../backup/backup_screen.dart';
import '../catalog/widgets/janitor_login_sheet.dart';
import '../cloud_sync/widgets/sync_sheet.dart';
import '../dev/menu_group_demo_screen.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> with ShellHeaderMixin {
  @override
  int get headerBranchIndex => 3;

  @override
  ShellHeaderConfig buildShellHeader() =>
      const ShellHeaderConfig(title: 'Menu');

  @override
  Widget build(BuildContext context) {
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
                      onTap: () => showModalBottomSheet<void>(
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
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        useRootNavigator: true,
                        useSafeArea: true,
                        backgroundColor: Colors.transparent,
                        barrierColor: Colors.black54,
                        isScrollControlled: true,
                        builder: (_) => const SyncSheet(),
                      ),
                    ),
                    MenuItem(
                      icon: Icons.person_outline_rounded,
                      label: 'janitor_login_menu'.tr(),
                      onTap: () => showJanitorLoginSheet(context),
                    ),
                  ],
                ),
                if (ref.watch(devModeProvider))
                  MenuGroup(
                    header: 'Dev',
                    items: [
                      MenuSwitchItem(
                        label: 'Hide build date watermark',
                        value: ref.watch(hideBuildWatermarkProvider),
                        onChanged: (v) => ref
                            .read(hideBuildWatermarkProvider.notifier)
                            .set(v),
                      ),
                      MenuItem(
                        icon: Icons.widgets_outlined,
                        label: 'MenuGroup Demo',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const MenuGroupDemoScreen(),
                        )),
                      ),
                      MenuItem(
                        icon: Icons.warning_amber_rounded,
                        label: 'Test Error Dialog',
                        onTap: () => GlazeErrorDialog.show(
                          context,
                          Exception(
                            'HTTP 401: Invalid API key\n\n'
                            'The request was rejected by the remote server. '
                            'Please verify that your API key is correct and has '
                            'not expired. Keys can be revoked from the provider '
                            'dashboard at any time without notice.\n\n'
                            'Endpoint:  https://api.openai.com/v1/chat/completions\n'
                            'Model:     gpt-4o\n'
                            'Status:    401 Unauthorized\n'
                            'Request:   POST /v1/chat/completions\n'
                            'Trace-ID:  req_abc123def456ghi789\n\n'
                            '{"error":{"message":"Incorrect API key provided: '
                            'sk-proj-...xXxX. You can find your API key at '
                            'https://platform.openai.com/account/api-keys.",'
                            '"type":"invalid_request_error","param":null,'
                            '"code":"invalid_api_key"}}',
                          ),
                        ),
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
        ],
      ),
    );
  }
}
