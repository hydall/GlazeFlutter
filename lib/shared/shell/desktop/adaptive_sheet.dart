import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/glaze_bottom_sheet.dart';
import 'desktop_layout_provider.dart';
import 'sidebar_sheet_provider.dart';

Future<T?> showAdaptiveSheet<T>(
  BuildContext context,
  WidgetRef ref, {
  required Widget Function(BuildContext context) builder,
  String? title,
}) async {
  if (isDesktopLayout(context)) {
    // On desktop, render inside the right sidebar
    showSheetInRightSidebar(
      ref,
      _SidebarSheetWrapper(
        title: title,
        onClose: () => closeRightSidebarSheet(ref),
        child: builder(context),
      ),
    );
    return null;
  }

  // On mobile, use the standard bottom sheet
  return GlazeBottomSheet.show<T>(
    context,
    title: title,
    child: builder(context),
  );
}

class _SidebarSheetWrapper extends StatelessWidget {
  final String? title;
  final VoidCallback onClose;
  final Widget child;

  const _SidebarSheetWrapper({
    this.title,
    required this.onClose,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with close button
        if (title != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white10),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Colors.white70),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
        // Content
        Expanded(child: child),
      ],
    );
  }
}
