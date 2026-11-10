import 'dart:math';

/// How much of a verse each stage hides, in percent. The last stage hides every word.
const hideStagePercents = [0, 25, 50, 75, 100];

const _fnvOffset = 0x811c9dc5;
const _fnvPrime = 0x01000193;
const _mask32 = 0xffffffff;

/// A number for [text] that is the same on every run and phone, so a verse hides the same words
/// each time. String.hashCode is not stable across runs.
int stableSeed(String text) {
  var h = _fnvOffset;
  for (final unit in text.codeUnits) {
    h = ((h ^ unit) * _fnvPrime) & _mask32;
  }
  return h;
}

/// The words of [text], split where there is whitespace, so a hidden word keeps its punctuation's
/// place and a blank can be drawn as long as the word.
List<String> verseWords(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// For each stage, the positions of the words it hides. The positions come from a shuffle seeded
/// by [seedText], so each stage hides everything the stage before it did.
List<Set<int>> hideStages(String text, {required String seedText}) {
  final count = verseWords(text).length;
  final order = List<int>.generate(count, (i) => i)
    ..shuffle(Random(stableSeed(seedText)));
  return [
    for (final percent in hideStagePercents)
      order.take((count * percent / 100).ceil()).toSet(),
  ];
}
