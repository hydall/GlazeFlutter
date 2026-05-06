import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CrashRecoveryService {
  static const _activeSessionKey = 'crash_recovery_active_session';
  static const _activeCharKey = 'crash_recovery_active_char';

  Future<void> markSessionActive(String sessionId, String charId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeSessionKey, sessionId);
    await prefs.setString(_activeCharKey, charId);
  }

  Future<void> markSessionClosed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeSessionKey);
    await prefs.remove(_activeCharKey);
  }

  Future<CrashRecoveryInfo?> checkRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_activeSessionKey);
    final charId = prefs.getString(_activeCharKey);
    if (sessionId == null || charId == null) return null;
    return CrashRecoveryInfo(sessionId: sessionId, charId: charId);
  }
}

class CrashRecoveryInfo {
  final String sessionId;
  final String charId;
  const CrashRecoveryInfo({required this.sessionId, required this.charId});
}

final crashRecoveryProvider = Provider<CrashRecoveryService>((_) => CrashRecoveryService());

Future<void> checkAndOfferCrashRecovery(BuildContext context, WidgetRef ref) async {
  final service = ref.read(crashRecoveryProvider);
  final info = await service.checkRecovery();
  if (info == null || !context.mounted) return;

  final shouldRecover = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Recover Session?'),
      content: const Text('It looks like the app was closed unexpectedly. Would you like to recover your last chat session?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Dismiss'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Recover'),
        ),
      ],
    ),
  );

  await service.markSessionClosed();

  if (shouldRecover == true && context.mounted) {
    context.go('/chat/${info.charId}');
  }
}
