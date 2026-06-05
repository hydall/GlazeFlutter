import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';
import 'package:glaze_flutter/features/cloud_sync/services/sync_serialization.dart';

void main() {
  test('computeMemoryBookHash ignores device-local generation settings', () {
    final base = MemoryBook(
      id: 'memorybook_s1',
      sessionId: 's1',
      updatedAt: 1000,
      lastProcessedMessageCount: 42,
    ).toJson();
    final withLocalGen = MemoryBook(
      id: 'memorybook_s1',
      sessionId: 's1',
      updatedAt: 999999,
      lastProcessedMessageCount: 99,
      settings: const MemoryBookSettings(
        generationApiKey: 'sk-local-secret',
        generationModel: 'local-model',
        generationEndpoint: 'http://localhost:1234',
      ),
    ).toJson();

    final fromMake = MemoryBook(
      id: 'memorybook_s1',
      sessionId: 's1',
      updatedAt: 1000,
    ).toJson();

    final baseHash = SyncSerialization.computeMemoryBookHash(base);
    expect(
      SyncSerialization.computeMemoryBookHash(withLocalGen),
      equals(baseHash),
    );
    expect(
      SyncSerialization.computeMemoryBookHash(fromMake),
      equals(baseHash),
    );

    final cloudJson =
        jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    expect(
      SyncSerialization.computeMemoryBookHash(cloudJson),
      equals(baseHash),
    );
  });
}
