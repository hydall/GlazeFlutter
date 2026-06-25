import '../../core/models/chat_message.dart';

class ChatState {
  final ChatSession? session;
  final bool isGenerating;
  final bool isGeneratingImage;
  final String? error;
  final String? lastRawResponse;
  final DateTime? generationStartTime;
  final int visibleStartIndex;
  final bool isLoadingOlder;

  final String? regenTargetId;

  static const int initialPageSize = 20;
  static const int olderPageSize = 20;

  const ChatState({
    this.session,
    this.isGenerating = false,
    this.isGeneratingImage = false,
    this.error,
    this.lastRawResponse,
    this.generationStartTime,
    this.visibleStartIndex = 0,
    this.isLoadingOlder = false,
    this.regenTargetId,
  });

  bool get hasMoreOlder => visibleStartIndex > 0;

  List<ChatMessage> get messages => session?.messages ?? [];

  List<ChatMessage> get visibleMessages {
    final all = messages;
    if (visibleStartIndex >= all.length) return all;
    return all.sublist(visibleStartIndex);
  }

  static const _unset = Object();

  ChatState copyWith({
    ChatSession? session,
    bool? isGenerating,
    bool? isGeneratingImage,
    Object? error = _unset,
    String? lastRawResponse,
    DateTime? generationStartTime,
    int? visibleStartIndex,
    bool? isLoadingOlder,
    Object? regenTargetId = _unset,
  }) {
    return ChatState(
      session: session ?? this.session,
      isGenerating: isGenerating ?? this.isGenerating,
      isGeneratingImage: isGeneratingImage ?? this.isGeneratingImage,
      error: error == _unset ? this.error : error as String?,
      lastRawResponse: lastRawResponse ?? this.lastRawResponse,
      generationStartTime: generationStartTime ?? this.generationStartTime,
      visibleStartIndex: visibleStartIndex ?? this.visibleStartIndex,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      regenTargetId: regenTargetId == _unset
          ? this.regenTargetId
          : regenTargetId as String?,
    );
  }
}

class StreamingState {
  final String text;
  final String? reasoning;
  final List<Map<String, dynamic>> studioOutputs;
  final bool studioOutputsExpanded;

  const StreamingState({
    this.text = '',
    this.reasoning,
    this.studioOutputs = const [],
    this.studioOutputsExpanded = false,
  });
}
