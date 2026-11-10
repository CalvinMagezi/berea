import 'package:berea/export.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('notes export to Markdown, and text a person did not write says so', () {
    final raw = sqlite3.openInMemory()
      ..execute('''
        CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT);
        INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', 43, 3, 16, 'For God so loved the world.');
      ''');
    final db = BibleDb(raw);
    final store = StudyStore(sqlite3.openInMemory());
    final ref = RefParser.parse('John 3:16').first;
    store.addNote(ref, 'Loved first.');
    final verses = StudyStore.notesOnVersesNotebook(store.db);
    store.addNotebookNote(verses, 'agape', kind: 'word', title: 'agape', verse: ref);

    final all = allNotesMarkdown(store, db, 'BSB');
    expect(all, contains('### John 3:16'));
    expect(all, contains('> For God so loved the world.'));
    expect(all, contains('Loved first.'));
    expect(all, contains('_Shortened by an earlier version of Berea from a lexicon entry.'));
  });
}
