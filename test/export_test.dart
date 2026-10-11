import 'package:berea/export.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('study and notes export to Markdown with cited passages', () {
    final raw = sqlite3.openInMemory()
      ..execute('''
        CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT);
        INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', 43, 3, 16, 'For God so loved the world.');
      ''');
    final db = BibleDb(raw);
    final store = StudyStore(sqlite3.openInMemory());
    final ref = RefParser.parse('John 3:16').first;
    store.addNote(ref, 'Loved first.');
    final c = store.createConversation('What does John 3:16 teach?');
    store.addMessage(c, 'user', 'What does John 3:16 teach?', const []);
    store.addMessage(c, 'assistant', 'It teaches love.', [ref]);

    final study = studyMarkdown(store, db, c, 'BSB');
    expect(study, startsWith('# What does John 3:16 teach?'));
    expect(study, contains('> **John 3:16** For God so loved the world.'));

    final all = allNotesMarkdown(store, db, 'BSB');
    expect(all, contains('### John 3:16'));
    expect(all, contains('Loved first.'));
    expect(all, contains('## What does John 3:16 teach?'));
  });
}
