enum MemoryStudioStage {
  memoryCurator,
  summarizer,
  trackerUpdater,
  scenarioWriter,
  director,
  operator,
  mainResponder,
}

enum MemoryStudioOutputDisposition { ephemeral, proposed, canonical }

class MemoryStudioSettings {
  final bool experimentalEnabled;
  final bool persistIntermediateActivity;
  final bool allowCanonicalWrites;
  final bool requireExplicitConfirmation;

  const MemoryStudioSettings({
    this.experimentalEnabled = false,
    this.persistIntermediateActivity = false,
    this.allowCanonicalWrites = false,
    this.requireExplicitConfirmation = true,
  });
}

class MemoryStudioStagePlan {
  final MemoryStudioStage stage;
  final MemoryStudioOutputDisposition disposition;
  final String purpose;

  const MemoryStudioStagePlan({
    required this.stage,
    required this.disposition,
    required this.purpose,
  });
}

class MemoryStudioPolicy {
  final MemoryStudioSettings settings;

  const MemoryStudioPolicy(this.settings);

  bool get isAvailable => settings.experimentalEnabled;

  bool get shouldPersistIntermediateActivity {
    return settings.experimentalEnabled && settings.persistIntermediateActivity;
  }

  bool canUseStage(MemoryStudioStage stage) {
    return settings.experimentalEnabled &&
        _defaultPipeline.any((plan) => plan.stage == stage);
  }

  bool canPersist(MemoryStudioOutputDisposition disposition) {
    if (!settings.experimentalEnabled) return false;
    switch (disposition) {
      case MemoryStudioOutputDisposition.ephemeral:
        return false;
      case MemoryStudioOutputDisposition.proposed:
        return settings.persistIntermediateActivity;
      case MemoryStudioOutputDisposition.canonical:
        return settings.allowCanonicalWrites &&
            !settings.requireExplicitConfirmation;
    }
  }

  List<MemoryStudioStagePlan> defaultPipeline() {
    if (!settings.experimentalEnabled) return const [];
    return _defaultPipeline;
  }

  static const List<MemoryStudioStagePlan> _defaultPipeline = [
    MemoryStudioStagePlan(
      stage: MemoryStudioStage.memoryCurator,
      disposition: MemoryStudioOutputDisposition.ephemeral,
      purpose: 'Select evidence-backed memory context.',
    ),
    MemoryStudioStagePlan(
      stage: MemoryStudioStage.scenarioWriter,
      disposition: MemoryStudioOutputDisposition.ephemeral,
      purpose: 'Review unresolved arcs and obligations.',
    ),
    MemoryStudioStagePlan(
      stage: MemoryStudioStage.director,
      disposition: MemoryStudioOutputDisposition.ephemeral,
      purpose: 'Plan tone, pacing, and continuity risks.',
    ),
    MemoryStudioStagePlan(
      stage: MemoryStudioStage.mainResponder,
      disposition: MemoryStudioOutputDisposition.ephemeral,
      purpose: 'Produce the final in-character response.',
    ),
  ];
}
