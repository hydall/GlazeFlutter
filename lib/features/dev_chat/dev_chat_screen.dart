import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dev_chat_config.dart';
import 'dev_chat_message.dart';
import 'dev_chat_provider.dart';
import 'dev_chat_webview.dart';

/// Minimal chat with the developer(s). Plain messaging — no roleplay features,
/// no macros, no swipes. The message list is rendered by a fully self-contained
/// WebView ([DevChatWebView]); everything else (app bar, composer, nickname
/// prompt) is native. Outgoing goes to Telegram via the Worker; replies are
/// polled while this screen is open.
class DevChatScreen extends ConsumerStatefulWidget {
  const DevChatScreen({super.key});

  @override
  ConsumerState<DevChatScreen> createState() => _DevChatScreenState();
}

class _DevChatScreenState extends ConsumerState<DevChatScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  bool _promptedForNick = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(devChatProvider.notifier).startPolling();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(devChatProvider.notifier).stopPolling();
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause polling in the background to avoid pointless network churn.
    final notifier = ref.read(devChatProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      notifier.startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      notifier.stopPolling();
    }
  }

  Future<void> _maybePromptNick(DevChatState data) async {
    if (_promptedForNick || data.hasNick) return;
    _promptedForNick = true;
    final nick = await _askNick(initial: '');
    if (nick != null && nick.trim().isNotEmpty) {
      await ref.read(devChatProvider.notifier).setNick(nick.trim());
    }
  }

  Future<String?> _askNick({required String initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            hintText: 'How should the developers see you?',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(devChatProvider.notifier).send(text);
  }

  void _retry(String id) {
    final data = ref.read(devChatProvider).value;
    for (final m in data?.messages ?? const <DevChatMessage>[]) {
      if (m.id == id) {
        ref.read(devChatProvider.notifier).retry(m);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(devChatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with developer'),
        actions: [
          IconButton(
            tooltip: 'Change nickname',
            icon: const Icon(Icons.badge_outlined),
            onPressed: () async {
              final data = async.value ?? const DevChatState();
              final nick = await _askNick(initial: data.nick ?? '');
              if (nick != null && nick.trim().isNotEmpty) {
                await ref.read(devChatProvider.notifier).setNick(nick.trim());
              }
            },
          ),
        ],
      ),
      body: !DevChatConfig.isConfigured
          ? const _NotConfigured()
          : async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (data) {
                _maybePromptNick(data);
                return Column(
                  children: [
                    Expanded(
                      child: DevChatWebView(
                        messages: data.messages,
                        onRetry: _retry,
                      ),
                    ),
                    _Composer(controller: _input, onSend: _send),
                  ],
                );
              },
            ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Message…',
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(
              'Developer chat is not configured.\n'
              'Set DEV_CHAT_URL to the deployed Worker URL.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
