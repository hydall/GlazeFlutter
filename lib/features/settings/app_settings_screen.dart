import 'package:app_settings/app_settings.dart' as sys_settings;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/theme_provider.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/menu_group.dart';
import 'app_settings_provider.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  String _currentScreen = 'main';

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return GlazeScaffold(
      title: _currentScreen == 'main' ? 'section_settings'.tr() : 'menu_interface_settings'.tr(),
      onBack: () {
        if (_currentScreen == 'interface') {
          setState(() => _currentScreen = 'main');
        } else {
          context.go('/menu');
        }
      },
      showBackground: false,
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _currentScreen == 'main'
              ? _buildMainSettings(context, s)
              : _buildInterfaceSettings(context, s),
        ),
      ),
    );
  }

  Widget _buildMainSettings(BuildContext context, AppSettings s) {
    return ListView(
      key: const ValueKey('main'),
      children: [
        const SizedBox(height: 12),
        MenuGroup(
          header: 'tab_general'.tr(),
          items: [
            MenuItem(
              icon: Icons.palette_outlined,
              label: 'theme_presets'.tr(),
              trailing: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ref.watch(themeProvider).accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              onTap: () => context.push('/menu/themes'),
            ),
            MenuItem(
              icon: Icons.brightness_6_outlined,
              label: 'theme_title'.tr(),
              value: _themeModeLabel(ref.watch(themeProvider).mode),
              onTap: () => _showThemeModePicker(context, ref),
            ),
            MenuItem(
              icon: Icons.language_outlined,
              label: 'menu_language'.tr(),
              value: s.language == 'en' ? 'English' : 'Русский',
              onTap: () => _showLanguagePicker(context, ref, s),
            ),
            MenuItem(
              icon: Icons.notifications_none_outlined,
              label: 'menu_notifications'.tr(),
              onTap: () => sys_settings.AppSettings.openAppSettings(
                type: sys_settings.AppSettingsType.notification,
              ),
            ),
            MenuItem(
              icon: Icons.settings_outlined,
              label: 'menu_interface_settings'.tr(),
              trailing: const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF99A2AD)),
              onTap: () => setState(() => _currentScreen = 'interface'),
            ),
            MenuItem(
              icon: Icons.extension_outlined,
              label: 'Расширения',
              trailing: const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF99A2AD)),
              onTap: () => context.push('/extensions'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInterfaceSettings(BuildContext context, AppSettings s) {
    return ListView(
      key: const ValueKey('interface'),
      children: [
        const SizedBox(height: 12),
        MenuGroup(
          items: [
            MenuSwitchItem(
              label: 'menu_battery_saver_ui'.tr(),
              description: 'desc_battery_saver_ui'.tr(),
              value: s.batterySaver,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(batterySaver: v)),
            ),
            MenuSwitchItem(
              label: 'menu_enter_to_send'.tr(),
              description: 'desc_enter_to_send'.tr(),
              value: s.enterToSend,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(enterToSend: v)),
            ),
            MenuSwitchItem(
              label: 'menu_virtual_keyboard_send'.tr(),
              description: 'desc_virtual_keyboard_send'.tr(),
              value: s.virtualKeyboardSend,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(virtualKeyboardSend: v)),
            ),
          ],
        ),
        MenuGroup(
          header: 'menu_interface_settings'.tr(),
          items: [
            MenuSwitchItem(
              label: 'menu_dialog_grouping'.tr(),
              description: 'desc_dialog_grouping'.tr(),
              value: s.groupDialogs,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(groupDialogs: v)),
            ),
            MenuSwitchItem(
              label: 'menu_hide_help_tips'.tr(),
              description: 'desc_hide_help_tips'.tr(),
              value: s.hideTooltips,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideTooltips: v)),
            ),
            MenuSwitchItem(
              label: 'menu_show_our_picks'.tr(),
              description: 'desc_show_our_picks'.tr(),
              value: s.showOurPicks,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(showOurPicks: v)),
            ),
          ],
        ),
        MenuGroup(
          header: 'menu_message_settings'.tr(),
          items: [
            MenuSwitchItem(
              label: 'menu_disable_swipe_regeneration'.tr(),
              description: 'desc_disable_swipe_regeneration'.tr(),
              value: s.disableSwipeRegeneration,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(disableSwipeRegeneration: v)),
            ),
            MenuItem(
              label: 'menu_chat_layout'.tr(),
              value: ref.watch(themeProvider).activePreset.chatLayout == 'bubble'
                  ? 'layout_bubble'.tr()
                  : 'layout_default'.tr(),
              onTap: () => _showLayoutPicker(context, ref),
            ),
            MenuSwitchItem(
              label: 'menu_hide_msg_id'.tr(),
              description: 'desc_hide_msg_id'.tr(),
              value: s.hideMessageId,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideMessageId: v)),
            ),
            MenuSwitchItem(
              label: 'menu_hide_gen_time'.tr(),
              description: 'desc_hide_gen_time'.tr(),
              value: s.hideGenerationTime,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideGenerationTime: v)),
            ),
            MenuSwitchItem(
              label: 'menu_hide_token_count'.tr(),
              description: 'desc_hide_token_count'.tr(),
              value: s.hideTokenCount,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideTokenCount: v)),
            ),
          ],
        ),
      ],
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'theme_dark'.tr();
      case ThemeMode.light:
        return 'theme_light'.tr();
      case ThemeMode.system:
        return 'theme_system'.tr();
    }
  }

  void _showThemeModePicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(themeProvider).mode;
    GlazeBottomSheet.show<void>(
      context,
      title: 'theme_title'.tr(),
      items: ThemeMode.values
          .map((mode) => BottomSheetItem(
                label: _themeModeLabel(mode),
                icon: mode == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                iconColor:
                    mode == current ? context.cs.primary : context.cs.onSurfaceVariant,
                onTap: () {
                  Navigator.of(context, rootNavigator: true).pop();
                  ref.read(themeProvider.notifier).setMode(mode);
                },
              ))
          .toList(),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, AppSettings s) {
    GlazeBottomSheet.show<void>(
      context,
      title: 'menu_language'.tr(),
      items: [
        BottomSheetItem(
          label: 'English',
          icon: s.language == 'en'
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor:
              s.language == 'en' ? context.cs.primary : context.cs.onSurfaceVariant,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref.read(appSettingsProvider.notifier).save(s.copyWith(language: 'en'));
          },
        ),
        BottomSheetItem(
          label: 'Русский',
          icon: s.language == 'ru'
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor:
              s.language == 'ru' ? context.cs.primary : context.cs.onSurfaceVariant,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref.read(appSettingsProvider.notifier).save(s.copyWith(language: 'ru'));
          },
        ),
      ],
    );
  }

  void _showLayoutPicker(BuildContext context, WidgetRef ref) {
    final preset = ref.read(themeProvider).activePreset;
    final current = preset.chatLayout;
    GlazeBottomSheet.show<void>(
      context,
      title: 'menu_chat_layout'.tr(),
      items: [
        BottomSheetItem(
          label: 'layout_default'.tr(),
          icon: current == 'default'
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor: current == 'default'
              ? context.cs.primary
              : context.cs.onSurfaceVariant,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref
                .read(themeProvider.notifier)
                .updatePreset(preset.copyWith(chatLayout: 'default'));
          },
        ),
        BottomSheetItem(
          label: 'layout_bubble'.tr(),
          icon: current == 'bubble'
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor: current == 'bubble'
              ? context.cs.primary
              : context.cs.onSurfaceVariant,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            ref
                .read(themeProvider.notifier)
                .updatePreset(preset.copyWith(chatLayout: 'bubble'));
          },
        ),
      ],
    );
  }
}
