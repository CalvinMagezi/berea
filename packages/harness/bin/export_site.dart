// Writes the data the public site's live reference check reads, and a parity fixture that
// site/check/selftest.mjs uses to prove the JavaScript port agrees with this harness.
// Usage: dart run bin/export_site.dart [--db ../../assets/berea.sqlite] [--out ../../site/data]
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';

const defaultDb = '../../assets/berea.sqlite';
const defaultOut = '../../site/data';

/// Inputs the port must handle exactly as the Dart check does: real and invented books,
/// missing chapters and verses, prose that looks like a citation, and quotations.
const fixtureInputs = [
  '2 Hezekiah 4:1',
  'Psalm 151',
  'Psalm 151:1',
  'Jn 3.16',
  'II Timothy 3:16',
  '1 Cor 13',
  'Philippians 4:6-7',
  'John 3:99',
  'See Jasher 3:2',
  'Monday 3:30',
  'Paul 3:16',
  'First Hezekiah 2:4',
  '“God so loved the world that He gave His only Son” (John 3:16)',
  '“For God so loved the world that He gave His one and only Son” (John 3:16)',
  '“Be anxious for nothing, but in everything, by prayer and petition” (Philippians 4:6)',
  '“God helps those who help themselves, as the proverb says” (Proverbs 3:5)',
  'Song of Songs 2:4 and Rev 21:4',
  'Jasher 3:2',
  'Romans 8:28-29',
  'romans 8:28',
  'Gen 1:1',
  'Hezekiah 4:1',
  'Matthew 17:21',
  '3 John 1:15',
  'Obadiah 1',
  'Psalm 23',
  '“The LORD is my shepherd; I shall not want” (Psalm 23:1)',
  '“The Lord is my shepherd, I lack nothing at all in this life” (Psalm 23:1)',
  'Read Second Opinions 4:2 tonight',
];

String opt(List<String> args, String name, String fallback) {
  final i = args.indexOf('--$name');
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

void writeJson(String path, Object data, {bool pretty = false}) {
  final text = pretty ? const JsonEncoder.withIndent(' ').convert(data) : jsonEncode(data);
  File(path).writeAsStringSync('$text\n');
}

void main(List<String> args) {
  final db = BibleDb.open(opt(args, 'db', defaultDb));
  final out = opt(args, 'out', defaultOut);
  Directory('$out/bible').createSync(recursive: true);

  writeJson('$out/books.json', [
    for (final b in books) {'id': b.id, 'name': b.name, 'step': b.step, 'aliases': b.aliases},
  ]);

  // Per book: chapters as arrays of verse text (null for a verse the translation omits), and an
  // index of each chapter's last verse plus any gaps, so existence checks need no download.
  final index = <String, Object>{};
  for (final b in books) {
    final rows = db.db.select(
      'SELECT chapter, verse, text FROM verses WHERE translation = ? AND book = ? ORDER BY chapter, verse',
      [defaultTranslation, b.id],
    );
    final chapters = <int, Map<int, String>>{};
    for (final r in rows) {
      (chapters[r['chapter'] as int] ??= {})[r['verse'] as int] = r['text'] as String;
    }
    final lastChapter = chapters.keys.reduce((a, c) => a > c ? a : c);
    final text = <List<String?>>[];
    final idx = <List<Object>>[];
    for (var c = 1; c <= lastChapter; c++) {
      final verses = chapters[c] ?? const <int, String>{};
      final top = verses.isEmpty ? 0 : verses.keys.reduce((a, v) => a > v ? a : v);
      text.add([for (var v = 1; v <= top; v++) verses[v]]);
      idx.add([top, [for (var v = 1; v <= top; v++) if (!verses.containsKey(v)) v]]);
    }
    writeJson('$out/bible/${b.id}.json', text);
    index['${b.id}'] = idx;
  }
  writeJson('$out/index.json', index);

  final fixture = <Map<String, Object?>>[];
  for (final input in fixtureInputs) {
    final refs = RefParser.parse(input);
    final ctx = StudyContext(
      refs: refs,
      passages: [for (final r in refs) ...db.passage(r)],
      words: const [],
      lexicon: const {},
      xrefVerses: const [],
      searchHits: const [],
    );
    final r = CitationGuard(db).apply(input, ctx);
    fixture.add({
      'input': input,
      'text': r.text,
      'verified': [for (final x in r.verified) x.label],
      'unverified': [for (final x in r.unverified) x.label],
      'unknownBooks': r.unknownBooks,
      'badQuotes': r.unverifiedQuotes,
      'corrected': r.correctedQuotes,
    });
  }
  writeJson('$out/fixture.json', fixture, pretty: true);
  stdout.writeln('site data written to $out: ${books.length} books, ${fixture.length} fixture cases');
}
