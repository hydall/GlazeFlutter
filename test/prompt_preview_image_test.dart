import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/history_assembler.dart';
import 'package:glaze_flutter/features/chat/widgets/prompt_preview_screen.dart';

void main() {
  const png =
      'data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

  testWidgets('formatted preview renders a local image thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PromptAttachmentPreview(imagePath: png)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('prompt-attachment-image')), findsOne);
    expect(
      find.byKey(const ValueKey('prompt-attachment-unavailable')),
      findsNothing,
    );
  });

  testWidgets('malformed and remote images use a safe fallback', (
    tester,
  ) async {
    for (final path in [
      'data:image/png;base64,not-valid!',
      'https://x.test/a',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PromptAttachmentPreview(imagePath: path)),
        ),
      );

      expect(
        find.byKey(const ValueKey('prompt-attachment-unavailable')),
        findsOne,
      );
      expect(find.byType(Image), findsNothing);
    }
  });

  test('preview request retains image-only messages and exact data URI', () {
    final messages = buildPreviewApiMessages(const [
      PromptMessage(role: 'user', content: '', imagePath: png),
    ]);

    expect(messages, [
      {
        'role': 'user',
        'content': [
          {
            'type': 'image_url',
            'image_url': {'url': png},
          },
        ],
      },
    ]);
  });
}
