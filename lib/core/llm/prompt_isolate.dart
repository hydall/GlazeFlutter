import 'prompt_builder.dart';
import 'prompt_worker.dart';

/// Runs buildPrompt in a persistent background isolate.
///
/// The isolate maintains its own o200k_base tokenizer and a persistent
/// token cache, so repeated calls are fast (cached history tokens).
Future<PromptResult> buildPromptInIsolate(PromptPayload payload) async {
  final worker = await PromptWorker.ensureInitialized();
  return worker.buildPrompt(payload);
}
