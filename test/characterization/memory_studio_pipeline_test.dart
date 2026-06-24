import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/prompt_block_router.dart';
import 'package:glaze_flutter/core/llm/memory_studio_mode.dart';

void main() {
  group('PromptBlockRouter (Phase 11)', () {
    test('classifies memory blocks correctly', () {
      expect(PromptBlockRouter.classifyBlock('Memory Context'), 'memory');
      expect(PromptBlockRouter.classifyBlock('Memory Recall'), 'memory');
    });

    test('classifies continuity blocks correctly', () {
      expect(PromptBlockRouter.classifyBlock('Continuity Check'), 'continuity');
      expect(PromptBlockRouter.classifyBlock('Relationship State'), 'continuity');
      expect(PromptBlockRouter.classifyBlock('Tracker'), 'continuity');
    });

    test('classifies scenario blocks correctly', () {
      expect(PromptBlockRouter.classifyBlock('Scenario Planning'), 'scenario');
      expect(PromptBlockRouter.classifyBlock('Arc Progression'), 'scenario');
      expect(PromptBlockRouter.classifyBlock('Quest Tracker'), 'scenario');
    });

    test('classifies director blocks correctly', () {
      expect(PromptBlockRouter.classifyBlock('Director Notes'), 'director');
      expect(PromptBlockRouter.classifyBlock('Tone and Pacing'), 'director');
    });

    test('classifies style blocks correctly', () {
      expect(PromptBlockRouter.classifyBlock('Writing Style'), 'style');
      expect(PromptBlockRouter.classifyBlock('Prose Guidelines'), 'style');
    });

    test('classifies intimacy/violence blocks correctly', () {
      expect(PromptBlockRouter.classifyBlock('Intimacy Rules'), 'intimacy');
      expect(PromptBlockRouter.classifyBlock('Violence Guidelines'), 'violence');
    });

    test('classifies utility/OOC blocks correctly', () {
      expect(PromptBlockRouter.classifyBlock('Utility Commands'), 'utility');
      expect(PromptBlockRouter.classifyBlock('OOC Instructions'), 'utility');
    });

    test('defaults to final for unrecognized blocks', () {
      expect(PromptBlockRouter.classifyBlock('Some Random Block'), 'final');
    });

    test('filterForStage returns only matching shards', () {
      final blocks = [
        PresetBlockInfo.classify('Memory Context', 'memory content'),
        PresetBlockInfo.classify('Writing Style', 'style content'),
        PresetBlockInfo.classify('Director Notes', 'director content'),
        PresetBlockInfo.classify('OOC', 'utility content'),
      ];

      final curatorShards = PromptBlockRouter.filterForStage(
        StudioStage.memoryCurator,
        blocks,
      );
      expect(curatorShards, hasLength(1));
      expect(curatorShards.first.shard, 'memory');

      final directorShards = PromptBlockRouter.filterForStage(
        StudioStage.director,
        blocks,
      );
      // Director stage gets {'director', 'style', 'continuity'} shards
      expect(directorShards, hasLength(2));
      expect(directorShards.any((s) => s.shard == 'director'), isTrue);
      expect(directorShards.any((s) => s.shard == 'style'), isTrue);

      final responderShards = PromptBlockRouter.filterForStage(
        StudioStage.mainResponder,
        blocks,
      );
      expect(responderShards.any((s) => s.shard == 'style'), isTrue);
      expect(responderShards.any((s) => s.shard == 'utility'), isTrue);
      expect(responderShards.any((s) => s.shard == 'memory'), isFalse);
    });
  });

  group('MemoryStudioPolicy (Phase 11)', () {
    test('disabled by default', () {
      const policy = MemoryStudioPolicy(MemoryStudioSettings());
      expect(policy.isAvailable, isFalse);
      expect(policy.defaultPipeline(), isEmpty);
    });

    test('enabled returns default pipeline', () {
      const policy = MemoryStudioPolicy(
        MemoryStudioSettings(experimentalEnabled: true),
      );
      expect(policy.isAvailable, isTrue);
      final pipeline = policy.defaultPipeline();
      expect(pipeline, hasLength(4));
      expect(pipeline.first.stage, MemoryStudioStage.memoryCurator);
      expect(pipeline.last.stage, MemoryStudioStage.mainResponder);
    });

    test('ephemeral outputs are never persisted', () {
      const policy = MemoryStudioPolicy(
        MemoryStudioSettings(experimentalEnabled: true),
      );
      expect(
        policy.canPersist(MemoryStudioOutputDisposition.ephemeral),
        isFalse,
      );
    });

    test('proposed outputs require persistIntermediateActivity', () {
      const policyNoPersist = MemoryStudioPolicy(
        MemoryStudioSettings(experimentalEnabled: true),
      );
      expect(
        policyNoPersist.canPersist(MemoryStudioOutputDisposition.proposed),
        isFalse,
      );

      const policyPersist = MemoryStudioPolicy(
        MemoryStudioSettings(
          experimentalEnabled: true,
          persistIntermediateActivity: true,
        ),
      );
      expect(
        policyPersist.canPersist(MemoryStudioOutputDisposition.proposed),
        isTrue,
      );
    });

    test('canonical writes require explicit settings', () {
      const policySafe = MemoryStudioPolicy(
        MemoryStudioSettings(
          experimentalEnabled: true,
          allowCanonicalWrites: false,
        ),
      );
      expect(
        policySafe.canPersist(MemoryStudioOutputDisposition.canonical),
        isFalse,
      );

      const policyAuto = MemoryStudioPolicy(
        MemoryStudioSettings(
          experimentalEnabled: true,
          allowCanonicalWrites: true,
          requireExplicitConfirmation: false,
        ),
      );
      expect(
        policyAuto.canPersist(MemoryStudioOutputDisposition.canonical),
        isTrue,
      );
    });

    test('canUseStage only for stages in default pipeline', () {
      const policy = MemoryStudioPolicy(
        MemoryStudioSettings(experimentalEnabled: true),
      );
      expect(policy.canUseStage(MemoryStudioStage.memoryCurator), isTrue);
      expect(policy.canUseStage(MemoryStudioStage.mainResponder), isTrue);
      expect(policy.canUseStage(MemoryStudioStage.operator), isFalse);
      expect(policy.canUseStage(MemoryStudioStage.summarizer), isFalse);
    });
  });
}
