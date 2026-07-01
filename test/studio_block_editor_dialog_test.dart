import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/studio_config.dart';
import 'package:glaze_flutter/features/studio/widgets/studio_block_editor_dialog.dart';

void main() {
  group('StudioBlockEditorDialog', () {
    testWidgets('returns updated block on Save', (tester) async {
      final block = StudioPresetBlock(
        id: 'test_block',
        title: 'Original Title',
        kind: 'custom_text',
        role: 'system',
        content: 'Original content',
        enabled: true,
        order: 5,
        section: 'pregen',
      );

      StudioPresetBlock? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<StudioPresetBlock>(
                    context: context,
                    builder: (_) => StudioBlockEditorDialog(block: block),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Block'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.id, 'test_block');
      expect(result!.title, 'Original Title');
      expect(result!.section, 'pregen');
    });

    testWidgets('returns null on Cancel', (tester) async {
      final block = StudioPresetBlock(
        id: 'test_block',
        title: 'Test',
        section: 'final',
      );

      StudioPresetBlock? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<StudioPresetBlock>(
                    context: context,
                    builder: (_) => StudioBlockEditorDialog(block: block),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('shows all section options in dropdown', (tester) async {
      final block = StudioPresetBlock(
        id: 'test_block',
        title: 'Test',
        section: 'pregen',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await showDialog<StudioPresetBlock>(
                    context: context,
                    builder: (_) => StudioBlockEditorDialog(block: block),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Block'), findsOneWidget);
      expect(find.text('pregen'), findsOneWidget);
      expect(find.text('custom_text'), findsOneWidget);
      expect(find.text('system'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
    });

    testWidgets('shows New Block title for new blocks', (tester) async {
      final block = StudioPresetBlock(
        id: 'new_block',
        title: '',
        section: 'pregen',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await showDialog<StudioPresetBlock>(
                    context: context,
                    builder: (_) =>
                        StudioBlockEditorDialog(block: block, isNew: true),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('New Block'), findsOneWidget);
    });
  });
}
