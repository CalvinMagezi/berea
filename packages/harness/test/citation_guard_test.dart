import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

BibleDb memoryDb() {
  final db = sqlite3.openInMemory();
  db.execute('''
    CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT);
    INSERT INTO verses(translation, book, chapter, verse, text) VALUES
      ('BSB', 43, 3, 16, 'For God so loved the world that He gave His one and only Son, that everyone who believes in Him shall not perish but have eternal life.'),
      ('BSB', 43, 3, 17, 'For God did not send His Son into the world to condemn the world, but to save the world through Him.');
  ''');
  return BibleDb(db);
}

void main() {
  final db = memoryDb();
  final ctx = StudyContext(
    refs: RefParser.parse('John 3:16'),
    passages: db.passage(RefParser.parse('John 3:16').first),
    words: const [],
    lexicon: const {},
    xrefVerses: const [],
    searchHits: const [],
  );

  test('flags invented references and unseen quotes, keeps verified ones', () {
    const output =
        'John 3:16 says "God so loved the world that He gave His one and only Son" '
        'and John 3:99 adds "the Lord helps those who help themselves, forever".';
    final r = CitationGuard(db).apply(output, ctx);
    expect(r.verified.map((e) => e.label), ['John 3:16']);
    expect(r.unverified.map((e) => e.label), ['John 3:99']);
    expect(r.text, contains('[unverified: John 3:99]'));
    expect(r.unverifiedQuotes.length, 1);
    expect(r.text, contains('help themselves, forever" [unverified quote]'));
    expect(r.text, isNot(contains('only Son" [unverified quote]')));
  });

  test('a short quote does not open a bogus long one', () {
    const output =
        'The word means "to create" (H1254A). Scope: "of heaven and earth" and more words here.';
    final r = CitationGuard(db).apply(output, ctx);
    expect(r.unverifiedQuotes, isEmpty);
    expect(r.text, output);
  });

  test('flags citations of books that do not exist without touching prose', () {
    const output =
        'Compare 2 Hezekiah 4:1 and Jasher 3:2 with John 3:16. '
        'In John 3:16 we read this. Verse 3:16 and At 3:30 are not citations. '
        'See 1 John 4:8 and Song of Solomon 2:1.';
    final r = CitationGuard(db).apply(output, ctx);
    expect(r.unknownBooks, ['2 Hezekiah 4:1', 'Jasher 3:2']);
    expect(r.inventedCount, 2 + r.unverified.length);
    expect(r.text, contains('[unverified: 2 Hezekiah 4:1]'));
    expect(r.text, contains('In John 3:16 we read'));
    expect(r.text, contains('Verse 3:16 and At 3:30'));
    expect(r.text, contains('Song of Solomon 2:1'));
  });

  test('a range split into single verses still overlaps', () {
    final range = RefParser.parse('Philippians 4:6-7').first;
    expect(range.overlaps(RefParser.parse('Philippians 4:7').first), isTrue);
    expect(range.overlaps(RefParser.parse('Philippians 4:8').first), isFalse);
  });
}
