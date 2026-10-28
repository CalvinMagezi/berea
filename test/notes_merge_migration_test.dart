import 'dart:convert';
import 'dart:io';

import 'package:berea/backup.dart';
import 'package:berea/export.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// study.sqlite as 0.6.0 left it: the 0.3.0 tables, then migrations 0 and 1.
const _v030Tables = '''
  CREATE TABLE notes(
    id INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER, verse_start INTEGER, verse_end INTEGER,
    text TEXT, created INTEGER, updated INTEGER);
  CREATE INDEX notes_ref ON notes(book, chapter);
  CREATE TABLE highlights(book INTEGER, chapter INTEGER, verse INTEGER,
    PRIMARY KEY(book, chapter, verse)) WITHOUT ROWID;
  CREATE TABLE conversations(id INTEGER PRIMARY KEY, title TEXT, created INTEGER, updated INTEGER);
  CREATE TABLE messages(id INTEGER PRIMARY KEY, conversation_id INTEGER, role TEXT,
    text TEXT, refs TEXT, created INTEGER);
  CREATE INDEX messages_conv ON messages(conversation_id);
  CREATE TABLE plan_progress(plan_id TEXT, day INTEGER, done_at INTEGER,
    PRIMARY KEY(plan_id, day)) WITHOUT ROWID;
  CREATE TABLE study_pages(id INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER,
    verse_start INTEGER, verse_end INTEGER, observation TEXT, interpretation TEXT,
    application TEXT, created INTEGER, updated INTEGER);
''';

const _citation =
    '[{"tag":"1","source":2,"title":"Note on John 3:16","kind":"note","ordinal":0,"page":null,"ref":null}]';

/// Realistic rows across every user table. Note 3 was edited after it was copied into a
/// notebook, so that copy matches no note.
void _fill(Database db) {
  db.execute('''
    INSERT INTO notes VALUES (1, 43, 3, 16, 16, 'Loved first.', 10, 10);
    INSERT INTO notes VALUES (2, 45, 8, 28, 28, 'All things.', 11, 11);
    INSERT INTO notes VALUES (3, 1, 1, 1, 1, 'Edited later.', 12, 30);
    INSERT INTO highlights VALUES (43, 3, 16);
    INSERT INTO plan_progress VALUES ('nt-90', 1, 13);
    INSERT INTO study_pages VALUES (1, 19, 23, 1, 1, 'O1', 'I1', 'A1', 14, 14);
    INSERT INTO study_pages VALUES (2, 45, 8, 28, 30, 'O2', 'I2', 'A2', 15, 15);
    INSERT INTO study_pages VALUES (3, 1, 1, 1, 1, 'O3', 'I3', 'A3', 16, 16);
    INSERT INTO conversations VALUES (1, 'What is grace?', 17, 18);
    INSERT INTO messages VALUES (1, 1, 'user', 'What is grace?', '[]', 17);
    INSERT INTO messages VALUES (2, 1, 'assistant', 'Unearned favour.', '["Ephesians 2:8"]', 18);
    INSERT INTO notebooks VALUES (1, 'Shepherd', 19, 19);
    INSERT INTO notebooks VALUES (2, 'Romans', 20, 20);
  ''');
  final sources = [
    (1, 1, 'passage', 'Psalm 23:1 (BSB)', 'Psalm 23:1|BSB', '1 The LORD is my shepherd.'),
    (2, 1, 'note', 'Note on John 3:16', 'John 3:16', 'Loved first.'),
    (3, 1, 'note', 'Note on Genesis 1:1', 'Genesis 1:1', 'Original words.'),
    (4, 1, 'text', 'Pasted', '', 'Shepherds keep watch by night.'),
    (5, 2, 'passage', 'Romans 8 (BSB)', 'Romans 8|BSB', '28 All things work together.'),
  ];
  for (final (id, nb, kind, title, origin, text) in sources) {
    db.execute(
      'INSERT INTO notebook_sources(id, notebook_id, kind, title, origin, text, created) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, nb, kind, title, origin, text, id],
    );
    db.execute(
      'INSERT INTO notebook_chunks(source_id, ordinal, start_offset, end_offset, page, text) '
      'VALUES (?, 0, 0, ?, NULL, ?)',
      [id, text.length, text],
    );
  }
  db.execute(
    'INSERT INTO notebook_messages(id, notebook_id, role, text, refs, sources, created) VALUES '
    "(1, 1, 'user', 'Who is the shepherd?', '[]', '[]', 21), "
    "(2, 1, 'assistant', 'The LORD [1].', '[\"Psalm 23:1\"]', ?, 22)",
    [_citation],
  );
}

