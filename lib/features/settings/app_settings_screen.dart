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
      title: _currentScreen == 'main' ? 'Settings' : 'Interface Settings',
      onBack: () {
        if (_currentScreen == 'interface') {
          setState(() => _currentScreen = 'main');
        } else {
          context.go('/menu');
        }
      },
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
          header: 'General',
          items: [
            MenuItem(
              icon: Icons.palette_outlined,
              label: 'Custom Theme',
              trailing: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ref.watch(themeProvider).accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              onTap: () => _showAccentPicker(context, ref),
            ),
            MenuItem(
              icon: Icons.brightness_6_outlined,
              label: 'Theme Mode',
              value: _themeModeLabel(ref.watch(themeProvider).mode),
              onTap: () => _showThemeModePicker(context, ref),
            ),
            MenuItem(
              icon: Icons.language_outlined,
              label: 'Language',
              value: s.language == 'en' ? 'English' : 'Русский',
              onTap: () => _showLanguagePicker(context, ref, s),
            ),
            MenuItem(
              icon: Icons.notifications_none_outlined,
              label: 'Notifications',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notification settings not implemented')),
                );
              },
            ),
            MenuItem(
              icon: Icons.settings_outlined,
              label: 'Interface Settings',
              trailing: const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF99A2AD)),
              onTap: () => setState(() => _currentScreen = 'interface'),
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
              label: 'Battery Saver UI',
              description: 'Applies lower-animation, lower-update chat rendering',
              value: s.batterySaver,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(batterySaver: v)),
            ),
            MenuSwitchItem(
              label: 'Enter to Send',
              description: 'Press Enter to send message. Applies only to physical keyboards.',
              value: s.enterToSend,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(enterToSend: v)),
            ),
            MenuSwitchItem(
              label: 'Virtual Keyboard Send',
              description: 'Show Send button instead of Enter on virtual keyboards',
              value: s.virtualKeyboardSend,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(virtualKeyboardSend: v)),
            ),
          ],
        ),
        MenuGroup(
          header: 'Interface Settings',
          items: [
            MenuSwitchItem(
              label: 'Group Dialogs',
              description: 'Groups all sessions by character, sorted by latest message',
              value: s.groupDialogs,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(groupDialogs: v)),
            ),
            MenuSwitchItem(
              label: 'Hide Tooltips',
              description: 'Hides contextual help buttons (?) across the app',
              value: s.hideTooltips,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideTooltips: v)),
            ),
          ],
        ),
        MenuGroup(
          header: 'Message Settings',
          items: [
            MenuSwitchItem(
              label: 'Disable Swipe Regeneration',
              description: 'Disables regenerating messages by swiping left',
              value: s.disableSwipeRegeneration,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(disableSwipeRegeneration: v)),
            ),
            MenuItem(
              label: 'Chat Layout',
              value: s.chatLayout == 'bubble' ? 'Bubbles' : 'Default',
              onTap: () => _showLayoutPicker(context, ref, s),
            ),
            MenuSwitchItem(
              label: 'Hide Message ID',
              description: 'Hides the unique message identifier in the chat interface',
              value: s.hideMessageId,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideMessageId: v)),
            ),
            MenuSwitchItem(
              label: 'Hide Gen Time',
              description: 'Hides the generation time statistics for AI messages',
              value: s.hideGenerationTime,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideGenerationTime: v)),
            ),
            MenuSwitchItem(
              label: 'Hide Token Count',
              description: 'Hides token usage statistics attached to messages',
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
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _showThemeModePicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(themeProvider).mode;
    GlazeBottomSheet.show(
      context,
      title: 'Theme Mode',
      items: ThemeMode.values
          .map((mode) => BottomSheetItem(
                label: _themeModeLabel(mode),
                icon: mode == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                iconColor:
                    mode == current ? context.colors.accent : context.colors.textSecondary,
                onTap: () {
                  Navigator.pop(context);
                  ref.read(themeProvider.notifier).setMode(mode);
                },
              ))
          .toList(),
    );
  }

  void _showAccentPicker(BuildContext context, WidgetRef ref) {
    const presets = [
      Color(0xFF7996CE),
      Color(0xFFCE7979),
      Color(0xFF79CE96),
      Color(0xFFCEB479),
      Color(0xFFB479CE),
      Color(0xFF79CECE),
      Color(0xFF96CE79),
      Color(0xFFCE79B4),
      Color(0xFFFF9F43),
    ];
    final current = ref.read(themeProvider).accentColor;
    GlazeBottomSheet.show(
      context,
      title: 'Accent Color',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: presets
              .map((c) => GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(themeProvider.notifier).setAccentColor(c);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: c.value == current.value
                            ? Border.all(color: Colors.white, width: 3)
                            : Border.all(color: Colors.white24, width: 1),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, AppSettings s) {
    GlazeBottomSheet.show(
      context,
      title: 'Language',
      items: [
        BottomSheetItem(
          label: 'English',
          icon: s.language == 'en'
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor:
              s.language == 'en' ? context.colors.accent : context.colors.textSecondary,
          onTap: () {
            Navigator.pop(context);
            ref.read(appSettingsProvider.notifier).save(s.copyWith(language: 'en'));
          },
        ),
        BottomSheetItem(
          label: 'Русский',
          icon: s.language == 'ru'
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor:
              s.language == 'ru' ? context.colors.accent : context.colors.textSecondary,
          onTap: () {
            Navigator.pop(context);
            ref.read(appSettingsProvider.notifier).save(s.copyWith(language: 'ru'));
          },
        ),
      ],
    );
  }

  void _showLayoutPicker(BuildContext context, WidgetRef ref, AppSettings s) {
    GlazeBottomSheet.show(
      context,
      title: 'Chat Layout',
      items: [
        BottomSheetItem(
          label: 'Default',
          icon: s.chatLayout == 'default'
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor: s.chatLayout == 'default'
              ? context.colors.accent
              : context.colors.textSecondary,
          onTap: () {
            Navigator.pop(context);
            ref
                .read(appSettingsProvider.notifier)
                .save(s.copyWith(chatLayout: 'default'));
          },
        ),
        BottomSheetItem(
          label: 'Bubbles',
          icon: s.chatLayout == 'bubble'
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
          iconColor: s.chatLayout == 'bubble'
              ? context.colors.accent
              : context.colors.textSecondary,
          onTap: () {
            Navigator.pop(context);
            ref
                .read(appSettingsProvider.notifier)
                .save(s.copyWith(chatLayout: 'bubble'));
          },
        ),
      ],
    );
  }
}
