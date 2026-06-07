import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/api_config.dart';
import 'anthropic_chat_transport.dart';
import 'chat_transport.dart';
import 'gemini_chat_transport.dart';
import 'llm_protocol.dart';
import 'openai_chat_transport.dart';
import 'openrouter_chat_transport.dart';

/// Resolves a [ChatTransport] for the given protocol string.
///
/// Unknown / legacy values fall back to OpenAI for safety — that keeps
/// pre-v23 configs (no `protocol` field) working without any UI prompt.
///
/// Implementations are stateless and cheap to instantiate, so the factory
/// just `new`s on every call. If a transport ever needs shared HTTP-client
/// state, register it as a singleton here.
ChatTransport pickChatTransport(String protocol) {
  switch (protocol) {
    case LlmProtocol.openai:
      return OpenAiChatTransport();
    case LlmProtocol.anthropic:
      return AnthropicChatTransport();
    case LlmProtocol.gemini:
      return GeminiChatTransport();
    case LlmProtocol.openrouter:
      return OpenRouterChatTransport();
    default:
      return OpenAiChatTransport();
  }
}

ChatTransport pickChatTransportFor(ApiConfig config) =>
    pickChatTransport(config.protocol);

/// Riverpod handle for consumers that prefer DI over the bare function.
final chatTransportFactoryProvider =
    Provider<ChatTransport Function(String)>((_) => pickChatTransport);
