/// Status of a single expected word after aligning against what was recognized.
enum WordStatus { pending, correct, wrong, missing }

class WordMatchResult {
  final List<WordStatus> expectedWordStatus; // one entry per expected word
  final List<String?> recognizedWordForExpected; // what was heard at that
  // position, if anything (for showing "you said X, expected Y")
  final int extraWordCount; // spoken words that didn't align to any expected word
  final int correctCount;
  final int currentPosition; // index of the next expected word still pending

  WordMatchResult({
    required this.expectedWordStatus,
    required this.recognizedWordForExpected,
    required this.extraWordCount,
    required this.correctCount,
    required this.currentPosition,
  });

  double get accuracy {
    final total = expectedWordStatus.length;
    if (total == 0) return 0;
    return correctCount / total;
  }
}

/// Normalizes Arabic text for comparison: strips diacritics (tashkeel),
/// normalizes alef variants, and removes punctuation, so minor recognizer
/// differences in diacritics don't register as word-level mistakes (that is
/// a Tajweed-level concern, handled separately, not a memorization mistake).
String normalizeArabic(String input) {
  var text = input;
  // Strip Arabic diacritics (harakat/tashkeel) - Unicode range 0x064B-0x065F, 0x0670
  text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
  // Normalize alef variants to bare alef
  text = text.replaceAll(RegExp(r'[\u0622\u0623\u0625]'), '\u0627');
  // Normalize alef maksura to yeh
  text = text.replaceAll('\u0649', '\u064A');
  // Remove tatweel (kashida)
  text = text.replaceAll('\u0640', '');
  // Strip punctuation/whitespace edges
  text = text.trim();
  return text;
}

List<String> tokenize(String text) {
  return text
      .split(RegExp(r'\s+'))
      .map(normalizeArabic)
      .where((w) => w.isNotEmpty)
      .toList();
}

/// Aligns the recognized words against the expected ayah words using a
/// Levenshtein-style edit-distance alignment (Needleman-Wunsch), so each
/// discrepancy is classified as correct / wrong / missing, with position.
/// Spoken words that don't correspond to any expected word are counted as
/// "extra" separately.
WordMatchResult alignWords({
  required List<String> expectedWords,
  required List<String> recognizedWords,
}) {
  final m = expectedWords.length;
  final n = recognizedWords.length;

  // dp[i][j] = min edit operations to align expected[0..i) with recognized[0..j)
  final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = 0; i <= m; i++) dp[i][0] = i;
  for (var j = 0; j <= n; j++) dp[0][j] = j;

  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (expectedWords[i - 1] == recognizedWords[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        final substitution = dp[i - 1][j - 1] + 1;
        final deletion = dp[i - 1][j] + 1; // expected word missing
        final insertion = dp[i][j - 1] + 1; // extra spoken word
        dp[i][j] = [substitution, deletion, insertion].reduce((a, b) => a < b ? a : b);
      }
    }
  }

  // Backtrack to build the alignment
  final expectedStatus = List<WordStatus>.filled(m, WordStatus.missing);
  final recognizedForExpected = List<String?>.filled(m, null);
  var extraCount = 0;
  var correctCount = 0;

  var i = m, j = n;
  final ops = <String>[]; // for backtracking order (reversed)
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && expectedWords[i - 1] == recognizedWords[j - 1] && dp[i][j] == dp[i - 1][j - 1]) {
      expectedStatus[i - 1] = WordStatus.correct;
      recognizedForExpected[i - 1] = recognizedWords[j - 1];
      correctCount++;
      i--;
      j--;
    } else if (i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + 1) {
      expectedStatus[i - 1] = WordStatus.wrong;
      recognizedForExpected[i - 1] = recognizedWords[j - 1];
      i--;
      j--;
    } else if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
      expectedStatus[i - 1] = WordStatus.missing;
      i--;
    } else {
      // insertion - extra spoken word not matching any expected word
      extraCount++;
      j--;
    }
    ops.add(''); // placeholder, order not otherwise needed
  }

  // Find how far into the ayah the recitation has progressed: the last
  // expected word that has a non-pending status, +1. Words after that are
  // still "pending" (not yet reached), not "missing" - only backtrack marks
  // trailing words as missing if the recognizer has clearly moved past them
  // (i.e. recognizedWords is non-empty and alignment placed later words
  // after them). We approximate "pending" as: any run of missing words at
  // the very end of the ayah, beyond the recognized content, is pending
  // rather than a mistake, since the user simply hasn't recited them yet.
  var lastNonMissingFromEnd = m; // exclusive index
  for (var k = m - 1; k >= 0; k--) {
    if (expectedStatus[k] != WordStatus.missing) {
      lastNonMissingFromEnd = k + 1;
      break;
    }
    lastNonMissingFromEnd = k;
  }
  for (var k = lastNonMissingFromEnd; k < m; k++) {
    expectedStatus[k] = WordStatus.pending;
  }

  return WordMatchResult(
    expectedWordStatus: expectedStatus,
    recognizedWordForExpected: recognizedForExpected,
    extraWordCount: extraCount,
    correctCount: correctCount,
    currentPosition: lastNonMissingFromEnd,
  );
}
