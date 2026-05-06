import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_colors.dart';
import 'chat_dialogs.dart';
import 'tokenizer_sheet.dart';

class MagicDrawerPanel extends ConsumerWidget {
  final String charId;
  const MagicDrawerPanel({super.key, required this.charId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Text(
                  'Quick Actions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MagicItem(
                  icon: Icons.tune,
                  label: 'Presets',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/tools/presets');
                  },
                ),
                _MagicItem(
                  icon: Icons.person,
                  label: 'Personas',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/tools/personas');
                  },
                ),
                _MagicItem(
                  icon: Icons.menu_book,
                  label: 'Lorebooks',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/tools/lorebooks');
                  },
                ),
                _MagicItem(
                  icon: Icons.api,
                  label: 'API',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/tools/api');
                  },
                ),
                _MagicItem(
                  icon: Icons.code,
                  label: 'Regex',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/tools/regex');
                  },
                ),
                _MagicItem(
                  icon: Icons.data_object,
                  label: 'Raw Prompt',
                  onTap: () {
                    Navigator.pop(context);
                    showRawPromptDialog(context, ref, charId);
                  },
                ),
                _MagicItem(
                  icon: Icons.pie_chart_outline,
                  label: 'Tokenizer',
                  onTap: () {
                    Navigator.pop(context);
                    showTokenizerSheet(context, charId);
                  },
                ),
                _MagicItem(
                  icon: Icons.face,
                  label: 'Character',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/character/$charId');
                  },
                ),
                _MagicItem(
                  icon: Icons.info_outline,
                  label: 'Context',
                  onTap: () {
                    Navigator.pop(context);
                    showTokenizerSheet(context, charId);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MagicItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MagicItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.accent, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
