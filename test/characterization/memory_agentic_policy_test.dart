import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/memory_agentic_policy.dart';

void main() {
  test('agentic mode is disabled and write-blocked by default', () {
    const policy = MemoryAgenticPolicy(MemoryAgenticSettings());

    final read = policy.canUse(MemoryAgenticTool.inspectContext);
    final write = policy.canUse(MemoryAgenticTool.writeMemory);

    expect(read.allowed, isFalse);
    expect(read.reason, 'agentic_disabled');
    expect(write.allowed, isFalse);
    expect(write.reason, 'agentic_disabled');
  });

  test('enabled agentic scaffold allows read-only proposal tools', () {
    const policy = MemoryAgenticPolicy(MemoryAgenticSettings(enabled: true));

    expect(policy.canUse(MemoryAgenticTool.inspectContext).allowed, isTrue);
    expect(policy.canUse(MemoryAgenticTool.proposeMemory).allowed, isTrue);
    expect(policy.canUse(MemoryAgenticTool.proposeTracker).allowed, isTrue);
  });

  test('write tools require non-read-only mode and write tool opt-in', () {
    const readOnly = MemoryAgenticPolicy(MemoryAgenticSettings(enabled: true));
    const writeDisabled = MemoryAgenticPolicy(
      MemoryAgenticSettings(enabled: true, readOnly: false),
    );

    expect(
      readOnly.canUse(MemoryAgenticTool.writeMemory).reason,
      'agentic_read_only',
    );
    expect(
      writeDisabled.canUse(MemoryAgenticTool.writeMemory).reason,
      'write_tools_disabled',
    );
  });

  test('write tools require explicit diff approval by default', () {
    const policy = MemoryAgenticPolicy(
      MemoryAgenticSettings(
        enabled: true,
        readOnly: false,
        writeToolsEnabled: true,
      ),
    );

    expect(
      policy.canUse(MemoryAgenticTool.writeTracker).reason,
      'diff_approval_required',
    );
    expect(
      policy
          .canUse(MemoryAgenticTool.writeTracker, explicitDiffApproved: true)
          .allowed,
      isTrue,
    );
  });
}
