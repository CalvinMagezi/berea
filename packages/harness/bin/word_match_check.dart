// How often a word pressed in the reader finds the Hebrew or Greek word behind it. No model needed.
// Usage: dart run bin/word_match_check.dart [--translation BSB] [--verses 2000] [--show 30]
import 'dart:math';

import 'package:berea_harness/berea_harness.dart';

/// Words a reader would not study; they are left out of the rate.
const _skip = {
  'the',
  'a',
  'an',
  'and',
  'of',
  'to',
  'in',
  'that',
  'for',
  'on',
  'with',
  'as',
  'at',
  'by',
  'from',
  'is',
  'was',
  'be',
  'are',
  'were',
  'it',
  'he',
  'she',
  'they',
  'his',
  'her',
  'their',
  'them',
  'him',
  'you',
  'your',
  'i',
  'me',
  'my',
  'we',
  'us',
  'our',
  'this',
  'these',
  'those',
  'who',
  'which',
  'what',
  'not',
  'but',
  'or',
  'so',
  'then',
  'all',
  'will',
  'shall',
  'have',
  'has',
  'had',
  'there',
  'when',
  'into',
  'out',
  'up',
  'do',
  'did',
  'ye',
  'thee',
  'thou',
  'thy',
};

void main(List<String> args) {
  String opt(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final translation = opt('translation', defaultTranslation);
  final sample = int.parse(opt('verses', '2000'));
  final show = int.parse(opt('show', '30'));
  final db = BibleDb.open('../../assets/berea.sqlite');
  final rng = Random(17);
  final ids = [
    for (final r in db.db.select('SELECT id FROM verses WHERE translation = ?', [translation]))
      r['id'] as int,
  ];
  var words = 0, matched = 0;
  final ot = [0, 0], nt = [0, 0];
  final examples = <String>[];
  for (var n = 0; n < sample; n++) {
    final r = db.db.select('SELECT book, chapter, verse, text FROM verses WHERE id = ?', [
      ids[rng.nextInt(ids.length)],
    ]).first;
    final ref = Ref(bookById(r['book'] as int), r['chapter'] as int, r['verse'] as int);
    final tags = db.words(ref);
    if (tags.isEmpty) continue;
    final text = r['text'] as String;
    for (final m in RegExp(r"[A-Za-z']+").allMatches(text)) {
      if (_skip.contains(m[0]!.toLowerCase())) continue;
      final at = wordAt(text, m.start)!;
      final hit = matchOriginal(tags, at.word, occurrence: at.occurrence, lexicon: db.lexicon);
      words++;
      final side = ref.book.id < 40 ? ot : nt;
      side[0]++;
      if (hit.isNotEmpty) {
        matched++;
        side[1]++;
      }
      if (examples.length < show && rng.nextInt(40) == 0) {
        final w = hit.isEmpty ? null : tags[hit.first];
        examples.add(
          '${ref.label.padRight(22)} ${at.word.padRight(14)} '
          '${w == null ? '(no match: pick from the verse)' : '${cleanOriginal(w.original)} '
                    '${w.translit} "${w.gloss}" ${studyCode(w)}'}',
        );
      }
    }
  }
  String pct(int a, int b) => b == 0 ? '-' : '${(100 * a / b).toStringAsFixed(1)}%';
  print(
    '$translation, $sample verses: $matched of $words study words matched (${pct(matched, words)})',
  );
  print('  Old Testament ${pct(ot[1], ot[0])}, New Testament ${pct(nt[1], nt[0])}');
  print('\nSample (check by eye that the original word is the one behind the English):');
  examples.forEach(print);
  db.close();
}
