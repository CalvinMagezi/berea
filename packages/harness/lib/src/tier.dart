/// Budget per model class. Prompt budget is in estimated tokens (chars / 4).
enum Tier {
  low(promptTokens: 2000, searchK: 3, xrefK: 4, lexiconWords: 6, maxOutput: 600),
  mid(promptTokens: 4000, searchK: 6, xrefK: 8, lexiconWords: 12, maxOutput: 900),
  high(promptTokens: 8000, searchK: 10, xrefK: 12, lexiconWords: 24, maxOutput: 1400);

  final int promptTokens;
  final int searchK;
  final int xrefK;
  final int lexiconWords;
  final int maxOutput;
  const Tier({
    required this.promptTokens,
    required this.searchK,
    required this.xrefK,
    required this.lexiconWords,
    required this.maxOutput,
  });
}

int estimateTokens(String s) => (s.length / 4).ceil();
