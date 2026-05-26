import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glass_surface.dart';

class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;
  final void Function(String text, String? guidance)? onSendWithGuidance;
  final bool isGenerating;
  final bool isGeneratingImage;
  final VoidCallback? onStop;
  final VoidCallback? onMagicDrawer;
  final VoidCallback? onAttach;
  final VoidCallback? onFullScreen;
  final VoidCallback? onContinue;
  final VoidCallback? onImpersonate;
  final bool virtualKeyboardSend;
  final bool enterToSend;
  final bool batterySaver;

  /// When true, the magic-drawer button shows the active state. The host
  /// also uses this to interpret onMagicDrawer as a toggle.
  final bool isDrawerOpen;

  /// Optional focus node from the host so it can mediate keyboard ↔ drawer
  /// transitions (Telegram-style: keyboard and drawer replace each other).
  final FocusNode? focusNode;

  final String initialDraft;
  final ValueChanged<String>? onDraftChanged;

  final bool showSearchControls;
  final String searchQuery;
  final int searchMatchCount;
  final int searchCurrentIndex;
  final VoidCallback? onSearchNext;
  final VoidCallback? onSearchPrev;

  final bool isSelectionMode;
  final int selectedCount;
  final VoidCallback? onCancelSelection;
  final VoidCallback? onHideSelected;
  final VoidCallback? onDeleteSelected;
  final bool allSelectedHidden;
  final bool isEditingMessage;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onSendWithGuidance,
    required this.isGenerating,
    this.isGeneratingImage = false,
    this.onStop,
    this.onMagicDrawer,
    this.onAttach,
    this.onFullScreen,
    this.onContinue,
    this.onImpersonate,
    this.virtualKeyboardSend = false,
    this.enterToSend = true,
    this.batterySaver = false,
    this.isDrawerOpen = false,
    this.focusNode,
    this.initialDraft = '',
    this.onDraftChanged,
    this.showSearchControls = false,
    this.searchQuery = '',
    this.searchMatchCount = 0,
    this.searchCurrentIndex = 0,
    this.onSearchNext,
    this.onSearchPrev,
    this.isSelectionMode = false,
    this.selectedCount = 0,
    this.onCancelSelection,
    this.onHideSelected,
    this.onDeleteSelected,
    this.allSelectedHidden = false,
    this.isEditingMessage = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;
  final _guidanceController = TextEditingController();
  bool _guidanceMode = false;
  Timer? _debounce;
  final _internalFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDraft);
    _controller.addListener(_onTextChanged);
    _updateFocusNodeHandler();
  }

  void _onTextChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        widget.onDraftChanged?.call(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(ChatInputBar old) {
    super.didUpdateWidget(old);
    if (old.enterToSend != widget.enterToSend ||
        old.isEditingMessage != widget.isEditingMessage ||
        old.focusNode != widget.focusNode) {
      _updateFocusNodeHandler();
    }
  }

  void _updateFocusNodeHandler() {
    final fn = widget.focusNode;
    final effective = _effectiveFocusNode;
    effective.canRequestFocus = !widget.isEditingMessage;
    if (widget.isEditingMessage && effective.hasFocus) {
      effective.unfocus();
    }
    if (fn == null || !widget.enterToSend) return;
    fn.onKeyEvent = (node, event) {
      if (widget.isEditingMessage) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _handleSend();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _guidanceController.dispose();
    _internalFocusNode.dispose();
    super.dispose();
  }

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  void _handleSend() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    if (_guidanceMode && _guidanceController.text.trim().isNotEmpty) {
      widget.onSendWithGuidance?.call(text, _guidanceController.text.trim());
    } else {
      widget.onSend(text);
    }
    _controller.clear();
    _guidanceController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showSearchControls) {
      final searchContent = GlassSurface(
        borderRadius: BorderRadius.circular(28),
        tint: context.cs.surface,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
          children: [
            const SizedBox(width: 18),
            Icon(Icons.search, size: 20, color: context.cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.searchMatchCount > 0
                    ? '${widget.searchCurrentIndex + 1} of ${widget.searchMatchCount} matches'
                    : 'No matches found',
                style: TextStyle(
                  color: context.cs.onSurface,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.keyboard_arrow_up,
                size: 24,
                color: context.cs.onSurface,
              ),
              onPressed: widget.onSearchPrev,
            ),
            IconButton(
              icon: Icon(
                Icons.keyboard_arrow_down,
                size: 24,
                color: context.cs.onSurface,
              ),
              onPressed: widget.onSearchNext,
            ),
            const SizedBox(width: 8),
          ],
        ),
        ),
      );
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child:           Material(
            color: Colors.transparent,
            elevation: 0,
            borderRadius: BorderRadius.circular(28),
            child: searchContent,
          ),
        ),
      );
    }

    if (widget.isSelectionMode) {
      final selectionContent = GlassSurface(
        borderRadius: BorderRadius.circular(28),
        tint: context.cs.surface,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
          children: [
            const SizedBox(width: 8),
            _CircleBtn(
              icon: Icons.close,
              onTap: widget.onCancelSelection,
              batterySaver: widget.batterySaver,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${widget.selectedCount} Selected',
                style: TextStyle(
                  color: context.cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _CircleBtn(
              icon: widget.allSelectedHidden ? Icons.visibility : Icons.visibility_off,
              onTap: widget.selectedCount > 0 ? widget.onHideSelected : null,
              color: widget.selectedCount > 0 ? context.cs.primary : context.cs.onSurface.withValues(alpha: 0.3),
              batterySaver: widget.batterySaver,
            ),
            const SizedBox(width: 8),
            _CircleBtn(
              icon: Icons.delete,
              onTap: widget.selectedCount > 0 ? widget.onDeleteSelected : null,
              color: widget.selectedCount > 0 ? Colors.redAccent : context.cs.onSurface.withValues(alpha: 0.3),
              batterySaver: widget.batterySaver,
            ),
            const SizedBox(width: 8),
          ],
        ),
        ),
      );
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            borderRadius: BorderRadius.circular(28),
            child: selectionContent,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_guidanceMode) ...[
            Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _guidanceController,
                readOnly: widget.isEditingMessage,
                canRequestFocus: !widget.isEditingMessage,
                enableInteractiveSelection: !widget.isEditingMessage,
                showCursor: !widget.isEditingMessage,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: 14, color: Colors.orange),
                decoration: InputDecoration(
                  hintText: 'Guidance instructions...',
                  hintStyle: TextStyle(
                    color: Colors.orange.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.tips_and_updates_outlined,
                    color: Colors.orange.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Material(
            color: Colors.transparent,
            elevation: 0,
            borderRadius: BorderRadius.circular(28),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(28),
              tint: context.cs.surface,
              border: Border.all(
                color: _guidanceMode
                    ? Colors.orange.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.05),
              ),
              child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: TextField(
                controller: _controller,
                focusNode: _effectiveFocusNode,
                readOnly: widget.isEditingMessage,
                canRequestFocus: !widget.isEditingMessage,
                enableInteractiveSelection: !widget.isEditingMessage,
                showCursor: !widget.isEditingMessage,
                maxLines: 5,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: widget.virtualKeyboardSend
                    ? TextInputAction.send
                    : TextInputAction.newline,
                onSubmitted: widget.virtualKeyboardSend
                    ? (_) => _handleSend()
                    : null,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: _guidanceMode
                      ? 'Message with guidance...'
                      : 'Type a message...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  filled: false,
                ),
              ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CircleBtn(
                    icon: Icons.auto_awesome,
                    onTap: widget.onMagicDrawer,
                    color: widget.isDrawerOpen ? Colors.amber : null,
                    batterySaver: widget.batterySaver,
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.attach_file,
                    onTap: widget.onAttach,
                    batterySaver: widget.batterySaver,
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.fullscreen,
                    onTap: widget.onFullScreen,
                    batterySaver: widget.batterySaver,
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.north_east,
                    onTap: () => setState(() {
                      _guidanceMode = !_guidanceMode;
                      if (!_guidanceMode) _guidanceController.clear();
                    }),
                    color: _guidanceMode ? Colors.orange : null,
                    batterySaver: widget.batterySaver,
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.keyboard_double_arrow_right,
                    onTap: widget.onContinue,
                    batterySaver: widget.batterySaver,
                  ),
                ],
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) {
                  final hasText = value.text.trim().isNotEmpty || (_guidanceMode && _guidanceController.text.trim().isNotEmpty);
                  final isGenerating = widget.isGenerating || widget.isGeneratingImage;

                  IconData icon;
                  if (isGenerating) {
                    icon = Icons.stop_rounded;
                  } else if (hasText) {
                    icon = (_guidanceMode && value.text.trim().isEmpty) ? Icons.check_rounded : Icons.send_rounded;
                  } else {
                    icon = Icons.account_circle_rounded;
                  }

                  return _SendBtn(
                    icon: icon,
                    batterySaver: widget.batterySaver,
                    onTap: () {
                      if (isGenerating) {
                        widget.onStop?.call();
                      } else if (hasText) {
                        _handleSend();
                      } else {
                        widget.onImpersonate?.call();
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final bool batterySaver;

  const _CircleBtn({required this.icon, this.onTap, this.color, this.batterySaver = false});

  @override
  State<_CircleBtn> createState() => _CircleBtnState();
}

class _CircleBtnState extends State<_CircleBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (widget.onTap != null && !widget.batterySaver) ? (_) => _press.forward() : null,
      onTapUp: (widget.onTap != null && !widget.batterySaver) ? (_) => _press.reverse() : null,
      onTapCancel: (widget.onTap != null && !widget.batterySaver) ? () => _press.reverse() : null,
      child: ScaleTransition(
        scale: _scale,
        child: SizedBox(
          width: 40,
          height: 40,
          child: GlassSurface(
            borderRadius: BorderRadius.circular(20),
            tint: context.cs.surface,
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            child: Center(
              child: Icon(widget.icon, color: widget.color ?? context.cs.primary, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool batterySaver;

  const _SendBtn({required this.icon, this.onTap, this.batterySaver = false});

  @override
  State<_SendBtn> createState() => _SendBtnState();
}

class _SendBtnState extends State<_SendBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.batterySaver ? null : (_) => _press.forward(),
      onTapUp: widget.batterySaver ? null : (_) => _press.reverse(),
      onTapCancel: widget.batterySaver ? null : () => _press.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: context.cs.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
                  child: child,
                ),
              ),
              child: Icon(
                widget.icon,
                key: ValueKey(widget.icon),
                color: Colors.black,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
