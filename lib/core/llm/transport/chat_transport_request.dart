/// Provider-neutral input for [ChatTransport.stream].
///
/// Mirrors the shape of OpenAI Chat Completions request body — that's also
/// the format current consumers build, so this is a near-identity carrier.
/// Non-OpenAI transports re-shape it via converters in `lib/core/llm/converters/`.
///
/// Multimodal: `messages[i].content` may be a `String` or a `List` of OpenAI-shape
/// content parts (`{type: "text", text}`, `{type: "image_url", image_url: {url}}`).
/// Anthropic/Gemini transports convert these parts to their native shape.
class ChatTransportRequest {
  /// API endpoint base URL (e.g. `https://api.openai.com`). Ignored by
  /// `OpenRouterChatTransport` (URL is hardcoded).
  final String endpoint;
  final String apiKey;
  final String model;

  /// OpenAI-shape messages — see class docstring.
  final List<Map<String, dynamic>> messages;

  final int maxTokens;
  final double temperature;
  final double topP;
  final bool stream;
  final bool requestReasoning;
  final String? reasoningEffort;
  final bool omitTemperature;
  final bool omitTopP;
  final bool omitReasoning;
  final bool omitReasoningEffort;

  /// Optional session ID — forwarded as `session_id` in body when prompt
  /// caching is enabled (OpenRouter / Anthropic-via-OR scenarios).
  final String? sessionId;

  /// Anthropic prompt cache TTL: `'off' | '5min' | '1h'`.
  final String cacheControlTtl;

  const ChatTransportRequest({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.messages,
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    this.stream = true,
    this.requestReasoning = false,
    this.reasoningEffort,
    this.omitTemperature = false,
    this.omitTopP = false,
    this.omitReasoning = false,
    this.omitReasoningEffort = false,
    this.sessionId,
    this.cacheControlTtl = 'off',
  });
}
