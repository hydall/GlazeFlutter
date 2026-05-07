import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';

class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;
  final void Function(String text, String? guidance)? onSendWithGuidance;
  final bool isGenerating;
  final VoidCallback? onStop;
  final VoidCallback? onMagicDrawer;
  final VoidCallback? onImageGen;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onSendWithGuidance,
    required this.isGenerating,
    this.onStop,
    this.onMagicDrawer,
    this.onImageGen,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _guidanceController = TextEditingController();
  bool _guidanceMode = false;

  @override
  void dispose() {
    _controller.dispose();
    _guidanceController.dispose();
    super.dispose();
  }

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
    return SafeArea(
      top: false,
      child: Padding(
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
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _guidanceController,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 14, color: Colors.orange),
                  decoration: InputDecoration(
                    hintText: 'Guidance instructions...',
                    hintStyle: TextStyle(color: Colors.orange.withValues(alpha: 0.5), fontSize: 14),
                    prefixIcon: Icon(Icons.tips_and_updates_outlined, color: Colors.orange.withValues(alpha: 0.7), size: 20),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: false,
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).scaffoldBackgroundColor.withValues(alpha: 0.8),
                    border: Border.all(
                      color: _guidanceMode
                          ? Colors.orange.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: TextField(
                    controller: _controller,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: _guidanceMode ? 'Message with guidance...' : 'Type a message...',
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
                      icon: _guidanceMode ? Icons.tips_and_updates : Icons.tips_and_updates_outlined,
                      onTap: () => setState(() {
                        _guidanceMode = !_guidanceMode;
                        if (!_guidanceMode) _guidanceController.clear();
                      }),
                      color: _guidanceMode ? Colors.orange : null,
                    ),
                    const SizedBox(width: 8),
                    _CircleBtn(icon: Icons.auto_awesome, onTap: widget.onMagicDrawer),
                    const SizedBox(width: 8),
                    _CircleBtn(icon: Icons.image_outlined, onTap: widget.onImageGen),
                  ],
                ),
                GestureDetector(
                  onTap: widget.isGenerating ? widget.onStop : _handleSend,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.isGenerating ? 'Stop' : 'Send',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          widget.isGenerating
                              ? Icons.stop_rounded
                              : Icons.send_rounded,
                          color: Colors.black,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  const _CircleBtn({required this.icon, this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).scaffoldBackgroundColor.withValues(alpha: 0.8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              shape: BoxShape.circle,
            ),
            child: Center(child: Icon(icon, color: color ?? AppColors.accent, size: 20)),
          ),
        ),
      ),
    );
  }
}
