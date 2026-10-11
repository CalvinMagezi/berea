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
}
