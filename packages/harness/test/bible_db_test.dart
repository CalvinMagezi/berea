import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('the optional lexicon pack attaches and answers by Strong number', () {
    final dir = Directory.systemTemp.createTempSync('berea_lsj');
    final pack = '${dir.path}/lsj.sqlite';
    sqlite3.open(pack)
      ..execute('''
        CREATE TABLE lexicon_full(key TEXT PRIMARY KEY, base TEXT, definition TEXT);
        INSERT INTO lexicon_full VALUES ('G0025', 'G0025', 'to love, full entry');
      ''')
      ..dispose();
    final db = BibleDb(sqlite3.openInMemory());
    expect(db.fullLexicon('G0025'), isNull);
    expect(db.attachFullLexicon('${dir.path}/missing.sqlite'), isFalse);
    expect(db.attachFullLexicon(pack), isTrue);
    expect(db.fullLexicon('G0025'), 'to love, full entry');
    expect(db.fullLexicon('G9999'), isNull);
    dir.deleteSync(recursive: true);
  });

  test('imports a CSV translation and makes it searchable', () {
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT);
      CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id');
    ''');
    final db = BibleDb(raw);
    const csv =
        'Book,Chapter,Verse,Text\n'
        'John,3,16,"For God so loved the world, that he gave his only Son."\n'
        'I John,4,8,God is love.\n';
    expect(db.importCsv(csv, 'TEST'), 2);
    expect(db.translations(), ['TEST']);
    expect(
      db.passage(RefParser.parse('1 John 4:8').first, translation: 'TEST').first.text,
      'God is love.',
    );
    expect(db.search('only Son', translation: 'TEST', k: 1).first.label, 'John 3:16');
    expect(db.chapterCount(bookById(43), translation: 'TEST'), 3);
    expect(
      () => db.importCsv('Book,Chapter,Verse,Text\nNarnia,1,1,x\n', 'BAD'),
      throwsFormatException,
    );
    expect(db.translations(), ['TEST']);
    expect(
      () => db.importCsv('Book,Chapter,Verse,Text\nJohn,1,1,x\n', '../x'),
      throwsFormatException,
    );
    db.importCsv('Book,Chapter,Verse,Text\nJohn,1,1,a\nJohn,1,1,b\n', 'DUP');
    expect(db.passage(RefParser.parse('John 1:1').first, translation: 'DUP').length, 1);
    expect(db.exists(RefParser.parse('John 1:1').first, translation: 'DUP'), isTrue);
    const tricky = 'He said, "go", then left.';
    expect(
      parseCsv(
        toCsv([
          ['a', tricky],
        ]),
      ).single,
      ['a', tricky],
    );
  });

  test('the BSB renderings count each English phrase per Strong number, once per print', () {
    final db = BibleDb(sqlite3.openInMemory());
    final john = RefParser.parse('John 1:1').first;
    final jude = RefParser.parse('Jude 1:1').first;
    db.importRenderings({
      john: const [
        BsbRow('the Spirit', 'H7307'),
        BsbRow('the spirit', 'H7307'),
        BsbRow('[a] spirit', 'H7307'),
        BsbRow('. . .', 'H7307'),
        BsbRow('', 'H7307'),
        BsbRow('wind', 'H7307'),
        BsbRow('with', ''),
      ],
      jude: const [BsbRow('wind', 'H7307')],
    });
    final r = db.bsbRenderings('H7307');
    expect(r.map((e) => (e.english, e.count)), [('', 2), ('the Spirit', 2), ('wind', 2), ('a spirit', 1)]);
    expect(db.bsbRenderings('H7307G'), r, reason: 'an entry letter is not part of the number');
    expect(db.bsbRenderings('G0001'), isEmpty);
    expect(BibleDb(sqlite3.openInMemory()).bsbRenderings('H7307'), isEmpty);
  });

  test('word counts name the printed text, and Greek gives the Nestlé-Aland and the Received Text', () {
    final raw = sqlite3.openInMemory()
      ..execute('''
        CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT,
          translit TEXT, gloss TEXT, strongs TEXT, morph TEXT, PRIMARY KEY(book, chapter, verse, pos));
        CREATE TABLE word_editions(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER,
          editions TEXT, PRIMARY KEY(book, chapter, verse, pos));
        CREATE TABLE lexicon(key TEXT, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT,
          definition TEXT);
      ''');
    void word(int verse, String strongs, String editions) {
      raw.execute("INSERT INTO words VALUES (43, 1, ?, 1, 'x', 'x', 'g', ?, 'm')", [verse, strongs]);
      raw.execute('INSERT INTO word_editions VALUES (43, 1, ?, 1, ?)', [verse, editions]);
    }

    word(1, 'G0001', 'NA28+NA27+TR+Byz');
    word(2, 'G0001', 'TR+Byz');
    word(3, 'G0001', 'NA28+Tyn');
    raw.execute("INSERT INTO words VALUES (1, 1, 1, 1, 'y', 'y', 'g', 'H0001', 'm')");
    final db = BibleDb(raw)..buildWordIndex();
    final greek = db.wordCountsByText('G0001');
    expect(greek.map((t) => (t.text, t.uses, t.verses)), [
      (greekMainTextName, 2, 2),
      (greekReceivedTextName, 2, 2),
    ]);
    expect(db.wordCountsByText('H0001').single.text, hebrewTextName);
    expect(db.mainTextFor('G0001'), greekMainTextName);
    expect(db.wordCount('G0001').uses, 3, reason: 'the plain count still has every printed row');
  });

  test("Hebrew and Aramaic parsing is STEPBible's own label for the verb part of the code", () {
    final raw = sqlite3.openInMemory()
      ..execute('CREATE TABLE hebrew_morphology(code TEXT PRIMARY KEY, label TEXT) WITHOUT ROWID')
      ..execute("INSERT INTO hebrew_morphology VALUES ('HVhaa', 'Verb : Hiphil (Causative/declarative, Active) Infinitive Absolute')")
      ..execute("INSERT INTO hebrew_morphology VALUES ('AVqp3ms', 'Verb : Peal (Simple, Active) Perfect (Past/present Indicative) Third Singular Masculine')")
      ..execute("INSERT INTO hebrew_morphology VALUES ('HVqrmsc', 'Verb : Qal (Simple, Active) Participle Active Masculine Singular Construct')");
    final db = BibleDb(raw);
    expect(db.hebrewParsing('HVhaa'), 'Hiphil (Causative/declarative, Active) Infinitive Absolute');
    expect(db.hebrewParsing('AC/Vqp3ms'), startsWith('Peal'), reason: 'Aramaic keeps its own stem names');
    expect(db.hebrewParsing('HVqrmsc/Sp1bs'), startsWith('Qal'));
    expect(db.hebrewParsing('HNcmsa'), isNull);
    expect(db.hebrewParsing('HVzz'), isNull, reason: 'a code the table lacks is not guessed');
    expect(db.hebrewParsing('V-AAI-3S'), isNull);
    expect(BibleDb(sqlite3.openInMemory()).hebrewParsing('HVhaa'), isNull);
  });
}
