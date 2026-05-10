import '../../core/models/chat_message.dart';

class ChatState {
  final ChatSession? session;
  final bool isGenerating;
  final String streamingText;
  final String? streamingReasoning;
  final String? error;
  final String? lastRawResponse;
  final DateTime? generationStartTime;

  const ChatState({
    this.session,
    this.isGenerating = false,
    this.streamingText = '',
    this.streamingReasoning,
    this.error,
    this.lastRawResponse,
    this.generationStartTime,
  });

  ChatState copyWith({
    ChatSession? session,
    bool? isGenerating,
    String? streamingText,
    String? streamingReasoning,
    String? error,
    String? lastRawResponse,
    DateTime? generationStartTime,
  }) {
    return ChatState(
      session: session ?? this.session,
      isGenerating: isGenerating ?? this.isGenerating,
      streamingText: streamingText ?? this.streamingText,
      streamingReasoning: streamingReasoning ?? this.streamingReasoning,
      error: error,
      lastRawResponse: lastRawResponse ?? this.lastRawResponse,
      generationStartTime: generationStartTime ?? this.generationStartTime,
    );
  }

  List<ChatMessage> get messages => session?.messages ?? [];
}
