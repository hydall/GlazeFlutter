import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_colors.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/menu')),
        title: const Text('Tools'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _ToolTile(
            icon: Icons.api,
            title: 'API',
            subtitle: 'Endpoints & models',
            color: const Color(0xFF4CAF50),
            onTap: () => context.go('/tools/api'),
          ),
          _ToolTile(
            icon: Icons.tune,
            title: 'Presets',
            subtitle: 'Generation presets',
            color: const Color(0xFF2196F3),
            onTap: () => context.go('/tools/presets'),
          ),
          _ToolTile(
            icon: Icons.menu_book,
            title: 'Lorebooks',
            subtitle: 'World info',
            color: const Color(0xFFFF9800),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lorebooks coming soon')),
              );
            },
          ),
          _ToolTile(
            icon: Icons.code,
            title: 'Regex',
            subtitle: 'Find & replace scripts',
            color: const Color(0xFF9C27B0),
            onTap: () => context.go('/tools/regex'),
          ),
          _ToolTile(
            icon: Icons.face,
            title: 'Personas',
            subtitle: 'Your identities',
            color: const Color(0xFFE91E63),
            onTap: () => context.go('/tools/personas'),
          ),
          _ToolTile(
            icon: Icons.help_outline,
            title: 'Glossary',
            subtitle: 'Help & terms',
            color: AppColors.textSecondary,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Glossary coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      leading: Icon(icon, color: color, size: 20),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}
