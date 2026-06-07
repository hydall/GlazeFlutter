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
  final int topK;
  final double frequencyPenalty;
  final double presencePenalty;
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

  /// Previous request body messages for hash-based cache breakpoint placement.
  final List<Map<String, dynamic>>? previousMessages;

  /// Anthropic prompt cache TTL: `'off' | '5min' | '1h'`.
  final String cacheControlTtl;

  /// Prompt cache breakpoint placement: `'depth' | 'stable_prefix'`.
  final String cacheBreakpointMode;

  const ChatTransportRequest({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.messages,
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    this.topK = 0,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.stream = true,
    this.requestReasoning = false,
    this.reasoningEffort,
    this.omitTemperature = false,
    this.omitTopP = false,
    this.omitReasoning = false,
    this.omitReasoningEffort = false,
    this.sessionId,
    this.previousMessages,
    this.cacheControlTtl = 'off',
    this.cacheBreakpointMode = 'depth',
  });
}
