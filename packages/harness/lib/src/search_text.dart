import 'word_study.dart';

/// Letters, marks and digits of any script; an apostrophe splits a word, as it does in the index.
final _tokenPattern = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

/// Function words. A query of only these still runs, as an exact phrase.
const searchStopWords = {
  'the',
  'and',
  'of',
  'to',
  'a',
  'an',
  'in',
  'is',
  'it',
  'that',
  'this',
  'with',
  'for',
  'as', //
  'was',
  'be',
  'are',
  'by',
  'on',
  'at',
  'or',
  'but',
  'not',
  'he',
  'his',
  'him',
  'she',
  'her',
  'they',
  'them',
  'their',
  'i',
  'you',
  'your',
  'we',
  'our',
  'my',
  'me',
  'who',
  'which',
};

final _asciiWord = RegExp(r'^[a-z]+$');

List<String> searchTokens(String text) => [
  for (final m in _tokenPattern.allMatches(text.toLowerCase())) m[0]!,
];

/// The comparison form of one token: English stemming for ASCII words, the word itself otherwise.
String searchStem(String token) =>
    _asciiWord.hasMatch(token) ? wordStem(token) : token;

/// True when [phrase] occurs in [words] as consecutive, identical tokens.
bool containsPhrase(List<String> words, List<String> phrase) {
  if (phrase.isEmpty || phrase.length > words.length) return false;
  for (var i = 0; i + phrase.length <= words.length; i++) {
    var j = 0;
    while (j < phrase.length && words[i + j] == phrase[j]) {
      j++;
    }
    if (j == phrase.length) return true;
  }
  return false;
}
