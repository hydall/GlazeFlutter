import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'glaze_scaffold.dart';
import 'menu_group.dart';

class FullscreenEditorScreen extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final String? hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  const FullscreenEditorScreen({
    super.key,
    required this.title,
    required this.controller,
    this.hintText,
    this.autofocus = true,
    this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required TextEditingController controller,
    String? hintText,
    bool autofocus = true,
    ValueChanged<String>? onChanged,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullscreenEditorScreen(
          title: title,
          controller: controller,
          hintText: hintText,
          autofocus: autofocus,
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  State<FullscreenEditorScreen> createState() => _FullscreenEditorScreenState();
}

class _FullscreenEditorScreenState extends State<FullscreenEditorScreen> {
  @override
  Widget build(BuildContext context) {
    return GlazeScaffold(
      title: widget.title,
      showBack: true,
      onBack: () => Navigator.of(context).pop(),
      showBackground: true,
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return MenuGroup(
              items: [
                _FullscreenEditorField(
                  controller: widget.controller,
                  hintText: widget.hintText,
                  autofocus: widget.autofocus,
                  height: constraints.maxHeight - 30,
                  onChanged: widget.onChanged,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FullscreenEditorField extends StatelessWidget {
  final TextEditingController controller;
  final String? hintText;
  final bool autofocus;
  final double height;
  final ValueChanged<String>? onChanged;

  const _FullscreenEditorField({
    required this.controller,
    required this.hintText,
    required this.autofocus,
    required this.height,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height > 120 ? height : 120,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          autofocus: autofocus,
          maxLines: null,
          expands: true,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: TextStyle(
            color: context.cs.onSurface,
            fontSize: 16,
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: context.cs.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            filled: false,
            fillColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
