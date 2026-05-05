import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_colors.dart';
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
            _SectionHeader('Interface'),
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
