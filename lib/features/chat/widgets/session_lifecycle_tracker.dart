import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/crash_recovery_service.dart';
import '../chat_provider.dart';

class SessionLifecycleTracker extends ConsumerStatefulWidget {
  final String charId;
  final Widget child;
  const SessionLifecycleTracker({super.key, required this.charId, required this.child});

  @override
  ConsumerState<SessionLifecycleTracker> createState() => _SessionLifecycleTrackerState();
}

class _SessionLifecycleTrackerState extends ConsumerState<SessionLifecycleTracker> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _markActive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _doMarkClosed();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) _markActive();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (mounted) _doMarkClosed();
    }
  }

  Future<void> _markActive() async {
    final service = ref.read(crashRecoveryProvider);
    final chatState = ref.read(chatProvider(widget.charId)).value;
    final sessionId = chatState?.session?.id ?? '';
    if (sessionId.isNotEmpty) {
      await service.markSessionActive(sessionId, widget.charId);
    }
  }

  void _doMarkClosed() {
    try {
      final service = ref.read(crashRecoveryProvider);
      service.markSessionClosed();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
