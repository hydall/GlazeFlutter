/// Per-line diff algorithm for the POST-cleaner diff viewer.
///
/// Uses LCS (Longest Common Subsequence) to align lines between the original
/// and cleaned text. Each line is classified as `same`, `added`, or `removed`.
/// O(n*m) time and space — fine for prose (typically <200 lines per message).
library;

enum DiffLineType { same, added, removed }

class DiffLine {
  final String text;
  final DiffLineType type;

  const DiffLine(this.text, this.type);
}

class DiffResult {
  final List<DiffLine> leftLines;
  final List<DiffLine> rightLines;
  final int removedLines;
  final int addedLines;

  const DiffResult({
    required this.leftLines,
    required this.rightLines,
    required this.removedLines,
    required this.addedLines,
  });

  const DiffResult.empty()
      : leftLines = const [],
        rightLines = const [],
        removedLines = 0,
        addedLines = 0;
}

/// Computes a per-line diff between [original] and [cleaned] using LCS.
/// Returns aligned left/right line lists where each line is marked as
/// `same`, `added`, or `removed`.
DiffResult computeLineDiff(String original, String cleaned) {
  final left = original.isEmpty ? <String>[] : original.split('\n');
  final right = cleaned.isEmpty ? <String>[] : cleaned.split('\n');
  final n = left.length;
  final m = right.length;

  // LCS DP table.
  final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (left[i] == right[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = dp[i + 1][j] > dp[i][j + 1]
            ? dp[i + 1][j]
            : dp[i][j + 1];
      }
    }
  }

  // Backtrack to build the diff.
  final leftLines = <DiffLine>[];
  final rightLines = <DiffLine>[];
  var i = 0;
  var j = 0;
  var removed = 0;
  var added = 0;

  while (i < n && j < m) {
    if (left[i] == right[j]) {
      leftLines.add(DiffLine(left[i], DiffLineType.same));
      rightLines.add(DiffLine(right[j], DiffLineType.same));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      leftLines.add(DiffLine(left[i], DiffLineType.removed));
      rightLines.add(const DiffLine('', DiffLineType.removed));
      removed++;
      i++;
    } else {
      leftLines.add(const DiffLine('', DiffLineType.added));
      rightLines.add(DiffLine(right[j], DiffLineType.added));
      added++;
      j++;
    }
  }
  while (i < n) {
    leftLines.add(DiffLine(left[i], DiffLineType.removed));
    rightLines.add(const DiffLine('', DiffLineType.removed));
    removed++;
    i++;
  }
  while (j < m) {
    leftLines.add(const DiffLine('', DiffLineType.added));
    rightLines.add(DiffLine(right[j], DiffLineType.added));
    added++;
    j++;
  }

  return DiffResult(
    leftLines: leftLines,
    rightLines: rightLines,
    removedLines: removed,
    addedLines: added,
  );
}
