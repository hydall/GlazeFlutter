import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/features/chat/state/memory_activity_provider.dart';
import 'package:glaze_flutter/features/chat/widgets/memory_activity_card.dart';

void main() {
  Widget buildCard({required bool expanded}) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: MemoryActivityCard(
            activity: const MemoryActivityState(
              sessionId: 's1',
              messageId: 'a1',
              diagnostics: {
                'selectedCount': 1,
                'selectedTokens': 42,
                'totalCandidates': 2,
                'skippedCount': 1,
                'latencyMs': 7,
                'budget': {'effectiveTokens': 1000, 'source': 'absolute'},
                'candidates': [
                  {
                    'entryId': 'm1',
                    'title': 'Bridge memory',
                    'selected': true,
                    'reason': 'selected',
                    'tokenCost': 42,
                    'score': 3.25,
                  },
                  {
                    'entryId': 'm2',
                    'title': 'Visible memory',
                    'selected': false,
                    'reason': 'source_visible_in_prompt',
                    'tokenCost': 20,
                    'score': 0.0,
                  },
                ],
              },
              updatedAtMillis: 123,
            ),
            expanded: expanded,
            onToggle: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('MemoryActivityCard is collapsed by default data shape', (
    tester,
  ) async {
    await tester.pumpWidget(buildCard(expanded: false));

    expect(find.text('Memory: 1 entries, 42 tokens'), findsOneWidget);
    expect(find.text('2 candidates'), findsOneWidget);
    expect(find.textContaining('Bridge memory'), findsNothing);
    expect(find.textContaining('source_visible_in_prompt'), findsNothing);
  });

  testWidgets('MemoryActivityCard expands selected and skipped details', (
    tester,
  ) async {
    await tester.pumpWidget(buildCard(expanded: true));

    expect(find.text('Memory: 1 entries, 42 tokens'), findsOneWidget);
    expect(find.text('skipped 1'), findsOneWidget);
    expect(find.text('latency 7ms'), findsOneWidget);
    expect(find.text('budget 1000 (absolute)'), findsOneWidget);
    expect(find.textContaining('Bridge memory · selected'), findsOneWidget);
    expect(
      find.textContaining('Visible memory · source_visible_in_prompt'),
      findsOneWidget,
    );
  });
}
