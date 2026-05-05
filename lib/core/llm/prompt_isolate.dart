import 'package:flutter/foundation.dart';

import 'prompt_builder.dart';

Future<PromptResult> buildPromptInIsolate(PromptPayload payload) {
  return compute(_buildPromptEntry, payload);
}

PromptResult _buildPromptEntry(PromptPayload payload) {
  return buildPrompt(payload);
}
