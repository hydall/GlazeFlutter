import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/theme_provider.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import 'app_settings_provider.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return GlazeScaffold(
      title: 'App Settings',
      onBack: () => context.go('/menu'),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) => ListView(
          children: [
            _SectionHeader('Input'),
            SwitchListTile(
              title: const Text('Enter to Send'),
              subtitle: const Text(
                'Enter key sends message instead of new line',
              ),
              value: s.enterToSend,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(enterToSend: v)),
            ),
            _SectionHeader('Chat'),
            SwitchListTile(
              title: const Text('Bubble Layout'),
              subtitle: const Text('Show messages as chat bubbles'),
              value: s.chatLayout == 'bubble',
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(chatLayout: v ? 'bubble' : 'default')),
            ),
            SwitchListTile(
              title: const Text('Group Dialogs'),
              subtitle: const Text('Group chat sessions by character'),
              value: s.groupDialogs,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(groupDialogs: v)),
            ),
            SwitchListTile(
              title: const Text('Disable Swipe Regeneration'),
              subtitle: const Text(
                'Disable swipe left/right for alternative responses',
              ),
              value: s.disableSwipeRegeneration,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(disableSwipeRegeneration: v)),
            ),
            _SectionHeader('Message Display'),
            SwitchListTile(
              title: const Text('Hide Message ID'),
              value: s.hideMessageId,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideMessageId: v)),
            ),
            SwitchListTile(
              title: const Text('Hide Generation Time'),
              value: s.hideGenerationTime,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideGenerationTime: v)),
            ),
            SwitchListTile(
              title: const Text('Hide Token Count'),
              value: s.hideTokenCount,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideTokenCount: v)),
            ),
            _SectionHeader('Theme'),
            ListTile(
              title: const Text('Theme Mode'),
              subtitle: Text(_themeModeLabel(ref.watch(themeProvider).mode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showThemeModePicker(context, ref),
            ),
            ListTile(
              title: const Text('Accent Color'),
              trailing: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: ref.watch(themeProvider).accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
              onTap: () => _showAccentPicker(context, ref),
            ),
            SwitchListTile(
              title: const Text('Battery Saver UI'),
              subtitle: const Text('Reduce animations and effects'),
              value: s.batterySaver,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(batterySaver: v)),
            ),
            SwitchListTile(
              title: const Text('Hide Tooltips'),
              value: s.hideTooltips,
              onChanged: (v) => ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(hideTooltips: v)),
            ),
            _SectionHeader('Language'),
            ListTile(
              title: const Text('Language'),
              subtitle: Text(s.language == 'en' ? 'English' : 'Русский'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguagePicker(context, ref, s),
            ),
          ],
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark: return 'Dark';
      case ThemeMode.light: return 'Light';
      case ThemeMode.system: return 'System';
    }
  }

  void _showThemeModePicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(themeProvider).mode;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme Mode'),
        children: ThemeMode.values.map((mode) => SimpleDialogOption(
          onPressed: () {
            Navigator.pop(ctx);
            ref.read(themeProvider.notifier).setMode(mode);
          },
          child: Row(children: [
            if (mode == current) const Icon(Icons.check, size: 18, color: AppColors.accent),
            if (mode == current) const SizedBox(width: 8),
            Text(_themeModeLabel(mode)),
          ]),
        )).toList(),
      ),
    );
  }

  void _showAccentPicker(BuildContext context, WidgetRef ref) {
    const presets = [
      Color(0xFF7996CE), Color(0xFFCE7979), Color(0xFF79CE96),
      Color(0xFFCEB479), Color(0xFFB479CE), Color(0xFF79CECE),
      Color(0xFF96CE79), Color(0xFFCE79B4), Color(0xFFFF9F43),
    ];
    final current = ref.read(themeProvider).accentColor;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Accent Color'),
        children: [
          Wrap(
            spacing: 12, runSpacing: 12,
            alignment: WrapAlignment.center,
            children: presets.map((c) => GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                ref.read(themeProvider.notifier).setAccentColor(c);
              },
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: c == current ? Border.all(color: Colors.white, width: 3) : null,
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, AppSettings s) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Language'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(language: 'en'));
            },
            child: const Text('English'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(appSettingsProvider.notifier)
                  .save(s.copyWith(language: 'ru'));
            },
            child: const Text('Русский'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
