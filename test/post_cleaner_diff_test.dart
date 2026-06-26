import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/features/chat/widgets/post_cleaner_line_diff.dart';

void main() {
  group('computeLineDiff', () {
    test('identical text → all same lines', () {
      final result = computeLineDiff('a\nb\nc', 'a\nb\nc');
      expect(result.removedLines, 0);
      expect(result.addedLines, 0);
      expect(result.leftLines.length, 3);
      expect(result.rightLines.length, 3);
      for (final line in result.leftLines) {
        expect(line.type, DiffLineType.same);
      }
    });

    test('completely different text → all removed + all added', () {
      final result = computeLineDiff('x\ny', 'a\nb');
      expect(result.removedLines, 2);
      expect(result.addedLines, 2);
      // First two left lines are removed, last two right lines are added
      expect(result.leftLines[0].type, DiffLineType.removed);
      expect(result.leftLines[1].type, DiffLineType.removed);
      expect(result.rightLines[2].type, DiffLineType.added);
      expect(result.rightLines[3].type, DiffLineType.added);
      expect(result.rightLines[2].text, 'a');
      expect(result.rightLines[3].text, 'b');
    });

    test('middle line removed from left', () {
      final result = computeLineDiff('a\nb\nc', 'a\nc');
      expect(result.removedLines, 1);
      expect(result.addedLines, 0);
      // Left has 3 entries (a, b-removed, c), right has 3 (a, ''-removed, c)
      expect(result.leftLines[1].text, 'b');
      expect(result.leftLines[1].type, DiffLineType.removed);
      expect(result.rightLines[1].text, '');
      expect(result.rightLines[1].type, DiffLineType.removed);
    });

    test('middle line added on right', () {
      final result = computeLineDiff('a\nc', 'a\nb\nc');
      expect(result.addedLines, 1);
      expect(result.removedLines, 0);
      // Left has 3 entries (a, ''-added, c), right has 3 (a, b-added, c)
      expect(result.rightLines[1].text, 'b');
      expect(result.rightLines[1].type, DiffLineType.added);
      expect(result.leftLines[1].text, '');
      expect(result.leftLines[1].type, DiffLineType.added);
    });

    test('line changed (removed + added)', () {
      final result = computeLineDiff('a\nold\nc', 'a\nnew\nc');
      expect(result.removedLines, 1);
      expect(result.addedLines, 1);
      // Find the removed line on the left
      final removedLeft = result.leftLines.where((l) => l.type == DiffLineType.removed).first;
      expect(removedLeft.text, 'old');
      // Find the added line on the right
      final addedRight = result.rightLines.where((l) => l.type == DiffLineType.added).first;
      expect(addedRight.text, 'new');
    });

    test('empty original → all added', () {
      final result = computeLineDiff('', 'a\nb');
      expect(result.removedLines, 0);
      expect(result.addedLines, 2);
    });

    test('empty cleaned → all removed', () {
      final result = computeLineDiff('a\nb', '');
      expect(result.removedLines, 2);
      expect(result.addedLines, 0);
    });

    test('both empty → no diff', () {
      final result = computeLineDiff('', '');
      expect(result.removedLines, 0);
      expect(result.addedLines, 0);
      expect(result.leftLines, isEmpty);
      expect(result.rightLines, isEmpty);
    });

    test('prefix preserved, suffix added', () {
      final result = computeLineDiff('a\nb', 'a\nb\nc\nd');
      expect(result.removedLines, 0);
      expect(result.addedLines, 2);
      expect(result.leftLines[0].type, DiffLineType.same);
      expect(result.leftLines[1].type, DiffLineType.same);
      // Added lines are at the end of right
      final added = result.rightLines.where((l) => l.type == DiffLineType.added).toList();
      expect(added.length, 2);
      expect(added[0].text, 'c');
      expect(added[1].text, 'd');
    });

    test('preserves line count alignment (left and right same length)', () {
      final result = computeLineDiff('a\nb\nc', 'a\nx\nc');
      expect(result.leftLines.length, result.rightLines.length);
    });

    test('multiline prose with changed paragraph', () {
      final orig = 'First paragraph stays.\n\nSecond paragraph is old text.\n\nThird paragraph stays.';
      final cleaned = 'First paragraph stays.\n\nSecond paragraph is new text.\n\nThird paragraph stays.';
      final result = computeLineDiff(orig, cleaned);
      expect(result.removedLines, 1);
      expect(result.addedLines, 1);
      final removedLine = result.leftLines.where((l) => l.type == DiffLineType.removed).first;
      expect(removedLine.text, 'Second paragraph is old text.');
      final addedLine = result.rightLines.where((l) => l.type == DiffLineType.added).first;
      expect(addedLine.text, 'Second paragraph is new text.');
    });
  });
}
