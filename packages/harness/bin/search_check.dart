// Measures the search box against the BSB: can a reader find a verse from four of its words,
// does every vocabulary word return something, and how long a search takes.
// Usage: dart run bin/search_check.dart [--db ../../assets/berea.sqlite]
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:berea_harness/src/search_text.dart';
import 'package:sqlite3/sqlite3.dart';

const _phraseWords = 4;
const _verseSampleStep = 15;
const _vocabularySize = 500;
const _minVocabularyLength = 3;
const _timedQueries = 200;
const _topTen = 10;
const _targetTopTen = 93.0;
const _targetFirst = 70.0;
// Queries that match most of the Bible; the slowest case a reader can type.
const _commonQueries = [
  'the',
  'in the',
  'the lord said',
  'of the LORD your God',
  'God',
  'and',
  'jesus wept',
  'love one another',
];

String _opt(List<String> args, String name, String fallback) {
  final i = args.indexOf('--$name');
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

String _pct(int n, int of) => (100 * n / of).toStringAsFixed(1);

class _Case {
  final String label;
  final String query;
  const _Case(this.label, this.query);
}

void main(List<String> args) {
  final path = _opt(args, 'db', '../../assets/berea.sqlite');
  final db = BibleDb(sqlite3.open(path, mode: OpenMode.readOnly));

  final verses = <Verse>[
    for (final b in books)
      for (var c = 1; c <= db.chapterCount(b); c++) ...db.passage(Ref(b, c, null)),
  ];
  stdout.writeln('verses: ${verses.length}');

  final cases = <_Case>[];
  for (var i = 0; i < verses.length; i += _verseSampleStep) {
    final words = searchTokens(verses[i].text);
    if (words.length < _phraseWords) continue;
    final start = (words.length - _phraseWords) ~/ 2;
    cases.add(_Case(verses[i].label, words.sublist(start, start + _phraseWords).join(' ')));
  }
  stdout.writeln('cut-phrase sample: ${cases.length}');

  var oldFirst = 0, oldTen = 0, oldNone = 0, newFirst = 0, newTen = 0, newNone = 0;
  for (final c in cases) {
    final old = db.search(c.query, k: _topTen).map((v) => v.label).toList();
    if (old.isEmpty) oldNone++;
    if (old.isNotEmpty && old.first == c.label) oldFirst++;
    if (old.contains(c.label)) oldTen++;
    final flat = [
      for (final g in db.searchVerses(c.query, perGroup: _topTen)) ...g.verses.map((v) => v.label),
    ].take(_topTen).toList();
    if (flat.isEmpty) newNone++;
    if (flat.isNotEmpty && flat.first == c.label) newFirst++;
    if (flat.contains(c.label)) newTen++;
  }
  final n = cases.length;
  stdout.writeln('old search: first ${_pct(oldFirst, n)}%, top ten ${_pct(oldTen, n)}%, none ${_pct(oldNone, n)}%');
  stdout.writeln('new search: first ${_pct(newFirst, n)}%, top ten ${_pct(newTen, n)}%, none ${_pct(newNone, n)}%');

  final vocabulary = <String>{
    for (final v in verses)
      for (final t in searchTokens(v.text))
        // A lone function word is deliberately not listed, so it is not a vocabulary miss.
        if (t.length >= _minVocabularyLength && !searchStopWords.contains(t)) t,
  }.toList()..sort();
  final step = vocabulary.length ~/ _vocabularySize;
  var misses = 0;
  for (var i = 0; i < vocabulary.length; i += step) {
    if (db.searchVerses(vocabulary[i]).isEmpty) {
      misses++;
      stdout.writeln('no result for: ${vocabulary[i]}');
    }
  }
  stdout.writeln('vocabulary: ${vocabulary.length} distinct words, $misses sampled words with no result');

  final timed = [for (final c in cases.take(_timedQueries)) c.query];
  final millis = <int>[];
  for (final q in timed) {
    final watch = Stopwatch()..start();
    db.searchVerses(q);
    millis.add(watch.elapsedMilliseconds);
  }
  millis.sort();
  stdout.writeln(
    'time per search: p50 ${millis[millis.length ~/ 2]} ms, '
    'p95 ${millis[(millis.length * 95) ~/ 100]} ms over ${millis.length} searches',
  );

  for (final q in _commonQueries) {
    final watch = Stopwatch()..start();
    db.searchVerses(q);
    stdout.writeln('common query "$q": ${watch.elapsedMilliseconds} ms');
  }

  final pass = 100 * newTen / n >= _targetTopTen && 100 * newFirst / n >= _targetFirst && misses == 0;
  stdout.writeln(pass ? 'PASS' : 'FAIL');
  exit(pass ? 0 : 1);
}
