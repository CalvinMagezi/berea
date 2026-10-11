import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
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
  });
}
