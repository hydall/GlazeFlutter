import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_colors.dart';

// ── Group container ────────────────────────────────────────────────────────────

class SettingsGroup extends StatelessWidget {
  final String header;
  final List<Widget> children;

  const SettingsGroup({super.key, required this.header, required this.children});

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text(
                header,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                    height: 1,
                    thickness: 0.4,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              children[i],
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// ── Text field item ────────────────────────────────────────────────────────────

class SettingsItemField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const SettingsItemField({
    super.key,
    required this.label,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: TextStyle(
                color: context.colors.textSecondary.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: const Color(0xFF252525),
              suffixIcon: suffix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: context.colors.accent.withValues(alpha: 0.5),
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

// ── Switch item ────────────────────────────────────────────────────────────────

class SettingsItemSwitch extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsItemSwitch({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.colors.accent,
            activeTrackColor: context.colors.accent.withValues(alpha: 0.5),
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.transparent
                  : context.colors.glassBorder,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Range slider item ──────────────────────────────────────────────────────────

class SettingsItemRange extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const SettingsItemRange({
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
                child: Text(
                  label,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                _display,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                  fontVariations: const [FontVariation('wght', 500)],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.colors.accent,
              thumbColor: context.colors.accent,
              inactiveTrackColor: context.colors.accent.withValues(alpha: 0.18),
              overlayColor: context.colors.accent.withValues(alpha: 0.1),
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

// ── Clickable selector item ────────────────────────────────────────────────────

class SettingsItemSelector extends StatelessWidget {
  final String label;
  final String currentValue;
  final VoidCallback onTap;

  const SettingsItemSelector({
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
            Text(
              label,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 13,
              ),
            ),
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
                    child: Text(
                      currentValue,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: context.colors.textSecondary.withValues(alpha: 0.5),
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
