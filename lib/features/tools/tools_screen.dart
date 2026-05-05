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
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        children: [
          _ToolCard(
            icon: Icons.api,
            title: 'API',
            subtitle: 'Endpoints & models',
            color: const Color(0xFF4CAF50),
            onTap: () => context.go('/tools/api'),
          ),
          _ToolCard(
            icon: Icons.tune,
            title: 'Presets',
            subtitle: 'Generation presets',
            color: const Color(0xFF2196F3),
            onTap: () => context.go('/tools/presets'),
          ),
          _ToolCard(
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
          _ToolCard(
            icon: Icons.code,
            title: 'Regex',
            subtitle: 'Find & replace scripts',
            color: const Color(0xFF9C27B0),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Regex scripts coming soon')),
              );
            },
          ),
          _ToolCard(
            icon: Icons.face,
            title: 'Personas',
            subtitle: 'Your identities',
            color: const Color(0xFFE91E63),
            onTap: () => context.go('/tools/personas'),
          ),
          _ToolCard(
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

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 32),
              const Spacer(),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16)),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
