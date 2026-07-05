/// Configuration for the "Chat with developer" feature.
///
/// Set the Cloudflare Worker base URL (from `dev_chat_bridge/`) either by
/// editing [_defaultBaseUrl] below or by passing
/// `--dart-define=DEV_CHAT_URL=https://glaze-dev-chat.<you>.workers.dev`
/// at build time. When empty, the feature renders a "not configured" state.
library;

class DevChatConfig {
  const DevChatConfig._();

  /// Paste your deployed Worker URL here (no trailing slash), or override via
  /// `--dart-define=DEV_CHAT_URL=...`.
  static const String _defaultBaseUrl = '';

  static const String baseUrl = String.fromEnvironment(
    'DEV_CHAT_URL',
    defaultValue: _defaultBaseUrl,
  );

  static bool get isConfigured => baseUrl.isNotEmpty;

  /// How often the screen polls for developer replies while it is open.
  static const Duration pollInterval = Duration(seconds: 2);

  /// Safety margin subtracted from the [since] cursor to account for
  /// Cloudflare KV eventual consistency and concurrent webhook writes.
  /// Without this, messages written between polls can be permanently skipped.
  static const Duration sinceSafetyMargin = Duration(seconds: 60);

  // SharedPreferences keys.
  static const String kUserId = 'devChat.userId';
  static const String kNick = 'devChat.nick';
  static const String kHidden = 'devChat.hidden';
  static const String kMessages = 'devChat.messages';
  static const String kSince = 'devChat.since';
}
