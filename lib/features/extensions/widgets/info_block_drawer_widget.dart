import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../models/info_block.dart';
import '../providers/extensions_settings_provider.dart';
import '../providers/info_blocks_provider.dart';

class InfoBlockDrawerWidget extends ConsumerStatefulWidget {
  const InfoBlockDrawerWidget({
    required this.sessionId,
    required this.child,
    super.key,
  });

  final String sessionId;
  final Widget child;

  @override
  ConsumerState<InfoBlockDrawerWidget> createState() =>
      _InfoBlockDrawerWidgetState();
}

class _InfoBlockDrawerWidgetState extends ConsumerState<InfoBlockDrawerWidget>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late final AnimationController _animController;
  late final Animation<double> _slideAnimation;
  static const double _panelWidth = 320;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slideAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  void _close() {
    if (!_isOpen) return;
    setState(() => _isOpen = false);
    _animController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessionId.isEmpty) {
      return widget.child;
    }

    final blocks = ref.watch(infoBlocksProvider(widget.sessionId));
    final extensionEnabled = ref.watch(extensionsSettingsProvider).enabled;

    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _slideAnimation,
          builder: (context, _) {
            final progress = _slideAnimation.value;
            final rightOffset = -(_panelWidth * (1 - progress));

            return Stack(
              children: [
                if (progress > 0.001)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _close,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.3 * progress),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: rightOffset,
                  width: _panelWidth,
                  child: _PanelContent(
                    blocks: blocks,
                    onClose: _close,
                  ),
                ),
              ],
            );
          },
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 66,
          right: 12,
          child: IgnorePointer(
            ignoring: !extensionEnabled,
            child: AnimatedOpacity(
              opacity: extensionEnabled ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(20),
                  child: Ink(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isOpen
                          ? context.cs.primary.withValues(alpha: 0.2)
                          : context.cs.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Icon(
                      _isOpen
                          ? Icons.chevron_right
                          : Icons.article_outlined,
                      color: _isOpen
                          ? context.cs.primary
                          : context.cs.onSurface,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelContent extends StatelessWidget {
  const _PanelContent({
    required this.blocks,
    required this.onClose,
  });

  final List<InfoBlock> blocks;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cs.surface,
        border: Border(
          left: BorderSide(
            color: context.cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
              child: Row(
                children: [
                  Text(
                    'Инфоблоки',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: context.cs.onSurfaceVariant,
                    onPressed: onClose,
                    splashRadius: 16,
                  ),
                ],
              ),
            ),
            if (blocks.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'Нет инфоблоков',
                    style: TextStyle(
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: blocks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final block = blocks[index];
                    return _BlockCard(block: block);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block});
  final InfoBlock block;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  block.blockName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.cs.primary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                block.blockType,
                style: TextStyle(
                  fontSize: 10,
                  color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            block.content,
            style: TextStyle(
              fontSize: 12,
              color: context.cs.onSurface.withValues(alpha: 0.8),
              height: 1.4,
            ),
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
