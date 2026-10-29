import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

// Shaped like ebible.org's engbsb USFM: a division and its range before the first chapter,
// parallel passages under a heading, a superscription, an acrostic letter and a footnote.
const _psalms = r'''
\id PSA - Berean Standard Bible
\mt1 Psalms
\ms1 BOOK I
\mr Psalms 1—41
\c 1
\s1 The Two Paths
\r (Matthew 5:3–12; Luke 6:20–23)
\q1
\v 1 Blessed is the man
\v 2 But his delight
\c 3
\s1 Deliver Me, O LORD!
\r (2 Samuel 15:13–29)
\d A Psalm of David, when he fled from his son Absalom.
\q1
\v 1 O LORD, how my foes have increased!
\c 119
\s1 Your Word Is a Lamp to My Feet
\qa ALEPH
\q1
\v 1 Blessed \f + \fr 119:1 \ft This psalm is an acrostic.\f* are those
\s2 A smaller step
\v 2 Blessed are those who keep
''';

void main() {
  test('USFM headings anchor to the verse after them, in printed order', () {
    final rows = parseUsfmHeadings(_psalms);
    String show(HeadingRow r) => '${r.chapter}:${r.verse} ${r.kind} ${r.text} | ${r.refs}';
    expect(rows.map(show), [
      '1:1 ms BOOK I | Psalms 1—41',
      '1:1 s1 The Two Paths | (Matthew 5:3–12; Luke 6:20–23)',
      '3:1 s1 Deliver Me, O LORD! | (2 Samuel 15:13–29)',
      '119:1 s1 Your Word Is a Lamp to My Feet | ',
      '119:1 qa ALEPH | ',
      '119:2 s2 A smaller step | ',
    ]);
    expect(rows.every((r) => r.book.id == 19), isTrue);
  });

  test('a superscription is never a heading', () {
    expect(parseUsfmHeadings(_psalms).where((r) => r.text.contains('Psalm of David')), isEmpty);
  });

  test('books outside the 66 give no headings', () {
    expect(parseUsfmHeadings('\\id FRT\n\\s1 Preface\n'), isEmpty);
  });

  test('headings import, read back per chapter and report strays', () {
    final db = BibleDb(sqlite3.openInMemory())
      ..db.execute(
        'CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, '
        'chapter INTEGER, verse INTEGER, text TEXT)',
      );
    final psalms = bookById(19);
    expect(db.headings(psalms, 1), isEmpty, reason: 'no table yet');
    for (final (c, v) in [(1, 1), (1, 2), (3, 1), (119, 1)]) {
      db.db.execute(
        "INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', 19, ?, ?, '')",
        [c, v],
      );
    }
    expect(db.importHeadings(parseUsfmHeadings(_psalms), 'BSB'), 1, reason: '119:2 is missing');
    expect(db.headings(psalms, 1).map((h) => h.kind), ['ms', 's1']);
    expect(db.headings(psalms, 119).map((h) => h.text), [
      'Your Word Is a Lamp to My Feet',
      'ALEPH',
      'A smaller step',
    ]);
    expect(db.headings(psalms, 1, translation: 'KJV'), isEmpty);
    expect(
      db.importHeadings(parseUsfmHeadings(_psalms), 'BSB'),
      1,
      reason: 'replaced, not doubled',
    );
    expect(db.headings(psalms, 3), hasLength(1));
  });

  test('a heading covers verses up to the next heading of its rank or broader', () {
    const hs = [
      Heading(1, 's1', 'A', ''),
      Heading(1, 'qa', 'ALEPH', ''),
      Heading(5, 's2', 'B', ''),
      Heading(7, 'qa', 'BETH', ''),
      Heading(9, 's1', 'C', ''),
    ];
    expect(sectionSpan(hs, hs[0], 20), (start: 1, end: 8));
    expect(sectionSpan(hs, hs[1], 20), (start: 1, end: 4));
    expect(sectionSpan(hs, hs[2], 20), (start: 5, end: 8));
    expect(sectionSpan(hs, hs[3], 20), (start: 7, end: 8));
    expect(sectionSpan(hs, hs[4], 20), (start: 9, end: 20));
  });

  test('a chapter is read whole, past the prompt cap of passage', () {
    final db = BibleDb(sqlite3.openInMemory())
      ..db.execute(
        'CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, '
        'chapter INTEGER, verse INTEGER, text TEXT)',
      );
    for (var v = 1; v <= 176; v++) {
      db.db.execute(
        "INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', 19, 119, ?, '')",
        [v],
      );
    }
    final psalms = bookById(19);
    expect(db.chapter(psalms, 119).length, 176);
    expect(db.passage(Ref(psalms, 119)).length, maxPassageVerses);
  });
}
