import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GlazeFilterChipBar<T> extends StatelessWidget {
  final T current;
  final List<T> options;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onSelected;

  const GlazeFilterChipBar({
    super.key,
    required this.current,
    required this.options,
    required this.labelBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.map((option) {
            final selected = option == current;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(labelBuilder(option)),
                selected: selected,
                onSelected: (_) => onSelected(option),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: selected ? context.colors.accent : context.colors.textSecondary,
                ),
                selectedColor: context.colors.accent.withValues(alpha: 0.15),
                side: BorderSide(color: selected ? context.colors.accent : Colors.white12),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
