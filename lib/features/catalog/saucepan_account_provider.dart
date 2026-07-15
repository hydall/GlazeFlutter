import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Last-known Saucepan account, persisted across launches alongside the Bearer
/// token (see `saucepan_provider.dart`). Only the display [handle] is kept —
/// enough to show "Logged in as …" in the menu without a network round-trip.
class SaucepanAccount {
  final String? handle;
  const SaucepanAccount({this.handle});

  bool get isLoggedIn => handle != null && handle!.isNotEmpty;
}

/// Holds the persisted Saucepan [handle]. Written when a login lands (the login
/// sheet calls [setHandle] after `saucepanLogin` returns a token) and cleared on
/// logout. Loaded from prefs on first build so the menu hint is correct
/// immediately, before any network call.
class SaucepanAccountNotifier extends Notifier<SaucepanAccount> {
  static const _handleKey = 'gz_saucepan_handle';

  @override
  SaucepanAccount build() {
    _load();
    return const SaucepanAccount();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final handle = prefs.getString(_handleKey);
    if (handle != null && handle.isNotEmpty) {
      state = SaucepanAccount(handle: handle);
    }
  }

  /// Persists [handle] (or clears it when null/empty) and updates the state.
  Future<void> setHandle(String? handle) async {
    final prefs = await SharedPreferences.getInstance();
    if (handle == null || handle.isEmpty) {
      await prefs.remove(_handleKey);
      state = const SaucepanAccount();
    } else {
      await prefs.setString(_handleKey, handle);
      state = SaucepanAccount(handle: handle);
    }
  }
}

final saucepanAccountProvider =
    NotifierProvider<SaucepanAccountNotifier, SaucepanAccount>(
  SaucepanAccountNotifier.new,
);
