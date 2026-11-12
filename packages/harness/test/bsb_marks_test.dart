import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _header =
    'Heb Sort\tGreek Sort\tBSB Sort\tVerse\tLanguage\tA\tB\tTranslit\tParsing\tParsing\tStr Heb\t'
    'Str Grk\tVerseId\tHdg\tCrossref\tPar\tSpace\tbegQ\t BSB version \tpnc\tendQ\tfootnotes\tEnd text';

/// One row of the tables file: sort number, verse id, paragraph cell, opening quote, English,
/// punctuation, closing quote, footnote and end text.
String _row(
  int sort,
  String english, {
  String id = '',
  String par = '',
  String beg = '',
  String pnc = '',
  String endQ = '',
  String note = '',
  String end = '',
}) =>
    '0\t0\t$sort\t\tGreek\t\t\t\t\t\t\t\t$id\t\t\t$par\t\t$beg\t $english \t$pnc\t$endQ\t$note\t$end';

VerseRow _verse(int book, int chapter, int verse, String text) =>
    (book: bookFor('Matthew')!, chapter: chapter, verse: verse, text: text);

void main() {
  // Matthew 3:15 and 3:16 in the shape of the tables file: a red span that closes mid-verse, a
  // supplied word in brackets, a footnote, and a placeholder row.
  final tsv = [
    _header,
    _row(
      1,
      'Let [it] be so now',
      id: 'Matthew 3:15',
      par: '<p class=|reg|><span class=|red|>',
      beg: '“',
      pnc: ',',
      endQ: '”',
      end: '</span>',
    ),
    _row(2, '-'),
    _row(3, 'Jesus replied', pnc: '.'),
    _row(4, 'vvv Then John', note: 'Or <i>baptised</i>'),
    _row(5, 'permitted Him', pnc: '.'),
    _row(6, 'So', id: 'Matthew 3:16', par: '<p class=|red|>'),
    _row(7, 'He went'),
    _row(8, 'up', par: '<p class=|reg|>'),
  ].join('\n');

  final verses = [
    _verse(
      40,
      3,
      15,
      '“Let it be so now,” Jesus replied. Then John permitted Him.',
    ),
    _verse(40, 3, 16, 'So He went up'),
  ];

  test(
    'red spans, supplied words and footnotes come out as offsets into the verse text',
    () {
      final r = parseBsbMarks(tsv, verses);
      expect(r.unreconciled, isEmpty);
      final v15 = r.verses.first;
      final text = verses.first.text;
      expect(
        [
          for (final s in v15.spans)
            '${s.kind.name}:${text.substring(s.start, s.end)}',
        ],
        ['red:“Let it be so now,”', 'supplied:it'],
      );
      expect(v15.footnotes, hasLength(1));
      expect(
        text.substring(0, v15.footnotes.single.at).endsWith('John'),
        isTrue,
      );
      expect(v15.footnotes.single.text, 'Or baptised');
    },
  );

  test('a red paragraph runs until the next paragraph begins', () {
    final v16 = parseBsbMarks(tsv, verses).verses.last;
    expect(v16.spans.map((s) => (s.kind, s.start, s.end)), [
      (MarkKind.red, 0, 10),
    ]);
  });

  test(
    'a verse whose words differ between the two files gets no marks and is reported',
    () {
      final r = parseBsbMarks(tsv, [
        _verse(
          40,
          3,
          15,
          '“Let it be so now,” Jesus replied. Then Paul permitted Him.',
        ),
      ]);
      expect(r.verses, isEmpty);
      expect(r.unreconciled.single.label, 'Matthew 3:15');
    },
  );

  test('marks and footnotes are stored and read back per chapter', () {
    final raw = sqlite3.openInMemory();
    final db = BibleDb(raw);
    db.importMarks(parseBsbMarks(tsv, verses), 'BSB');
    final marks = db.marksForChapter(40, 3);
    expect(marks.keys, [15, 16]);
    expect(marks[15]!.spans, hasLength(2));
    expect(marks[15]!.footnotes.single.text, 'Or baptised');
    expect(db.marksForChapter(40, 4), isEmpty);
    db.importMarks(parseBsbMarks(tsv, [verses.last]), 'BSB');
    expect(db.marksForChapter(40, 3).keys, [
      16,
    ], reason: 'a re-import replaces what was there');
  });

  test('the poetry paragraph classes that end in red are red too', () {
    final poetry = [
      _header,
      _row(
        1,
        'Blessed are the poor',
        id: 'Matthew 3:1',
        par: '<p class=|indent1stlinered|>',
        beg: '“',
      ),
      _row(2, 'for theirs', id: 'Matthew 3:2', par: '<p class=|indent2|>'),
    ].join('\n');
    final r = parseBsbMarks(poetry, [
      _verse(40, 3, 1, '“Blessed are the poor'),
      _verse(40, 3, 2, 'for theirs'),
    ]);
    expect(
      r.verses.first.spans.where((s) => s.kind == MarkKind.red),
      hasLength(1),
    );
    expect(r.verses.last.spans, isEmpty, reason: 'indent2 is not a red class');
  });

  test('a database built before marks existed answers with none', () {
    expect(BibleDb(sqlite3.openInMemory()).marksForChapter(40, 3), isEmpty);
  });
}
