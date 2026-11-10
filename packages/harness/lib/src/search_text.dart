/// Letters, marks and digits of any script; an apostrophe splits a word, as it does in the index.
const _wordChar = r'\p{L}\p{M}\p{N}';
final _tokenPattern = RegExp('[$_wordChar]+', unicode: true);

/// Function words. A query of only these still runs, as an exact phrase.
const searchStopWords = {
  'the', 'and', 'of', 'to', 'a', 'an', 'in', 'is', 'it', 'that', 'this', 'with', 'for', 'as', //
  'was', 'be', 'are', 'by', 'on', 'at', 'or', 'but', 'not', 'he', 'his', 'him', 'she', 'her',
  'they', 'them', 'their', 'i', 'you', 'your', 'we', 'our', 'my', 'me', 'who', 'which',
};

List<String> searchTokens(String text) => [
  for (final m in _tokenPattern.allMatches(text.toLowerCase())) m[0]!,
];

/// True for a query that is one function word ("the", "and"). It matches most of the Bible and
/// lists nothing a reader can use.
bool searchIsTooCommon(String text) {
  final tokens = searchTokens(text);
  return tokens.length == 1 && searchStopWords.contains(tokens.first);
}

/// Matches [tokens] as whole, consecutive words in any case, however punctuation separates them.
RegExp phrasePattern(List<String> tokens) => RegExp(
  '(?<![$_wordChar])${tokens.map(RegExp.escape).join('[^$_wordChar]+')}(?![$_wordChar])',
  unicode: true,
  caseSensitive: false,
);
