import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_colors.dart';

class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;
  final void Function(String text, String? guidance)? onSendWithGuidance;
  final bool isGenerating;
  final bool isGeneratingImage;
  final VoidCallback? onStop;
  final VoidCallback? onMagicDrawer;
  final VoidCallback? onImageGen;
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

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onSendWithGuidance,
    required this.isGenerating,
    this.isGeneratingImage = false,
    this.onStop,
    this.onMagicDrawer,
    this.onImageGen,
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
    if (old.enterToSend != widget.enterToSend) {
      _updateFocusNodeHandler();
    }
  }

  void _updateFocusNodeHandler() {
    final fn = widget.focusNode;
    if (fn == null || !widget.enterToSend) return;
    fn.onKeyEvent = (node, event) {
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
      final searchContent = Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: context.cs.surface.withValues(alpha: widget.batterySaver ? 1.0 : 0.8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
          borderRadius: BorderRadius.circular(28),
        ),
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
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              decoration: BoxDecoration(
                color: context.cs.surface.withValues(alpha: 1.0),
                border: Border.all(
                  color: _guidanceMode
                      ? Colors.orange.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.05),
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _effectiveFocusNode,
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
                    icon: _guidanceMode
                        ? Icons.tips_and_updates
                        : Icons.tips_and_updates_outlined,
                    onTap: () => setState(() {
                      _guidanceMode = !_guidanceMode;
                      if (!_guidanceMode) _guidanceController.clear();
                    }),
                    color: _guidanceMode ? Colors.orange : null,
                    batterySaver: widget.batterySaver,
                  ),
                  const SizedBox(width: 8),
                  _CircleBtn(
                    icon: Icons.image_outlined,
                    onTap: widget.onImageGen,
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

                  return GestureDetector(
                    onTap: () {
                      if (isGenerating) {
                        widget.onStop?.call();
                      } else if (hasText) {
                        _handleSend();
                      } else {
                        widget.onImpersonate?.call();
                      }
                    },
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
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOut,
                                  ),
                                ),
                                child: child,
                              ),
                            );
                          },
                          child: Icon(
                            icon,
                            key: ValueKey(icon),
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
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

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final bool batterySaver;

  const _CircleBtn({required this.icon, this.onTap, this.color, this.batterySaver = false});

  @override
  Widget build(BuildContext context) {
    final container = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.cs.surface.withValues(alpha: batterySaver ? 1.0 : 0.8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(icon, color: color ?? context.cs.primary, size: 20),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: container,
    );
  }
}
