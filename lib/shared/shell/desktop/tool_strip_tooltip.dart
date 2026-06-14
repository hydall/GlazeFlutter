import 'package:flutter/material.dart';

class ToolStripTooltip extends StatefulWidget {
  final List<ToolStripItem> items;
  final Widget Function({
    required void Function(String id, RenderBox box) onItemEnter,
    required VoidCallback onItemLeave,
  }) builder;
  final bool showOnRight;

  const ToolStripTooltip({
    super.key,
    required this.items,
    required this.builder,
    this.showOnRight = true,
  });

  @override
  State<ToolStripTooltip> createState() => _ToolStripTooltipState();
}

class _ToolStripTooltipState extends State<ToolStripTooltip> {
  final _tooltipController = OverlayPortalController();
  String? _activeId;
  late Offset _position;

  @override
  void dispose() {
    _tooltipController.hide();
    super.dispose();
  }

  void _onItemEnter(String id, RenderBox box) {
    final offset = box.localToGlobal(Offset.zero);
    setState(() {
      _activeId = id;
      _position = offset;
    });
    _tooltipController.show();
  }

  void _onItemLeave() {
    _tooltipController.hide();
    setState(() => _activeId = null);
  }

  String _labelFor(String id) {
    return widget.items.firstWhere((e) => e.id == id).label;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _tooltipController,
      overlayChildBuilder: (context) {
        if (_activeId == null) return const SizedBox.shrink();
        final label = _labelFor(_activeId!);
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return const SizedBox.shrink();
        // Position tooltip to the right of the collapsed sidebar (at x=0 of the sidebar in global)
        return Positioned(
          left: _position.dx + 64 + 8, // sidebar width + gap
          top: _position.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        );
      },
      child: widget.builder(
        onItemEnter: (id, box) {
          // Delay to let the render box settle
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onItemEnter(id, box);
          });
        },
        onItemLeave: _onItemLeave,
      ),
    );
  }
}

class ToolStripItem {
  final String id;
  final String label;
  final String icon;

  const ToolStripItem({
    required this.id,
    required this.label,
    required this.icon,
  });
}
