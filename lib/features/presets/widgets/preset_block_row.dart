import 'package:flutter/material.dart';

import '../../../core/models/preset.dart';
import '../../../shared/theme/app_colors.dart';

IconData presetBlockRoleIcon(String role) {
  return switch (role) {
    'user' => Icons.person_outline,
    'assistant' => Icons.smart_toy_outlined,
    _ => Icons.storage_outlined,
  };
}

class PresetBlockRow extends StatelessWidget {
  final PresetBlock block;
  final int index;
  final bool isLast;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  const PresetBlockRow({
    super.key,
    required this.block,
    required this.index,
    required this.isLast,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: const Color(0x33808080),
            width: isLast ? 0 : 1,
          ),
        ),
      ),
      child: Opacity(
        opacity: block.enabled ? 1.0 : 0.5,
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 30,
                height: 44,
                child: Center(
                  child: Text(
                    '≡',
                    style: TextStyle(
                      fontSize: 20,
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            Icon(
              presetBlockRoleIcon(block.role),
              size: 16,
              color: context.cs.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        block.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: context.cs.onSurface,
                        ),
                      ),
                    ),
                    if (block.content.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '~${(block.content.length / 4).round()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 36,
              height: 44,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onEdit,
                  child: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Transform.scale(
                scale: 0.8,
                alignment: Alignment.centerRight,
                child: Switch(
                  value: block.enabled,
                  onChanged: onToggle,
                  activeThumbColor: context.cs.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
