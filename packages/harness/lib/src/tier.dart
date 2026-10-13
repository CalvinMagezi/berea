/// Budget per model class. Prompt budget is in estimated tokens ([estimateTokens]).
enum Tier {
  low(
    promptTokens: 2000,
    searchK: 3,
    xrefK: 4,
    lexiconWords: 6,
    maxOutput: 600,
    sourceTokens: 700,
    sourceK: 3,
    commentaryK: 0,
  ),
  mid(
    promptTokens: 4000,
    searchK: 6,
    xrefK: 8,
    lexiconWords: 12,
    maxOutput: 900,
    sourceTokens: 1400,
    sourceK: 6,
    commentaryK: 1,
  ),
  high(
    promptTokens: 8000,
    searchK: 10,
    xrefK: 12,
    lexiconWords: 24,
    maxOutput: 1400,
    sourceTokens: 3000,
    sourceK: 12,
    commentaryK: 2,
  );

  final int promptTokens;
  final int searchK;
  final int xrefK;
  final int lexiconWords;
  final int maxOutput;

  /// The share of [promptTokens] notebook sources may use; a chunk is about 330 tokens of English.
  final int sourceTokens;

  /// Notebook chunks fetched per kind of retrieval (pinned, search, openings).
  final int sourceK;

  /// Passages of installed commentary considered for a notebook answer.
  final int commentaryK;
  const Tier({
    required this.promptTokens,
    required this.searchK,
    required this.xrefK,
    required this.lexiconWords,
    required this.maxOutput,
    required this.sourceTokens,
    required this.sourceK,
    required this.commentaryK,
  });

  /// The context the engine is opened with: prompt budget, answer, and [contextPadding].
  int get contextWindow => promptTokens + maxOutput + contextPadding;
}

/// Room left in the context for the chat template and for error in [estimateTokens].
const contextPadding = 512;

const _charsPerToken = 4;
final _ownToken = RegExp(r'[^A-Za-z\s]');

/// Model tokens in [s], estimated high. English words run about four characters to a token, but
/// the Gemma tokenizer gives every digit its own token, punctuation in references and codes
/// rarely merges, and Hebrew and Greek with their points and accents come close to one token per
/// code unit. chars / 4 undercounted real prompts by up to half; `bin/prompt_size.dart` checks
/// this estimate against the model's own count.
int estimateTokens(String s) {
  final single = _ownToken.allMatches(s).length;
  return single + ((s.length - single) / _charsPerToken).ceil();
}
