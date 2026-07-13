import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/haptics.dart';

const String kKeyboardHeightPref = 'chat_last_keyboard_height';
const double _kDefaultKeyboardHeight = 320;

/// Identifies which content the drawer is currently showing.
enum DrawerPanel { magic, quickReplies }

/// Drives the native magic / quick-replies drawer and its keyboard↔drawer
/// "Telegram swap".
///
/// Phase 2 moved the compose field into the chat WebView, so the on-screen
/// keyboard and the field's focus are now **WebView-owned**. This controller no
/// longer reads `MediaQuery.viewInsets` or owns a Flutter `FocusNode`; instead
/// the WebView reports focus via [setInputFocused] and keyboard geometry via
/// [handleWebViewKeyboard] (sourced from `window.visualViewport`). To dismiss
/// the WebView keyboard from Flutter (e.g. the back gesture) it calls back
/// through [onRequestBlurInput].
class ChatDrawerController extends ChangeNotifier {
  final AnimationController _drawerAnimController;
  late final Animation<double> drawerAnim;

  bool _drawerOpen = false;
  bool _switchingToDrawer = false;
  DrawerPanel _activePanel = DrawerPanel.magic;
  double _lastKeyboardHeight = _kDefaultKeyboardHeight;
  double _activeDrawerHeight = _kDefaultKeyboardHeight;

  /// Whether the in-WebView compose field currently holds focus, and whether
  /// the WebView reports the on-screen keyboard as open. Both are pushed from
  /// the WebView (visualViewport / focus events) — Flutter no longer measures
  /// them itself.
  bool _inputFocused = false;
  bool _keyboardOpen = false;

  /// Fallback so a missed WebView keyboard-closed report can't leave the swap
  /// stuck with the drawer hidden.
  Timer? _switchTimer;

  bool _batterySaverMode = false;

  final Future<double> Function() _readKeyboardHeight;
  final Future<void> Function(double) _persistKeyboardHeight;

  /// Set by the chat body so the controller can ask the WebView to blur its
  /// compose field (there is no Flutter `FocusNode` to unfocus anymore).
  VoidCallback? onRequestBlurInput;

  ChatDrawerController({
    required TickerProvider vsync,
    required Future<double> Function() readKeyboardHeight,
    required Future<void> Function(double) persistKeyboardHeight,
  })  : _readKeyboardHeight = readKeyboardHeight,
        _persistKeyboardHeight = persistKeyboardHeight,
        _drawerAnimController = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 260),
        ) {
    drawerAnim = CurvedAnimation(
      parent: _drawerAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  bool get drawerOpen => _drawerOpen;
  bool get switchingToDrawer => _switchingToDrawer;
  DrawerPanel get activePanel => _activePanel;
  double get lastKeyboardHeight => _lastKeyboardHeight;
  double get activeDrawerHeight => _activeDrawerHeight;
  bool get isDrawerAnimating => _drawerAnimController.isAnimating;
  bool get inputFocused => _inputFocused;
  bool get keyboardOpen => _keyboardOpen;

  void setBatterySaverMode(bool enabled) {
    _batterySaverMode = enabled;
  }

  /// Seeds the last-known keyboard height from prefs so the drawer opens at the
  /// right size on the first tap, before any live keyboard measurement lands.
  Future<void> restoreKeyboardHeight() async {
    try {
      final saved = await _readKeyboardHeight();
      if (saved > 200) {
        _lastKeyboardHeight = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  void toggleDrawer({DrawerPanel panel = DrawerPanel.magic}) {
    if (_drawerOpen) {
      if (_activePanel == panel) {
        _drawerOpen = false;
        _drawerAnimController.reverse();
      } else {
        _activePanel = panel;
        Haptics.selectionClick();
      }
      notifyListeners();
      return;
    }
    _activePanel = panel;
    Haptics.selectionClick();
    _activeDrawerHeight = _lastKeyboardHeight;

    if (_keyboardOpen) {
      // Mobile: the WebView compose field blurs itself before sending the open
      // request, so the on-screen keyboard is already collapsing. Wait for the
      // WebView's keyboard-closed report to swap the drawer in seamlessly; a
      // fallback timer guards against a missed report.
      _switchingToDrawer = true;
      if (_batterySaverMode) {
        _drawerOpen = true;
        _drawerAnimController.forward();
      }
      notifyListeners();
      _switchTimer?.cancel();
      _switchTimer = Timer(const Duration(milliseconds: 400), () {
        if (_switchingToDrawer) _completeSwitchToDrawer();
      });
    } else {
      // Desktop / keyboard already down: reveal immediately.
      _drawerOpen = true;
      _drawerAnimController.forward();
      notifyListeners();
    }
  }

  void closeDrawer() {
    if (!_drawerOpen && !_switchingToDrawer) return;
    _switchTimer?.cancel();
    _drawerOpen = false;
    _switchingToDrawer = false;
    _drawerAnimController.reverse();
    notifyListeners();
  }

  /// WebView compose-field focus changed. Returning to the field closes the
  /// native drawer (the focus side of the keyboard↔drawer swap).
  void setInputFocused(bool focused) {
    if (_inputFocused == focused) return;
    _inputFocused = focused;
    if (focused && (_drawerOpen || _switchingToDrawer)) {
      _activeDrawerHeight = _lastKeyboardHeight;
      closeDrawer(); // notifies
      return;
    }
    notifyListeners();
  }

  /// On-screen keyboard geometry reported by the WebView (visualViewport).
  /// Replaces the old `MediaQuery.viewInsets`-driven [handleKeyboardFrame] /
  /// switching / collision machinery now that the compose field lives in the
  /// WebView: it persists the measured height (so the drawer opens at the same
  /// size), completes the keyboard→drawer swap when the keyboard finishes
  /// closing, and closes the drawer if the keyboard rises over it.
  void handleWebViewKeyboard(double height, bool open) {
    if (open && height > 200 && height != _lastKeyboardHeight) {
      _lastKeyboardHeight = height;
      _persistKeyboardHeight(_lastKeyboardHeight);
    }
    final wasOpen = _keyboardOpen;
    _keyboardOpen = open;

    if (!open && _switchingToDrawer) {
      _completeSwitchToDrawer();
      return;
    }
    if (open && !wasOpen && _drawerOpen && !_switchingToDrawer) {
      closeDrawer();
    }
  }

  void _completeSwitchToDrawer() {
    _switchTimer?.cancel();
    _switchingToDrawer = false;
    _drawerOpen = true;
    if (_drawerAnimController.value < 1.0) {
      _drawerAnimController.forward();
    }
    notifyListeners();
  }

  /// Asks the WebView to blur its compose field if it is focused. Returns true
  /// when it consumed the gesture (used by the back handler to dismiss the
  /// keyboard before any navigation / drawer close).
  bool requestBlurIfFocused() {
    if (!_inputFocused) return false;
    onRequestBlurInput?.call();
    return true;
  }

  bool canPop() => !_drawerOpen && !_inputFocused;

  @override
  void dispose() {
    _switchTimer?.cancel();
    _drawerAnimController.dispose();
    super.dispose();
  }
}
