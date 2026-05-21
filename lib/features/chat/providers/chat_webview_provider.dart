import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/models/chat_message.dart';
import '../bridge/chat_bridge_controller.dart';
import '../widgets/chat_webview_widget.dart';

class ChatWebViewNotifier extends StateNotifier<ChatWebViewWidget?> {
  ChatWebViewNotifier() : super(null);

  ChatBridgeController? _bridgeController;

  void setWidget(ChatWebViewWidget widget) {
    state = widget;
  }

  void setBridgeController(ChatBridgeController controller) {
    _bridgeController = controller;
  }

  Future<void> setMessages(List<ChatMessage> messages) async {
    await _bridgeController?.setMessages(messages);
  }

  Future<void> appendMessage(ChatMessage message) async {
    await _bridgeController?.appendMessage(message);
  }

  Future<void> appendMessages(List<ChatMessage> messages) async {
    for (final message in messages) {
      await _bridgeController?.appendMessage(message);
    }
  }

  Future<void> updateMessage(ChatMessage message) async {
    await _bridgeController?.updateMessage(message);
  }

  Future<void> deleteMessage(String messageId) async {
    await _bridgeController?.deleteMessage(messageId);
  }

  Future<void> scrollToBottom() async {
    await _bridgeController?.scrollToBottom();
  }

  Future<void> scrollToMessage(String messageId) async {
    await _bridgeController?.scrollToMessage(messageId);
  }

  Future<void> scrollToTop() async {
    await _bridgeController?.scrollToTop();
  }

  Future<void> setSearch({
    required String query,
    int activeIndex = -1,
  }) async {
    await _bridgeController?.setSearch(
      query: query,
      activeIndex: activeIndex,
    );
  }

  Future<void> scrollToSearchMatch(int index) async {
    await _bridgeController?.scrollToSearchMatch(index);
  }

  Future<bool?> isNearBottom() async {
    return await _bridgeController?.isNearBottom();
  }

  Future<bool?> isNearTop() async {
    return await _bridgeController?.isNearTop();
  }

  @override
  void dispose() {
    _bridgeController?.dispose();
    super.dispose();
  }
}

final chatWebViewProvider =
    StateNotifierProvider<ChatWebViewNotifier, ChatWebViewWidget?>((ref) {
  return ChatWebViewNotifier();
});
