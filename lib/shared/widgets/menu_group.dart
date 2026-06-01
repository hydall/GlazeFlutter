import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import 'glass_surface.dart';
import 'help_tip.dart';

enum MenuGroupHeaderVariant {
  standard,
  accentCaps,
}

// ── Group container ────────────────────────────────────────────────────────────

class MenuGroup extends StatelessWidget {
  final String? header;
  final String? helpTerm;
  final List<Widget> items;
  final MenuGroupHeaderVariant headerVariant;

  /// Kept for call-site compatibility; no longer affects visual style.
  // ignore: avoid_unused_constructor_parameters
  final bool compact;

  const MenuGroup({
    super.key,
    this.header,
    this.helpTerm,
    required this.items,
    this.headerVariant = MenuGroupHeaderVariant.standard,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.cs.outlineVariant),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null)
              _buildHeader(context),
            ...items,
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isAccentCaps = headerVariant == MenuGroupHeaderVariant.accentCaps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isAccentCaps ? header!.toUpperCase() : header!,
            style: TextStyle(
              color: isAccentCaps ? context.cs.primary : context.cs.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: isAccentCaps ? 13 : 18,
              letterSpacing: isAccentCaps ? 0.3 : null,
            ),
          ),
          if (helpTerm != null) HelpTip(term: helpTerm!),
        ],
      ),
    );
  }
}

// ── Sub-header ─────────────────────────────────────────────────────────────────

class MenuSubHeader extends StatelessWidget {
  final String label;

  const MenuSubHeader(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: context.cs.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Navigation item ────────────────────────────────────────────────────────────

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
            ? context.cs.primary.withValues(alpha: 0.08)
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
                      color: context.cs.onSurfaceVariant,
                      fontSize: 16,
                      fontWeight: FontWeight.w400)),
            ),
            if (widget.value != null)
              Text(widget.value!,
                  style: TextStyle(
                      color: context.cs.onSurfaceVariant, fontSize: 14)),
            if (widget.trailing != null) widget.trailing!,
            if (widget.value != null || widget.trailing != null)
              const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ── Switch item ────────────────────────────────────────────────────────────────

class MenuSwitchItem extends StatelessWidget {
  final String label;
  final String? helpTerm;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const MenuSwitchItem({
    super.key,
    required this.label,
    this.helpTerm,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: TextStyle(
                              color: context.cs.onSurfaceVariant,
                              fontSize: 16,
                              fontWeight: FontWeight.w400)),
                      if (helpTerm != null) HelpTip(term: helpTerm!),
                    ],
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 1),
                    Text(description!,
                        style: const TextStyle(
                            color: Color(0xFF99A2AD),
                            fontSize: 12,
                            fontWeight: FontWeight.normal)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: context.cs.primary,
              activeTrackColor: context.cs.primary.withValues(alpha: 0.5),
              trackOutlineColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.transparent
                    : context.cs.outlineVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Text field item ────────────────────────────────────────────────────────────

class MenuFieldItem extends StatelessWidget {
  final String label;
  final String? helpTerm;
  final TextEditingController controller;
  final String? placeholder;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final VoidCallback? onExpand;

  const MenuFieldItem({
    super.key,
    required this.label,
    this.helpTerm,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.maxLines = 1,
    this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                      color: context.cs.onSurfaceVariant, fontSize: 13)),
              if (helpTerm != null) HelpTip(term: helpTerm!, size: 14),
              const Spacer(),
              if (onExpand != null)
                GestureDetector(
                  onTap: onExpand,
                  child: Icon(Icons.open_in_full,
                      size: 16, color: context.cs.primary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            maxLines: maxLines,
            style: TextStyle(color: context.cs.onSurface, fontSize: 15),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: TextStyle(
                color: context.cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: const Color(0xFF252525),
              suffixIcon: suffix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: context.cs.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Range slider item ──────────────────────────────────────────────────────────

class MenuRangeItem extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const MenuRangeItem({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions = 200,
  });

  String get _display {
    final s = value.toStringAsFixed(2);
    final trimmed = s.replaceAll(RegExp(r'0+$'), '');
    return trimmed.endsWith('.') ? '${trimmed}0' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: context.cs.onSurface, fontSize: 15)),
              ),
              Text(
                _display,
                style: TextStyle(
                  color: context.cs.onSurfaceVariant,
                  fontSize: 14,
                  fontVariations: const [FontVariation('wght', 500)],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.cs.primary,
              thumbColor: context.cs.primary,
              inactiveTrackColor: context.cs.primary.withValues(alpha: 0.18),
              overlayColor: context.cs.primary.withValues(alpha: 0.1),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Script list item ──────────────────────────────────────────────────────────

/// List item for named scripts (regex, lorebook, etc.) with a toggle switch
/// and a trailing more-vert action. Visual style matches [MenuItem].
class MenuScriptItem extends StatefulWidget {
  final String name;
  final String? subtitle;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const MenuScriptItem({
    super.key,
    required this.name,
    this.subtitle,
    required this.enabled,
    required this.onToggle,
    required this.onTap,
    required this.onMore,
  });

  @override
  State<MenuScriptItem> createState() => _MenuScriptItemState();
}

class _MenuScriptItemState extends State<MenuScriptItem> {
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
            ? context.cs.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: widget.enabled
                          ? context.cs.onSurfaceVariant
                          : context.cs.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: widget.enabled,
              onChanged: widget.onToggle,
              activeThumbColor: context.cs.primary,
              activeTrackColor: context.cs.primary.withValues(alpha: 0.5),
              trackOutlineColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.transparent
                    : context.cs.outlineVariant,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onMore,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
                child: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: context.cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Selector item ──────────────────────────────────────────────────────────────

class MenuSelectorItem extends StatelessWidget {
  final String label;
  final String currentValue;
  final VoidCallback onTap;

  const MenuSelectorItem({
    super.key,
    required this.label,
    required this.currentValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: context.cs.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(currentValue,
                        style: TextStyle(
                            color: context.cs.onSurface, fontSize: 15)),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 22,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
