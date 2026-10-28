// Checks every BSB word's Strong's number against the BSB translation tables and against what the
// word means, and writes the counts and the worst verses as a Markdown report.
// Usage: dart run bin/word_alignment_report.dart [--db ../../assets/berea.sqlite]
//   [--tables .cache/bsb_tables.tsv] [--out ../../build/handoff/word-alignment-report.md]
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';

/// Verses and words listed under each heading of the report.
const _listed = 15;

void main(List<String> args) {
  String opt(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final db = BibleDb.open(opt('db', '../../assets/berea.sqlite'));
  final tables = parseBsbTables(File(opt('tables', '.cache/bsb_tables.tsv')).readAsStringSync());
  final out = File(opt('out', '../../build/handoff/word-alignment-report.md'));

  var verses = 0, words = 0, coded = 0, wrongRow = 0, driftVerses = 0, tableExtra = 0;
  var readerExtra = 0, noTag = 0;
  final kinds = {for (final k in PressKind.values) k: 0};
  final names = <String, Map<PressKind, int>>{};
  final entries = <String, LexEntry?>{};
  final isNames = <String, bool>{};
  final worst = <(int, String)>[];
  final wrong = <String>[];
  final swapped = <String>[];
  String norm(String w) => w.toLowerCase().replaceAll('’', "'");

  for (final r in db.db.select(
    "SELECT book, chapter, verse, text FROM verses WHERE translation = 'BSB'",
  )) {
    final ref = Ref(bookById(r['book'] as int), r['chapter'] as int, r['verse'] as int);
    final text = r['text'] as String;
    final placed = db.bsbWords(ref);
    final rows = tables[ref];
    if (placed == null || rows == null) continue;
    verses++;
    final matches = verseWordPattern.allMatches(text).toList();
    final reader = [for (final m in matches) norm(m[0]!)];
    final tableWords = [
      for (final row in rows)
        for (final m in verseWordPattern.allMatches(row.english)) norm(m[0]!),
    ];
    final counts = <String, int>{};
    for (final w in tableWords) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
    var extra = 0;
    for (final w in reader) {
      final left = counts[w] ?? 0;
      if (left > 0) {
        counts[w] = left - 1;
      } else {
        extra++;
      }
    }
    final missing = counts.values.fold(0, (a, b) => a + b);
    readerExtra += extra;
    tableExtra += missing;
    if (extra + missing > 0) {
      driftVerses++;
      worst.add((
        extra + missing,
        '${ref.label}: reader has $extra words the tables lack, tables have $missing the reader lacks',
      ));
    }
    if (placed.length != reader.length) {
      wrong.add('${ref.label}: stored ${placed.length} words, reader has ${reader.length}');
    }
    final tags = db.words(ref);
    for (var i = 0; i < reader.length && i < placed.length; i++) {
      words++;
      final p = placed[i];
      if (p.code.isNotEmpty) {
        coded++;
        // The words stored as one phrase must all come from a single row of that number.
        final span = reader.sublist(p.rowStart, p.rowEnd);
        final held = rows.any((row) {
          if (row.code != p.code) return false;
          final have = <String, int>{};
          for (final m in verseWordPattern.allMatches(row.english)) {
            have.update(norm(m[0]!), (n) => n + 1, ifAbsent: () => 1);
          }
          for (final w in span) {
            final left = have[w] ?? 0;
            if (left == 0) return false;
            have[w] = left - 1;
          }
          return true;
        });
        if (!held) {
          wrongRow++;
          if (wrong.length < _listed) {
            wrong.add(
              '${ref.label} "${matches[i][0]}" has ${p.code}: no table row holds its phrase',
            );
          }
        }
      }
      final press = resolvePress(
        english: matches[i][0]!,
        translation: defaultTranslation,
        tags: tags,
        lexicon: (c) => entries.putIfAbsent(c, () => db.lexicon(c)),
        isName: (w) => isNames.putIfAbsent(w, () => db.isName(w)),
        bsb: placed,
        occurrence: 0,
        wordIndex: i,
      );
      kinds[press.kind] = kinds[press.kind]! + 1;
      if (press.kind == PressKind.exact && press.tag == null) noTag++;
      final w = matches[i][0]!;
      if (const {'Jesus', 'Christ', 'God', 'LORD', 'Spirit'}.contains(w)) {
        final byKind = names.putIfAbsent(w, () => {for (final k in PressKind.values) k: 0});
        byKind[press.kind] = byKind[press.kind]! + 1;
      }
      if (p.code.isNotEmpty && press.kind != PressKind.exact && swapped.length < _listed) {
        swapped.add('${ref.label} "$w" is ${p.code} in the tables, opens ${press.kind.name}');
      }
    }
  }

  worst.sort((a, b) => b.$1.compareTo(a.$1));
  final b = StringBuffer()
    ..writeln('# BSB word alignment report')
    ..writeln()
    ..writeln(
      'Database built ${db.db.select("SELECT value FROM meta WHERE key = 'built'").firstOrNull?['value'] ?? 'unknown'}. $verses verses, $words words.',
    )
    ..writeln()
    ..writeln('## Row integrity (target zero)')
    ..writeln()
    ..writeln(
      '- Words whose stored phrase no single table row of the same number contains: **$wrongRow** of '
      '$coded coded words. This checks the stored data against the tables; the golden set in '
      'test/word_golden_test.dart checks the alignment itself.',
    )
    ..writeln(
      '- Verses stored with a different word count from the reader\'s text: ${wrong.where((w) => w.contains('stored')).length}.',
    );
  for (final w in wrong.take(_listed)) {
    b.writeln('  - $w');
  }
  b
    ..writeln()
    ..writeln('## Edition drift between the reader text and the tables')
    ..writeln()
    ..writeln('- Verses where the two differ: $driftVerses of $verses.')
    ..writeln(
      '- Reader words with no table word: $readerExtra. Table words with no reader word: $tableExtra.',
    )
    ..writeln()
    ..writeln('Worst verses:');
  for (final w in worst.take(_listed)) {
    b.writeln('- ${w.$2}');
  }
  b
    ..writeln()
    ..writeln('## What a press opens')
    ..writeln()
    ..writeln('Every word of the BSB, first occurrence rule off, resolved as the app resolves it.')
    ..writeln();
  for (final k in PressKind.values) {
    b.writeln('- ${k.name}: ${kinds[k]}');
  }
  b
    ..writeln('- exact with no matching tag in the verse (opens by number only): $noTag')
    ..writeln()
    ..writeln('Names the BSB puts on a pronoun or verb are not opened as that word. Examples:');
  for (final s in swapped) {
    b.writeln('- $s');
  }
  b
    ..writeln()
    ..writeln('## Names and titles')
    ..writeln()
    ..writeln('| Word | exact | byMeaning | supplied | unknown |')
    ..writeln('|---|---|---|---|---|');
  for (final e in names.entries) {
    final k = e.value;
    b.writeln(
      '| ${e.key} | ${k[PressKind.exact]} | ${k[PressKind.byMeaning]} | ${k[PressKind.supplied]} | ${k[PressKind.unknown]} |',
    );
  }
  out.createSync(recursive: true);
  out.writeAsStringSync(b.toString());
  stdout.writeln(b);
}
