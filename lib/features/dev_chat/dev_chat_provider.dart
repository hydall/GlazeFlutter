import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/id_generator.dart';
import 'dev_chat_config.dart';
import 'dev_chat_message.dart';
import 'dev_chat_service.dart';
import 'dev_chat_store.dart';

/// Immutable UI state for the developer chat.
class DevChatState {
  const DevChatState({
    this.messages = const [],
    this.nick,
  });

  final List<DevChatMessage> messages;
  final String? nick;

  bool get hasNick => (nick ?? '').trim().isNotEmpty;

  DevChatState copyWith({
    List<DevChatMessage>? messages,
    String? nick,
  }) =>
      DevChatState(
        messages: messages ?? this.messages,
        nick: nick ?? this.nick,
      );
}

final devChatServiceProvider = Provider<DevChatService>((_) => DevChatService());
final devChatStoreProvider = Provider<DevChatStore>((_) => DevChatStore());

final devChatProvider =
    AsyncNotifierProvider<DevChatController, DevChatState>(DevChatController.new);

/// Whether the developer chat entry is hidden by the user. UI state so menus
/// can rebuild when toggled.
final devChatHiddenProvider =
    AsyncNotifierProvider<DevChatHiddenController, bool>(
        DevChatHiddenController.new);

class DevChatController extends AsyncNotifier<DevChatState> {
  Timer? _timer;

  DevChatStore get _store => ref.read(devChatStoreProvider);
  DevChatService get _service => ref.read(devChatServiceProvider);

  @override
  Future<DevChatState> build() async {
    ref.onDispose(() => _timer?.cancel());
    final messages = await _store.loadMessages();
    final nick = await _store.nick();
    return DevChatState(messages: messages, nick: nick);
  }

  Future<void> setNick(String nick) async {
    final trimmed = nick.trim();
    await _store.setNick(trimmed);
    final current = state.value ?? const DevChatState();
    state = AsyncData(current.copyWith(nick: trimmed));
  }

  /// Begins periodic polling for developer replies. Safe to call repeatedly.
  void startPolling() {
    _timer?.cancel();
    // Poll once immediately so replies show up without waiting a full cycle.
    unawaited(pollOnce());
    _timer = Timer.periodic(DevChatConfig.pollInterval, (_) => pollOnce());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> pollOnce() async {
    if (!DevChatConfig.isConfigured) return;
    final current = state.value;
    if (current == null) return;
    try {
      final userId = await _store.userId();
      final since = await _store.since();
      final offset = DevChatConfig.sinceSafetyMargin.inMilliseconds;
      final safeSince = since > offset ? since - offset : 0;
      final result = await _service.poll(userId: userId, since: safeSince);
      if (result.messages.isEmpty) {
        await _store.setSince(result.now);
        return;
      }
      final existing = current.messages.map((m) => m.id).toSet();
      final incoming =
          result.messages.where((m) => !existing.contains(m.id)).toList();
      if (incoming.isEmpty) {
        await _store.setSince(result.now);
        return;
      }
      final merged = [...current.messages, ...incoming]
        ..sort((a, b) => a.ts.compareTo(b.ts));
      await _store.saveMessages(merged);
      await _store.setSince(result.now);
      state = AsyncData(current.copyWith(messages: merged));
    } catch (_) {
      // Transient network error — keep the cursor, retry on the next tick.
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !DevChatConfig.isConfigured) return;
    final current = state.value ?? const DevChatState();
    final nick = current.hasNick ? current.nick!.trim() : 'user';

    final msg = DevChatMessage(
      id: generateId(),
      fromDev: false,
      text: trimmed,
      ts: DateTime.now().millisecondsSinceEpoch,
      status: DevMsgStatus.sending,
    );
    var messages = [...current.messages, msg];
    state = AsyncData(current.copyWith(messages: messages));
    await _store.saveMessages(messages);

    try {
      final userId = await _store.userId();
      await _service.send(userId: userId, nick: nick, text: trimmed);
      messages = _mark(messages, msg.id, DevMsgStatus.sent);
    } catch (_) {
      messages = _mark(messages, msg.id, DevMsgStatus.failed);
    }
    await _store.saveMessages(messages);
    state = AsyncData((state.value ?? current).copyWith(messages: messages));
  }

  /// Retries a previously failed message by resending its text.
  Future<void> retry(DevChatMessage failed) async {
    final current = state.value ?? const DevChatState();
    final messages =
        current.messages.where((m) => m.id != failed.id).toList();
    state = AsyncData(current.copyWith(messages: messages));
    await _store.saveMessages(messages);
    await send(failed.text);
  }

  List<DevChatMessage> _mark(
    List<DevChatMessage> list,
    String id,
    DevMsgStatus status,
  ) =>
      [
        for (final m in list) m.id == id ? m.copyWith(status: status) : m,
      ];
}

class DevChatHiddenController extends AsyncNotifier<bool> {
  DevChatStore get _store => ref.read(devChatStoreProvider);

  @override
  Future<bool> build() => _store.hidden();

  Future<void> set(bool value) async {
    await _store.setHidden(value);
    state = AsyncData(value);
  }
}
