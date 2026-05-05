import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/character_provider.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';

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
              child: GlazeAppBar(title: 'Menu'),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                _SectionHeader('Settings'),
                _MenuCard(
                  icon: Icons.settings_outlined,
                  title: 'App Settings',
                  subtitle: 'Interface, language, notifications',
                  onTap: () => context.go('/settings'),
                ),
                _MenuCard(
                  icon: Icons.palette_outlined,
                  title: 'Theme',
                  subtitle: 'Colors, fonts, background',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Theme settings coming soon'),
                      ),
                    );
                  },
                ),
                _SectionHeader('Data'),
                _MenuCard(
                  icon: Icons.cloud_outlined,
                  title: 'Cloud Sync',
                  subtitle: 'Sync your data across devices',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cloud sync coming soon')),
                    );
                  },
                ),
                _MenuCard(
                  icon: Icons.backup_outlined,
                  title: 'Backups',
                  subtitle: 'Import from Glaze JS backup',
                  onTap: () => _importGlzBackup(context, ref),
                ),
                _SectionHeader('Info'),
                _MenuCard(
                  icon: Icons.info_outline,
                  title: 'About',
                  subtitle: 'Glaze v0.1.0-alpha',
                  onTap: () => _showAbout(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importGlzBackup(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['glz', 'json'],
      dialogTitle: 'Select Glaze backup file',
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final filePath = file.path;
    if (filePath == null) return;

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _MigrationProgressDialog(),
    );

    try {
      final migration = ref.read(migrationServiceProvider);
      final migrationResult = await migration.importGlzBackup(filePath);

      if (!context.mounted) return;
      Navigator.of(context).pop();

      ref.invalidate(charactersProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported: ${migrationResult.characters} characters, '
            '${migrationResult.sessions} chats, '
            '${migrationResult.presets} presets, '
            '${migrationResult.apiConfigs} APIs, '
            '${migrationResult.personas} personas'
            '${migrationResult.errors > 0 ? ' (${migrationResult.errors} errors)' : ''}',
          ),
          duration: const Duration(seconds: 6),
          action: migrationResult.characters > 0
              ? SnackBarAction(
                  label: 'View',
                  onPressed: () => context.go('/'),
                )
              : null,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Glaze',
      applicationVersion: '0.1.0-alpha',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.auto_awesome, color: Colors.black, size: 28),
      ),
      children: [
        const Text('Flutter rewrite of Glaze — local AI roleplay client.'),
      ],
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

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

class _MigrationProgressDialog extends StatelessWidget {
  const _MigrationProgressDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Importing backup...',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'This may take a moment',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
