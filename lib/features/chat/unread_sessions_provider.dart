import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Set of chat sessions with an unread assistant reply — a reply that landed
/// while that session was NOT the one open on screen. Drives the unread dot +
/// row highlight in the chat list, and survives app restarts (persisted to
/// SharedPreferences).
///
/// Writers:
/// - [markUnread] on generation completion for a non-active session (see
///   `sync_notification_stage.dart` and `ChatNotifier.continueMessage`).
/// - [markRead] when the user opens / focuses the session
///   (`SessionLifecycleTracker`).
final unreadSessionsProvider =
    NotifierProvider<UnreadSessionsNotifier, Set<String>>(
      UnreadSessionsNotifier.new,
    );

class UnreadSessionsNotifier extends Notifier<Set<String>> {
  static const _prefsKey = 'unread_sessions';

  @override
  Set<String> build() {
    // Hydrate asynchronously; starts empty and fills in once prefs load.
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_prefsKey);
      if (stored == null || stored.isEmpty) return;
      // Merge rather than overwrite: any marks that happened during the async
      // load must not be lost.
      state = {...state, ...stored};
    } catch (e) {
      debugPrint('[UnreadSessions] load failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, state.toList());
    } catch (e) {
      debugPrint('[UnreadSessions] persist failed: $e');
    }
  }

  void markUnread(String sessionId) {
    if (state.contains(sessionId)) return;
    state = {...state, sessionId};
    unawaited(_persist());
  }

  void markRead(String sessionId) {
    if (!state.contains(sessionId)) return;
    state = {...state}..remove(sessionId);
    unawaited(_persist());
  }
}
