import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/memory_studio_mode.dart';

void main() {
  test('studio mode is off by default', () {
    const policy = MemoryStudioPolicy(MemoryStudioSettings());

    expect(policy.isAvailable, isFalse);
    expect(policy.defaultPipeline(), isEmpty);
    expect(policy.canUseStage(MemoryStudioStage.director), isFalse);
  });

  test('disabled studio mode does not persist intermediate activity', () {
    const policy = MemoryStudioPolicy(
      MemoryStudioSettings(persistIntermediateActivity: true),
    );

    expect(policy.shouldPersistIntermediateActivity, isFalse);
    expect(policy.canPersist(MemoryStudioOutputDisposition.proposed), isFalse);
    expect(policy.canPersist(MemoryStudioOutputDisposition.canonical), isFalse);
  });

  test('enabled studio mode exposes read-only ephemeral pipeline', () {
    const policy = MemoryStudioPolicy(
      MemoryStudioSettings(experimentalEnabled: true),
    );

    final pipeline = policy.defaultPipeline();

    expect(pipeline.map((stage) => stage.stage), [
      MemoryStudioStage.memoryCurator,
      MemoryStudioStage.scenarioWriter,
      MemoryStudioStage.director,
      MemoryStudioStage.mainResponder,
    ]);
    expect(pipeline.map((stage) => stage.disposition).toSet(), {
      MemoryStudioOutputDisposition.ephemeral,
    });
    expect(policy.canPersist(MemoryStudioOutputDisposition.ephemeral), isFalse);
  });

  test(
    'canonical writes remain blocked unless future confirmation is relaxed',
    () {
      const confirmationRequired = MemoryStudioPolicy(
        MemoryStudioSettings(
          experimentalEnabled: true,
          allowCanonicalWrites: true,
        ),
      );
      const explicitlyRelaxed = MemoryStudioPolicy(
        MemoryStudioSettings(
          experimentalEnabled: true,
          allowCanonicalWrites: true,
          requireExplicitConfirmation: false,
        ),
      );

      expect(
        confirmationRequired.canPersist(
          MemoryStudioOutputDisposition.canonical,
        ),
        isFalse,
      );
      expect(
        explicitlyRelaxed.canPersist(MemoryStudioOutputDisposition.canonical),
        isTrue,
      );
    },
  );
}
