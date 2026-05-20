import '../../core/models/chat_message.dart';

class ChatState {
  final ChatSession? session;
  final bool isGenerating;
  final bool isGeneratingImage;
  final String? error;
  final String? lastRawResponse;
  final DateTime? generationStartTime;

  const ChatState({
    this.session,
    this.isGenerating = false,
    this.isGeneratingImage = false,
    this.error,
    this.lastRawResponse,
    this.generationStartTime,
  });

  ChatState copyWith({
    ChatSession? session,
    bool? isGenerating,
    bool? isGeneratingImage,
    String? error,
    String? lastRawResponse,
    DateTime? generationStartTime,
  }) {
    return ChatState(
      session: session ?? this.session,
      isGenerating: isGenerating ?? this.isGenerating,
      isGeneratingImage: isGeneratingImage ?? this.isGeneratingImage,
      error: error,
      lastRawResponse: lastRawResponse ?? this.lastRawResponse,
      generationStartTime: generationStartTime ?? this.generationStartTime,
    );
  }

  List<ChatMessage> get messages => session?.messages ?? [];
}

class StreamingState {
  final String text;
  final String? reasoning;

  const StreamingState({this.text = '', this.reasoning});
}
