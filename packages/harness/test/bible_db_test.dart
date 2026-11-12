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
    // A word in every printed text has no row at all.
    raw.execute("INSERT INTO words VALUES (43, 1, 4, 1, 'x', 'x', 'g', 'G0001', 'm')");
    raw.execute("INSERT INTO words VALUES (1, 1, 1, 1, 'y', 'y', 'g', 'H0001', 'm')");
    final db = BibleDb(raw)..buildWordIndex();
    final greek = db.wordCountsByText('G0001');
    expect(greek.map((t) => (t.text, t.uses, t.verses)), [
      (greekMainTextName, 3, 3),
      (greekReceivedTextName, 3, 3),
    ]);
    expect(db.wordCountsByText('H0001').single.text, hebrewTextName);
    expect(db.mainTextFor('G0001'), greekMainTextName);
    expect(db.wordCount('G0001').uses, 4, reason: 'the plain count still has every printed row');
    expect(db.wordBooks('G0001').map((b) => b.$2), [3], reason: 'the lists use the headline text');
    expect(db.wordGlosses('G0001').single.$2, 3);
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

  test('an imported translation is put in Bible order and recorded, so its searches skip the join', () {
    final raw = sqlite3.openInMemory();
    createBibleSchema(raw);
    final db = BibleDb(raw);
    final john = bookFor('John')!, gen = bookFor('Genesis')!;
    // Handed over out of order; the rows must still land as one ordered run.
    db.importRows([
      (book: john, chapter: 1, verse: 2, text: 'He was with God in the beginning.'),
      (book: gen, chapter: 1, verse: 1, text: 'In the beginning God created.'),
      (book: john, chapter: 1, verse: 1, text: 'In the beginning was the Word.'),
    ], 'MYV');
    final meta = raw.select("SELECT value FROM meta WHERE key = 'bible_order'").first['value'] as String;
    expect(meta, matches(RegExp(r'^MYV:\d+-\d+$')));
    final labels = db.searchVerses('beginning', translation: 'MYV').expand((g) => g.verses).map((v) => v.label);
    expect(labels.toSet(), {'Genesis 1:1', 'John 1:1', 'John 1:2'});
    final exact = db.searchVerses('beginning', translation: 'MYV').first.verses.map((v) => v.label).toList();
    expect(exact, ['Genesis 1:1', 'John 1:1', 'John 1:2'], reason: 'in Bible order');
    db.importRows([(book: gen, chapter: 1, verse: 1, text: 'Another beginning.')], 'TWO');
    final both = raw.select("SELECT value FROM meta WHERE key = 'bible_order'").first['value'] as String;
    expect(both, contains('MYV:'));
    expect(both, contains('TWO:'), reason: 'a second import is recorded without losing the first');
  });

  test('a cross reference that runs into the next chapter keeps its end and reads as a range', () {
    final raw = sqlite3.openInMemory();
    createBibleSchema(raw);
    final db = BibleDb(raw);
    // Genesis 11:31 points to Genesis 11:32-12:1 and to Genesis 12:2-3; 50:26 to Exodus 1:1-2.
    raw.execute("INSERT INTO xrefs VALUES (1, 11, 31, 1, 11, 32, 1, 9, 1, 12)");
    raw.execute("INSERT INTO xrefs VALUES (1, 11, 31, 1, 12, 2, 3, 4, 1, 12)");
    raw.execute("INSERT INTO xrefs VALUES (1, 50, 26, 2, 1, 1, 2, 3, 2, 1)");
    final across = db.xrefs(RefParser.parse('Genesis 11:31').first);
    expect(across.map((x) => x.label), ['Genesis 11:32-12:1', 'Genesis 12:2-3']);
    expect(across.first.to.verseEnd, 32, reason: 'readers of the target stay in one chapter');
    final book = db.xrefs(RefParser.parse('Genesis 50:26').first).single;
    expect(book.label, 'Exodus 1:1-2');
    final old = sqlite3.openInMemory()
      ..execute('CREATE TABLE xrefs(from_book INTEGER, from_chapter INTEGER, from_verse INTEGER, to_book INTEGER, to_chapter INTEGER, to_verse_start INTEGER, to_verse_end INTEGER, votes INTEGER)')
      ..execute('INSERT INTO xrefs VALUES (1, 1, 1, 43, 1, 1, 3, 5)');
    expect(BibleDb(old).xrefs(RefParser.parse('Genesis 1:1').first).single.label, 'John 1:1-3');
  });

  test("Greek verbs read from STEPBible's table, and a code the table lacks is not guessed", () {
    final raw = sqlite3.openInMemory()
      ..execute('CREATE TABLE greek_morphology(code TEXT PRIMARY KEY, label TEXT) WITHOUT ROWID')
      ..execute("INSERT INTO greek_morphology VALUES ('V-AAI-3S', 'Verb Aorist Active Indicative 3rd Singular')")
      ..execute("INSERT INTO greek_morphology VALUES ('N-NSM', 'Noun Nominative Singular Masculine')");
    final db = BibleDb(raw);
    expect(db.verbParsing('V-AAI-3S'), 'Aorist Active Indicative 3rd Singular');
    expect(db.verbParsing('N-NSM'), isNull, reason: 'only verbs are described');
    expect(db.verbParsing('V-ZZZ'), isNull);
    expect(db.verbParsing(''), isNull);
    expect(BibleDb(sqlite3.openInMemory()).verbParsing('V-AAI-3S'), isNull);
  });

  test('the optional Middle Liddell pack attaches apart from the full lexicon and answers by key', () {
    final dir = Directory.systemTemp.createTempSync('berea_ml');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pack = '${dir.path}/ml.sqlite';
    sqlite3.open(pack)
      ..execute('''
        CREATE TABLE lexicon_ml(key TEXT PRIMARY KEY, base TEXT, definition TEXT);
        INSERT INTO lexicon_ml VALUES ('G5104', 'G5104', 'enclit. Particle, serving to express belief');
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
      ''')
      ..dispose();
    final db = BibleDb(sqlite3.openInMemory());
    expect(db.middleLiddell('G5104'), isNull, reason: 'nothing attached yet');
    expect(db.attachMiddleLiddell('${dir.path}/missing.sqlite'), isFalse);
    expect(db.attachMiddleLiddell(pack), isTrue);
    expect(db.hasMiddleLiddell, isTrue);
    expect(db.hasFullLexicon, isFalse, reason: 'the two packs are separate files');
    expect(db.middleLiddell('G5104'), startsWith('enclit.'));
    expect(db.middleLiddell('G0001'), isNull);
    db.detachMiddleLiddell();
    expect(db.hasMiddleLiddell, isFalse);
    final notAPack = '${dir.path}/other.sqlite';
    sqlite3.open(notAPack)
      ..execute('CREATE TABLE x(a)')
      ..dispose();
    expect(db.attachMiddleLiddell(notAPack), isFalse);
  });

  test('each verse the BSB leaves empty resolves to the footnote that prints it, in the built Bible', () {
    final file = File('../../assets/berea.sqlite');
    if (!file.existsSync()) return;
    final db = BibleDb(sqlite3.open(file.path, mode: OpenMode.readOnly));
    final empty = db.db.select(
      "SELECT book, chapter, verse FROM verses WHERE translation = 'BSB' AND trim(text) = ''",
    );
    // Sixteen on 2026-11-12 (Matthew 17:21 and Acts 8:37 among them); a BSB-only CI database may
    // hold fewer rows, so the count is checked only against a database that has the footnotes.
    final withNotes = db.db.select("SELECT 1 FROM sqlite_master WHERE name = 'footnotes'").isNotEmpty;
    if (!withNotes) return;
    expect(empty, hasLength(16));
    for (final r in empty) {
      final note = db.emptyVerseNote(r['book'] as int, r['chapter'] as int, r['verse'] as int);
      expect(note, isNotNull, reason: '${bookById(r['book'] as int).name} ${r['chapter']}:${r['verse']}');
    }
  });
}
