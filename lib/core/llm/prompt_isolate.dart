import 'dart:isolate';

import 'prompt_builder.dart';

Future<PromptResult> buildPromptInIsolate(PromptPayload payload) {
  return Isolate.run(() => buildPrompt(payload));
}
