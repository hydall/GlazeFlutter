import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String kKeyboardHeightPref = 'chat_last_keyboard_height';
const double _kDefaultKeyboardHeight = 320;

class ChatDrawerController extends ChangeNotifier {
  final FocusNode _inputFocus = FocusNode();
  final AnimationController _drawerAnimController;
  late final Animation<double> drawerAnim;

  bool _drawerOpen = false;
  bool _switchingToDrawer = false;
  double _lastKeyboardHeight = _kDefaultKeyboardHeight;
  double _activeDrawerHeight = _kDefaultKeyboardHeight;

  double _tempMaxHeight = 0;
  Timer? _heightTimer;

  final Future<double> Function() _readKeyboardHeight;
  final Future<void> Function(double) _persistKeyboardHeight;

  ChatDrawerController({
    required TickerProvider vsync,
    required Future<double> Function() readKeyboardHeight,
    required Future<void> Function(double) persistKeyboardHeight,
  }) : _readKeyboardHeight = readKeyboardHeight,
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
    _inputFocus.addListener(_onFocusChanged);
  }

  FocusNode get inputFocus => _inputFocus;
  bool get drawerOpen => _drawerOpen;
  bool get switchingToDrawer => _switchingToDrawer;
  double get lastKeyboardHeight => _lastKeyboardHeight;
  double get activeDrawerHeight => _activeDrawerHeight;
  bool get isDrawerAnimating => _drawerAnimController.value > 0.001;

  Future<void> restoreKeyboardHeight() async {
    try {
      final saved = await _readKeyboardHeight();
      if (saved > 200) {
        _lastKeyboardHeight = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  void toggleDrawer(BuildContext context) {
    if (_drawerOpen) {
      _drawerOpen = false;
      _drawerAnimController.reverse();
      notifyListeners();
    } else {
      HapticFeedback.selectionClick();
      _activeDrawerHeight = _lastKeyboardHeight;

      final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
      if (keyboardHeight > 0 || _inputFocus.hasFocus) {
        _switchingToDrawer = true;
        _inputFocus.unfocus();
        notifyListeners();
      } else {
        _drawerOpen = true;
        _drawerAnimController.forward();
        notifyListeners();
      }
    }
  }

  void closeDrawer() {
    if (!_drawerOpen) return;
    _drawerOpen = false;
    _drawerAnimController.reverse();
    notifyListeners();
  }

  void _onFocusChanged() {
    if (_inputFocus.hasFocus && _drawerOpen) {
      _drawerOpen = false;
      _activeDrawerHeight = _lastKeyboardHeight;
      _drawerAnimController.reverse();
      notifyListeners();
    }
  }

  void handleKeyboardFrame(double keyboardHeight) {
    if (keyboardHeight > 200 && _inputFocus.hasFocus) {
      if (keyboardHeight > _tempMaxHeight) {
        _tempMaxHeight = keyboardHeight;
        _heightTimer?.cancel();
        _heightTimer = Timer(const Duration(milliseconds: 300), () {
          if (_tempMaxHeight > 200 && _tempMaxHeight != _lastKeyboardHeight) {
            _lastKeyboardHeight = _tempMaxHeight;
            _persistKeyboardHeight(_lastKeyboardHeight);
            notifyListeners();
          }
        });
      }
    }

    if (!_inputFocus.hasFocus && _tempMaxHeight != 0) {
      _tempMaxHeight = 0;
    }
  }

  bool checkSwitchingTransition(double keyboardHeight) {
    if (_switchingToDrawer && keyboardHeight == 0) {
      _switchingToDrawer = false;
      _drawerOpen = true;
      _drawerAnimController.forward();
      notifyListeners();
      return true;
    }
    return false;
  }

  bool checkDrawerCollision(double keyboardHeight) {
    if (keyboardHeight > 0 && _drawerOpen && !_switchingToDrawer) {
      closeDrawer();
      return true;
    }
    return false;
  }

  double computeTargetBottomPanelInset(double keyboardHeight, double safeBottom) {
    final targetDrawerInset = (_drawerOpen || _switchingToDrawer)
        ? _activeDrawerHeight
        : 0.0;
    final isIdle = keyboardHeight == 0 &&
        !_drawerOpen &&
        !_switchingToDrawer &&
        _drawerAnimController.value == 0;
    final bottomPadding = isIdle ? safeBottom : 0.0;
    return math.max(targetDrawerInset, keyboardHeight) + bottomPadding;
  }

  bool canPop() => !_drawerOpen && !_inputFocus.hasFocus;

  @override
  void dispose() {
    _heightTimer?.cancel();
    _inputFocus.removeListener(_onFocusChanged);
    _inputFocus.dispose();
    _drawerAnimController.dispose();
    super.dispose();
  }
}