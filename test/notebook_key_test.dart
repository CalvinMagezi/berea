import 'package:berea/notebook_store.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

Ref _ref(String s) => RefParser.parse(s).first;

void main() {
  test('renaming notes on verses keeps verse notes going to it', () {
    final store = StudyStore(sqlite3.openInMemory());
    final books = NotebookStore(store.db);
    final first = store.addNote(_ref('John 3:16'), 'Loved first.');
    final home = store.note(first)!.notebookId!;

    books.renameNotebook(home, 'Maelezo ya mistari');
    final second = store.addNote(_ref('Romans 8:28'), 'All things.');

    expect(store.note(second)!.notebookId, home);
    expect(books.notebooks(), hasLength(1));
    expect(StudyStore.notesOnVersesId(store.db), home);
  });

  test('deleting notes on verses moves its notes to a new one that takes the key', () {
    final store = StudyStore(sqlite3.openInMemory());
    final books = NotebookStore(store.db);
    final other = books.createNotebook('Sermons');
    final note = store.addNotebookNote(other, 'Sunday.');
    final home = store.note(store.addNote(_ref('John 1:1'), 'Word.'))!.notebookId!;

    books.deleteNotebook(home);
    books.deleteNotebook(other);

    final now = StudyStore.notesOnVersesId(store.db)!;
    expect(now, isNot(home));
    expect(store.note(note)!.notebookId, now);
    expect(store.notebookNotes(now), hasLength(2));
  });

  test('a backup from before keys restores without a second notes on verses', () {
    final source = StudyStore(sqlite3.openInMemory());
    source.addNote(_ref('John 3:16'), 'Loved first.');
    final tables = source.exportTables();
    for (final row in tables['notebooks']!) {
      row.remove('system_key');
    }
    for (final row in tables['notes']!) {
      row.remove('kind');
    }

    final target = StudyStore(sqlite3.openInMemory());
    target.importTables(tables);
    target.addNote(_ref('Romans 8:28'), 'All things.');

    expect(NotebookStore(target.db).notebooks(), hasLength(1));
    expect(target.notes(), hasLength(2));
  });

  test('a word kept before notes had a kind comes back as a kept word', () {
    final source = StudyStore(sqlite3.openInMemory());
    final nb = NotebookStore(source.db).createNotebook('Words');
    source.addNotebookNote(nb, "to love\nStrong's G0025 · agapaō · Greek", title: 'ἀγαπάω');
    source.addNotebookNote(nb, 'A plain note.');
    final tables = source.exportTables();
    for (final row in tables['notes']!) {
      row.remove('kind');
    }

    final target = StudyStore(sqlite3.openInMemory());
    target.importTables(tables);

    final kinds = {for (final n in target.notebookNotes(nb)) n.title: n.isKeptWord};
    expect(kinds, {'ἀγαπάω': true, '': false});
  });

  test('a note saved as a kept word says so', () {
    final store = StudyStore(sqlite3.openInMemory());
    final nb = NotebookStore(store.db).createNotebook('Words');
    final id = store.addNotebookNote(nb, 'to love', title: 'ἀγαπάω', kind: keptWordKind);
    expect(store.note(id)!.isKeptWord, isTrue);
  });

  test('a plain note that mentions a Strong number stays a note', () {
    final source = StudyStore(sqlite3.openInMemory());
    final nb = NotebookStore(source.db).createNotebook('Sermons');
    source.addNotebookNote(nb, "Pastor said:\nStrong's G25 is the word for love here.");
    source.addNotebookNote(nb, "Strong's H7965 · shalom", title: 'kept by an older build');
    final legacy = source.exportTables();
    for (final row in legacy['notes']!) {
      row.remove('kind');
    }

    final target = StudyStore(sqlite3.openInMemory());
    target.importTables(legacy);

    final words = target.notebookNotes(nb).where((n) => n.isKeptWord).map((n) => n.title);
    expect(words, ['kept by an older build']);
  });

  test('restoring a backup that has kinds keeps them as they are', () {
    final source = StudyStore(sqlite3.openInMemory());
    final nb = NotebookStore(source.db).createNotebook('Words');
    source.addNotebookNote(nb, "to love\nStrong's G0025 · agapaō · Greek", title: 'plain');

    final target = StudyStore(sqlite3.openInMemory());
    target.importTables(source.exportTables());

    expect(target.notebookNotes(nb).single.isKeptWord, isFalse);
  });
}