String _makeFixture(Directory dir) {
  final path = '${dir.path}/study.sqlite';
  final db = sqlite3.open(path)
    ..execute(_v030Tables)
    ..execute(notebookSchema)
    ..execute(notebookChatSchema)
    ..execute('PRAGMA user_version = 2');
  _fill(db);
  db.dispose();
  return path;
}

typedef _Tables = Map<String, List<Map<String, Object?>>>;

_Tables _snapshot(Database db) => {
  for (final t in StudyStore.userTables)
    t: [
      for (final r in db.select('SELECT * FROM $t ORDER BY 1, 2, 3')) Map<String, Object?>.from(r),
    ],
};

/// Every row of [before] is in [after] with the same values, matched on its key columns.
void _expectKept(_Tables before, _Tables after) {
  for (final t in before.keys) {
    expect(after[t]!.length, greaterThanOrEqualTo(before[t]!.length), reason: t);
    for (final row in before[t]!) {
      final match = after[t]!.where((r) => row.keys.every((c) => r[c] == row[c]));
      expect(match, hasLength(1), reason: '$t row $row');
    }
  }
}

int _notebookId(Database db, String title) =>
    db.select('SELECT id FROM notebooks WHERE title = ?', [title]).single['id'] as int;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('berea_notes_merge'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the notes merge backs up first and keeps every row, once', () {
    final path = _makeFixture(dir);
    final raw = sqlite3.open(path);
    final before = _snapshot(raw);
    raw.dispose();

    final store = StudyStore.open(path);
    final db = store.db;
    expect(db.select('PRAGMA user_version').first.values.first, StudyStore.schemaVersion);

    // The copy beside the database holds the data exactly as it was.
    final backup = File('$path$preNotesMergeSuffix');
    expect(backup.existsSync(), isTrue);
    final copy = sqlite3.open(backup.path);
    expect(copy.select('PRAGMA user_version').first.values.first, 2);
    expect(_snapshot(copy), before);
    copy.dispose();

    final after = _snapshot(db);
    _expectKept(before, after);
    for (final t in before.keys) {
      if (t == 'notebooks' || t == 'conversations' || t == 'messages') continue;
      expect(after[t]!.length, before[t]!.length, reason: t);
    }

    final verses = _notebookId(db, notesOnVersesTitle);
    expect([for (final r in after['notes']!) r['notebook_id']], [verses, verses, verses]);
    expect(store.notes().map((n) => n.text), containsAll(['Loved first.', 'All things.']));
    expect(store.notebookNotes(verses), hasLength(3));

    // Exact passage, containing chapter, then no notebook.
    expect(
      {for (final p in store.studyPages()) p.ref.label: p.notebookId},
      {'Psalms 23:1': 1, 'Romans 8:28-30': 2, 'Genesis 1:1': verses},
    );

    final books = NotebookStore(db);
    expect({for (final s in books.sources(1)) s.id: s.noteId}, {1: null, 2: 1, 3: null, 4: null});
    expect(books.search(1, 'shepherds').map((c) => c.title), contains('Pasted'));
    expect(books.messages(1), hasLength(2));

    expect(store.conversations().single.title, 'What is grace?');
    final scoped = store.conversations(notebookId: 1).single;
    expect(scoped.title, 'Who is the shepherd?');
    final copied = store.messages(scoped.id);
    expect(copied.map((m) => m.text), ['Who is the shepherd?', 'The LORD [1].']);
    expect(copied.last.refs.single.label, 'Psalms 23:1');
    expect(copied.last.sources.single.chunk.sourceId, 2);
    expect(store.conversations(notebookId: 2), isEmpty);
    store.close();

    // Opening again migrates nothing twice and changes nothing.
    final again = StudyStore.open(path);
    expect(_snapshot(again.db), after);
    again.close();
  });

  test('a fresh install writes no backup and makes no notes on verses notebook', () {
    final path = '${dir.path}/study.sqlite';
    final store = StudyStore.open(path);
    expect(File('$path$preNotesMergeSuffix').existsSync(), isFalse);
    expect(store.db.select('SELECT * FROM notebooks'), isEmpty);
    store.close();
  });

  test('notebooks with nothing homeless gain no notes on verses notebook', () {
    final path = '${dir.path}/study.sqlite';
    sqlite3.open(path)
      ..execute(_v030Tables)
      ..execute(notebookSchema)
      ..execute(notebookChatSchema)
      ..execute('PRAGMA user_version = 2')
      ..execute("INSERT INTO notebooks VALUES (1, 'Psalms', 1, 1)")
      ..execute(
        'INSERT INTO notebook_sources(notebook_id, kind, title, origin, text) '
        "VALUES (1, 'passage', 'Psalm 23', 'Psalm 23|BSB', '1 The LORD.')",
      )
      ..execute("INSERT INTO study_pages VALUES (1, 19, 23, 4, 4, 'O', 'I', 'A', 1, 1)")
      ..dispose();
    final store = StudyStore.open(path);
    expect(NotebookStore(store.db).notebooks().map((n) => n.title), ['Psalms']);
    expect(store.studyPages().single.notebookId, 1);
    expect(File('$path$preNotesMergeSuffix').existsSync(), isTrue);
    store.close();
  });

  test('when the backup cannot be written nothing is migrated', () {
    final path = _makeFixture(dir);
    // A directory where the copy goes makes VACUUM INTO fail.
    Directory('$path$preNotesMergeSuffix.partial').createSync();
    expect(() => StudyStore.open(path), throwsA(isA<SqliteException>()));
    final raw = sqlite3.open(path);
    expect(raw.select('PRAGMA user_version').first.values.first, 2);
    expect(raw.select('SELECT * FROM notebooks'), hasLength(2));
    raw.dispose();
  });

  test('a version 2 backup from 0.6.0 restores in the merged shape', () async {
    final contents = await readBackup(
      File('test/fixtures/backup-v2.berea').readAsBytesSync(),
      'correct horse',
    );
    expect(contents.version, 2);
    final store = StudyStore(sqlite3.openInMemory());
    store.addNotebookNote(NotebookStore(store.db).createNotebook('Replaced'), 'Gone.');
    store.importTables(contents.tables);
    final db = store.db;
    final books = NotebookStore(db);

    expect(
      books.notebooks().map((n) => n.title),
      unorderedEquals(['Psalm 23', notesOnVersesTitle]),
    );
    final psalm = _notebookId(db, 'Psalm 23');
    final verses = _notebookId(db, notesOnVersesTitle);
    expect(
      store.notebookNotes(verses).map((n) => n.text),
      unorderedEquals(['Loved first.', 'All things.']),
    );
    expect(
      {for (final p in store.studyPages()) p.ref.label: p.notebookId},
      {'Psalms 23:1': psalm, 'Genesis 1:1': verses},
    );
    final note = books.sources(psalm).singleWhere((s) => s.kind == SourceKind.note);
    expect(store.note(note.noteId!)!.text, 'Loved first.');
    expect(books.sources(psalm), hasLength(3));
    expect(store.conversations().single.title, 'What is grace?');
    final scoped = store.conversations(notebookId: psalm).single;
    expect(store.messages(scoped.id).last.sources.single.chunk.sourceId, note.id);
    expect(books.messages(psalm), hasLength(2));
    expect(store.highlights(bookById(43), 3), {16});
    expect(store.planDaysDone('nt-90'), {1});

    // Restoring the same backup again gives the same rows; only the new notebook's id moves on.
    final once = store.exportTables();
    store.importTables(contents.tables);
    final twice = store.exportTables();
    expect(
      {for (final e in twice.entries) e.key: e.value.length},
      {for (final e in once.entries) e.key: e.value.length},
    );
    expect(store.notebookNotes(_notebookId(db, notesOnVersesTitle)), hasLength(2));
  });

  test('a version 3 backup round trips the merged shape exactly', () async {
    final path = _makeFixture(dir);
    final source = StudyStore.open(path);
    source.addNotebookNote(1, 'Sermon on the shepherd.', title: 'Sunday');
    final bytes = await createBackup(source, const {}, 'correct horse');
    final contents = await readBackup(bytes, 'correct horse');
    expect(contents.version, backupVersion);
    final target = StudyStore(sqlite3.openInMemory());
    target.importTables(contents.tables);
    expect(target.exportTables(), source.exportTables());
    source.close();
  });

  test(
    'a version 1 backup restores under kept notebooks and their conversations come back',
    () async {
      final path = _makeFixture(dir);
      final store = StudyStore.open(path);
      final contents = await readBackup(
        File('test/fixtures/backup-v1.berea').readAsBytesSync(),
        'correct horse',
      );
      store.importTables(contents.tables);
      final books = NotebookStore(store.db);
      expect(books.notebooks(), hasLength(3));
      expect(store.notes().single.text, 'Loved first.');
      // The restored note has the copy's verse and text, so the copy links to it again.
      expect(books.source(2)!.noteId, store.notes().single.id);
      expect(books.source(3)!.noteId, isNull);
      expect(store.messages(store.conversations(notebookId: 1).single.id), hasLength(2));
      store.close();
    },
  );

  test('backups that point at missing notebooks or notes are refused', () {
    final store = StudyStore(sqlite3.openInMemory());
    final nb = NotebookStore(store.db).createNotebook('N');
    store.addNotebookNote(nb, 'Keep me.');
    final good = store.exportTables();
    for (final bad in <_Tables>[
      {
        ...good,
        'notes': [
          {...good['notes']!.single, 'notebook_id': 42},
        ],
      },
      {
        ...good,
        'notes': [
          {...good['notes']!.single, 'book': 43},
        ],
      },
      {
        ...good,
        'notebook_sources': [
          {
            'id': 1,
            'notebook_id': nb,
            'kind': 'note',
            'title': 'T',
            'origin': '',
            'text': 'x',
            'note_id': 9,
          },
        ],
      },
    ]) {
      expect(() => store.importTables(bad), throwsFormatException);
    }
    expect(store.notebookNotes(nb).single.text, 'Keep me.');
  });

  test('notes without a verse, linked note sources and deleting a notebook', () async {
    final store = StudyStore(sqlite3.openInMemory());
    final books = NotebookStore(store.db, ingest: (r) async => chunkSections([r.text ?? '']));
    final sermons = books.createNotebook('Sermons');
    final sermon = store.addNotebookNote(sermons, 'Grace upon grace.', title: 'Sunday');
    final verseNote = store.addNote(RefParser.parse('John 1:16').first, 'Fullness.');
    expect(store.notes().single.id, verseNote);
    expect(store.notebookNotes(sermons).single.title, 'Sunday');
    expect(store.note(sermon)!.verse, isNull);

    final src = (await books.addSource(sermons, noteSource(store.note(verseNote)!)))!;
    expect(books.source(src)!.noteId, verseNote);
    store.updateNote(verseNote, 'Fullness of grace.');
    expect(books.sourceText(src), 'Fullness of grace.');
    expect(books.search(sermons, 'fullness').single.text, 'Fullness of grace.');

    store.saveNote(
      sermon,
      notebookId: sermons,
      text: 'Edited.',
      title: 'Sunday',
      verse: RefParser.parse('John 1:17').first,
    );
    expect(store.note(sermon)!.verse!.label, 'John 1:17');

    final ref = RefParser.parse('Psalm 1:1').first;
    store.saveStudyPage(ref, 'O', 'I', 'A', notebookId: sermons);
    final asked = store.createConversation('Grace?', notebookId: sermons);

    books.deleteNotebook(sermons);
    final verses = _notebookId(store.db, notesOnVersesTitle);
    expect(store.notebookNotes(verses), hasLength(2));
    expect(store.studyPageFor(ref)!.notebookId, verses);
    expect(store.conversation(asked)!.notebookId, isNull);

    store.deleteNote(verseNote);
    expect(store.note(verseNote), isNull);
  });

  test('deleting a linked note leaves its source as a copy', () async {
    final store = StudyStore(sqlite3.openInMemory());
    final books = NotebookStore(store.db, ingest: (r) async => chunkSections([r.text ?? '']));
    final nb = books.createNotebook('N');
    final id = store.addNote(RefParser.parse('John 3:16').first, 'Loved first.');
    final src = (await books.addSource(nb, noteSource(store.note(id)!)))!;
    store.deleteNote(id);
    expect(books.source(src)!.noteId, isNull);
    expect(books.sourceText(src), 'Loved first.');
  });

  test('export covers notes without a verse, notebook by notebook', () {
    final store = StudyStore(sqlite3.openInMemory());
    final nb = NotebookStore(store.db).createNotebook('Sermons');
    store.addNotebookNote(nb, 'Grace upon grace.', title: 'Sunday');
    final c = store.createConversation('Grace?', notebookId: nb);
    store.addMessage(c, 'user', 'Grace?', const []);
    final bible = BibleDb(
      sqlite3.openInMemory()..execute(
        'CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, '
        'chapter INTEGER, verse INTEGER, text TEXT)',
      ),
    );
    final md = allNotesMarkdown(store, bible, 'BSB');
    expect(md, contains('## Sermons'));
    expect(md, contains('### Sunday\n\nGrace upon grace.'));
    expect(md, contains('## Grace?'));
    expect(jsonEncode(md), isNot(contains('null')));
  });
}
