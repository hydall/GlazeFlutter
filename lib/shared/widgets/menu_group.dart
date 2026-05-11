import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';

class MenuGroup extends StatelessWidget {
  final String? header;
  final List<Widget> items;

  const MenuGroup({super.key, this.header, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(header!,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ...items,
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class MenuItem extends StatefulWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback onTap;

  const MenuItem({
    super.key,
    this.icon,
    this.iconWidget,
    required this.label,
    this.value,
    this.trailing,
    required this.onTap,
  });

  @override
  State<MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<MenuItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _pressed
            ? context.colors.accent.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            if (widget.iconWidget != null)
              SizedBox(width: 22, height: 22, child: widget.iconWidget)
            else if (widget.icon != null)
              Icon(widget.icon, size: 22, color: const Color(0xFF99A2AD)),
            if (widget.icon != null || widget.iconWidget != null)
              const SizedBox(width: 16),
            Expanded(
              child: Text(widget.label,
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w400)),
            ),
            if (widget.value != null)
              Text(widget.value!,
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 15)),
            if (widget.trailing != null) widget.trailing!,
            if (widget.value != null || widget.trailing != null)
              const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class MenuSwitchItem extends StatelessWidget {
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const MenuSwitchItem({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w400)),
                  if (description != null) ...[
                    const SizedBox(height: 1),
                    Text(description!,
                        style: const TextStyle(
                            color: Color(0xFF99A2AD),
                            fontSize: 11,
                            fontWeight: FontWeight.normal)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: context.colors.accent,
              activeTrackColor: context.colors.accent.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
