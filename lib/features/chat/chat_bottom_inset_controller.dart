import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_drawer_controller.dart';

/// Keyboard/layout insets for chat chrome.
///
/// **Architecture:** WebView lives in an [Expanded] above the input bar (not
/// under a moving overlay). [bottomPanelInset] lifts the whole column when the
/// IME is open. Layout updates are **settle-only** during keyboard motion — no
/// per-frame PlatformView or JS relayout.
class ChatBottomInsetController extends ChangeNotifier {
  ChatBottomInsetController(this.drawerCtrl);

  final ChatDrawerController drawerCtrl;

  double inputBarHeight = 130;
  double bottomPanelInset = 0;
  double keyboardHeight = 0;

  bool get isKeyboardVisible => keyboardHeight > 0.5;

  void setInputBarHeight(double height) {
    if (height <= 0 || (height - inputBarHeight).abs() < 0.5) return;
    inputBarHeight = height;
    notifyListeners();
  }

  /// Applies layout from [context]. Returns true when chrome insets changed.
  bool syncFromContext(
    BuildContext context, {
    double? keyboardHeightOverride,
  }) {
    final media = MediaQuery.of(context);
    final keyboardHeight = _snapInset(
      keyboardHeightOverride ?? media.viewInsets.bottom,
      media.devicePixelRatio,
    );
    final safeBottom = media.padding.bottom;

    drawerCtrl.handleKeyboardFrame(keyboardHeight);

    final bottomPanelInset = computeInsets(
      keyboardHeight: keyboardHeight,
      safeBottom: safeBottom,
      drawerCtrl: drawerCtrl,
    );

    final keyboardChanged = (keyboardHeight - this.keyboardHeight).abs() >= 0.5;
    final panelChanged = (bottomPanelInset - this.bottomPanelInset).abs() >= 0.5;

    if (!keyboardChanged && !panelChanged) return false;

    this.keyboardHeight = keyboardHeight;
    this.bottomPanelInset = bottomPanelInset;
    notifyListeners();
    return true;
  }

  static double _snapInset(double value, double devicePixelRatio) {
    if (value <= 0) return 0;
    final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    return (value * ratio).round() / ratio;
  }

  static double computeInsets({
    required double keyboardHeight,
    required double safeBottom,
    required ChatDrawerController drawerCtrl,
  }) {
    final drawerProgress = drawerCtrl.drawerAnim.value;
    final drawerActive = drawerCtrl.drawerOpen || drawerCtrl.switchingToDrawer;
    final drawerInset =
        drawerActive ? drawerCtrl.activeDrawerHeight * drawerProgress : 0.0;
    final panelHeight = math.max(keyboardHeight, drawerInset);
    // In column layout the input chrome already occupies bottom space, so
    // adding safeBottom here creates a persistent empty stripe when keyboard
    // and drawer are closed.
    if (panelHeight <= 0.5) return 0;
    final factor = math.min(1.0, panelHeight / math.max(1.0, safeBottom));
    return panelHeight + (safeBottom * (1 - factor));
  }
}

/// Reads [MediaQuery.viewInsets] and publishes **settled** layout only.
class ChatBottomInsetSync extends StatefulWidget {
  const ChatBottomInsetSync({
    super.key,
    required this.controller,
    required this.drawerCtrl,
    this.onInsetsSettled,
  });

  final ChatBottomInsetController controller;
  final ChatDrawerController drawerCtrl;
  final VoidCallback? onInsetsSettled;

  @override
  State<ChatBottomInsetSync> createState() => _ChatBottomInsetSyncState();
}

class _ChatBottomInsetSyncState extends State<ChatBottomInsetSync> {
  static const _keyboardSettleDelay = Duration(milliseconds: 220);

  double _lastRawKeyboardHeight = -1;
  Timer? _keyboardSettleTimer;

  @override
  void dispose() {
    _keyboardSettleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onViewInsetsChanged();
  }

  void _onViewInsetsChanged() {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    if ((keyboardHeight - _lastRawKeyboardHeight).abs() < 0.5) return;
    _lastRawKeyboardHeight = keyboardHeight;

    // Drawer switching/open state must react immediately to raw keyboard
    // frames; waiting for settle can leave stale bottom inset and lock the
    // Magic Drawer in a half-open state.
    if (widget.drawerCtrl.switchingToDrawer || widget.drawerCtrl.drawerOpen) {
      final changed = widget.controller.syncFromContext(
        context,
        keyboardHeightOverride: keyboardHeight,
      );
      if (changed) {
        widget.onInsetsSettled?.call();
      }
    }

    _keyboardSettleTimer?.cancel();
    _keyboardSettleTimer = Timer(_keyboardSettleDelay, _applySettledInsets);

    if (widget.drawerCtrl.switchingToDrawer && keyboardHeight == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.drawerCtrl.checkSwitchingTransition(keyboardHeight);
        _applySettledInsets();
      });
    }

    if (keyboardHeight > 0 &&
        widget.drawerCtrl.drawerOpen &&
        !widget.drawerCtrl.switchingToDrawer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.drawerCtrl.checkDrawerCollision(keyboardHeight);
      });
    }
  }

  void _applySettledInsets() {
    if (!mounted) return;
    final settledHeight = MediaQuery.viewInsetsOf(context).bottom;
    final changed = widget.controller.syncFromContext(
      context,
      keyboardHeightOverride: settledHeight,
    );
    if (changed) {
      widget.onInsetsSettled?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Depend on viewInsets without rebuilding ancestors each frame.
    MediaQuery.viewInsetsOf(context);
    return const SizedBox.shrink();
  }
}
