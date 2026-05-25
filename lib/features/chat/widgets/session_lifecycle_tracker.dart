import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/shared_prefs_provider.dart';

class SessionLifecycleTracker extends ConsumerStatefulWidget {
  final String charId;
  final Widget child;
  const SessionLifecycleTracker({super.key, required this.charId, required this.child});

  @override
  ConsumerState<SessionLifecycleTracker> createState() => _SessionLifecycleTrackerState();
}

class _SessionLifecycleTrackerState extends ConsumerState<SessionLifecycleTracker> with WidgetsBindingObserver {
  DateTime? _enteredAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enteredAt = DateTime.now();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushTime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enteredAt = DateTime.now();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _flushTime();
    }
  }

  Future<void> _flushTime() async {
    if (_enteredAt == null) return;
    final elapsed = DateTime.now().difference(_enteredAt!).inSeconds;
    _enteredAt = null;
    if (elapsed <= 0) return;
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final key = 'chat_time_${widget.charId}';
      final prev = prefs.getInt(key) ?? 0;
      await prefs.setInt(key, prev + elapsed);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
