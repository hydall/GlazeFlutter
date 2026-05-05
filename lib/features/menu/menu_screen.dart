import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
                  subtitle: 'Create and restore backups',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Backups coming soon')),
                    );
                  },
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
