import 'prompt_builder.dart';
import 'prompt_inputs.dart';

class PromptPayloadAssembler {
  const PromptPayloadAssembler();

  /// Pure transformation: prompt inputs -> prompt payload.
  /// Does NOT touch Riverpod, async I/O, or network. Use this in unit tests
  /// or in scenarios where vector search and memory injection results have
  /// already been computed by [PromptPayloadBuilder] (which owns async work).
  ///
  /// Note: this only maps fields that exist on [PromptInputs]. Runtime-only
  /// fields (memoryCoverage, summaryPrefix, preScannedEntries) must be set
  /// via [PromptPayload.copyWith] after this call.
  PromptPayload assemble(PromptInputs inputs) {
    return PromptPayload(
      character: inputs.character,
      persona: inputs.persona,
      preset: inputs.preset,
      history: inputs.history,
      apiConfig: inputs.apiConfig,
      sessionVars: inputs.sessionVars,
      globalVars: inputs.globalVars,
      lorebooks: inputs.lorebooks,
      lorebookSettings: inputs.lorebookSettings,
      lorebookActivations: inputs.lorebookActivations,
      vectorEntries: inputs.vectorEntries,
      summaryContent: inputs.summaryContent,
      memoryContent: null,
      memoryMacroContent: null,
      memoryInjectionTarget: inputs.memoryInjectionTarget,
      guidanceText: inputs.guidanceText,
      authorsNote: inputs.authorsNote,
      characterDepthPrompt: inputs.characterDepthPrompt,
      characterDepthPromptDepth: inputs.characterDepthPromptDepth,
      characterDepthPromptRole: inputs.characterDepthPromptRole,
      globalRegexes: inputs.globalRegexes,
      triggeredMemories: const [],
      runtimePromptBlocks: inputs.runtimePromptBlocks,
    );
  }
}
