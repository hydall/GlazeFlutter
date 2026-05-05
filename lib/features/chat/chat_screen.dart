import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatScreen extends ConsumerWidget {
  final String charId;
  const ChatScreen({super.key, required this.charId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      ),
      body: Column(
        children: [
          const Expanded(
            child: Center(
              child: Text('Chat will appear here'),
            ),
          ),
          _InputBar(
            controller: controller,
            onSend: (text) {
              controller.clear();
              // TODO: implement send message
            },
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final bool isGenerating;

  const _InputBar({
    required this.controller,
    required this.onSend,
    this.isGenerating = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: isGenerating
                  ? null
                  : () => onSend(controller.text),
              icon: Icon(isGenerating ? Icons.stop : Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
