import 'dart:io';

import 'package:berea/provenance.dart';
import 'package:berea/provenance_line.dart';
import 'package:material_ui/material_ui.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// A study.sqlite as 0.8.0 left it: the schema up to migration 7, a chat, and notes some of which
/// were kept from answers.
String _oldFile(Directory dir) {
  final path = '${dir.path}/study.sqlite';
  final store = StudyStore.open(path);
  final db = store.db;
  StudyStore.notesOnVersesNotebook(db);
  // Rewind: drop the columns migration 8 adds and set the version back.
  db.execute('PRAGMA user_version = 7');
  store.close();
  final raw = sqlite3.open(path);
  for (final t in ['notes', 'study_pages', 'notebook_sources']) {
    raw.execute('ALTER TABLE $t DROP COLUMN provenance');
  }
  raw.dispose();
  return path;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('berea_provenance'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the rule labels a kept word, a kept commentary and the reader\'s own words', () {
    expect(
      provenanceFor(kind: 'word', title: 'agapao', text: 'love'),
      provenanceRewrite,
    );
    expect(
      provenanceFor(kind: 'studyword', title: 'x', text: 'y'),
      provenanceRewrite,
    );
    expect(
      provenanceFor(
        kind: 'note',
        title: 'Matthew Henry on John 3:16',
        text: 'God so loved.\n\nMatthew Henry · Public domain',
      ),
      provenanceSource,
    );
    expect(
      provenanceFor(kind: 'note', title: 'Sermon on Sunday', text: 'Peace.'),
      provenancePerson,
    );
    expect(provenanceLabel(provenancePerson), isNull);
    expect(provenanceLabel(provenanceSource), isNull);
    expect(provenanceLabel(provenanceMachine), contains('language model'));
  });

  test('migration 8 labels existing text by what wrote it, then deletes the chat only', () {
    final path = _oldFile(dir);
    final raw = sqlite3.open(path);
    final verse = RefParser.parse('John 3:16').first;
    final nb = raw.select('SELECT id FROM notebooks').first['id'] as int;
    raw.execute(
      "INSERT INTO conversations(id, title, created, updated) VALUES (1, 'Q', 1, 1)",
    );
    raw.execute(
      "INSERT INTO messages(conversation_id, role, text, refs, created) VALUES "
      "(1, 'user', 'What is love?', '[]', 1), (1, 'assistant', 'Love is patient.', '[]', 1)",
    );
    final ins = raw.prepare(
      'INSERT INTO notes(book, chapter, verse_start, verse_end, text, title, notebook_id, kind, '
      'created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
    );
    ins.execute([43, 3, 16, 16, 'Love is patient.', 'Go deeper', nb, 'note']);
    ins.execute([43, 3, 16, 16, 'agape\nStrong\'s G26', 'agape', nb, 'word']);
    ins.execute([
      43,
      3,
      16,
      16,
      'God so loved.\n\nHenry · PD',
      'Henry on John 3:16',
      nb,
      'note',
    ]);
    ins.execute([43, 3, 16, 16, 'My own thought.', '', nb, 'note']);
    ins.dispose();
    raw.execute(
      'INSERT INTO study_pages(book, chapter, verse_start, verse_end, observation, interpretation, '
      "application, notebook_id, created, updated) VALUES (43, 3, 16, 16, 'o', 'i', 'a', $nb, 1, 1)",
    );
    raw.dispose();

    final store = StudyStore.open(path);
    final byText = {for (final n in store.notes()) n.text: n.provenance};
    expect(
      byText['Love is patient.'],
      provenanceMachine,
      reason: 'kept from an answer',
    );
    expect(byText["agape\nStrong's G26"], provenanceRewrite);
    expect(byText['God so loved.\n\nHenry · PD'], provenanceSource);
    expect(byText['My own thought.'], provenancePerson);
    expect(store.studyPageFor(verse)!.provenance, provenanceUnknown);
    // The chat is gone; every note the reader kept is still there.
    expect(store.conversations(), isEmpty);
    expect(store.db.select('SELECT 1 FROM messages'), isEmpty);
    expect(store.notes(), hasLength(4));
    store.close();
  });

  test(
    'a note written now carries its label, and a backup round trips it',
    () async {
      final store = StudyStore(sqlite3.openInMemory());
      final id = store.addNotebookNote(
        StudyStore.notesOnVersesNotebook(store.db),
        'x',
        kind: 'word',
        verse: RefParser.parse('John 3:16').first,
      );
      expect(store.note(id)!.provenance, provenanceRewrite);
      final tables = store.exportTables();
      expect(tables['notes']!.single['provenance'], provenanceRewrite);
      final other = StudyStore(sqlite3.openInMemory());
      other.importTables(tables);
      expect(
        other.db.select('SELECT provenance FROM notes').single['provenance'],
        provenanceRewrite,
      );
    },
  );

  test(
    'a restored backup that predates labels is labelled and loses its chat',
    () {
      final store = StudyStore(sqlite3.openInMemory());
      final tables = {
        'conversations': [
          {'id': 1, 'title': 'Q', 'updated': 1},
        ],
        'messages': [
          {
            'id': 1,
            'conversation_id': 1,
            'role': 'assistant',
            'text': 'Kept answer.',
            'refs': '[]',
          },
        ],
        'notes': [
          {'id': 1, 'text': 'Kept answer.', 'updated': 1},
          {'id': 2, 'text': 'Mine.', 'updated': 1},
        ],
      };
      store.importTables(tables);
      expect(
        {
          for (final r in store.db.select('SELECT text, provenance FROM notes'))
            r['text']: r['provenance'],
        },
        {'Kept answer.': provenanceMachine, 'Mine.': provenancePerson},
      );
      expect(store.conversations(), isEmpty);
    },
  );

  test('a backup naming a provenance that does not exist is refused', () {
    final store = StudyStore(sqlite3.openInMemory());
    expect(
      () => store.importTables({
        'notes': [
          {'id': 1, 'text': 'x', 'updated': 1, 'provenance': 'robot'},
        ],
      }),
      throwsFormatException,
    );
  });

  testWidgets('the line shows for text a model or Berea wrote, and not for a person\'s', (tester) async {
    for (final p in [provenanceMachine, provenanceRewrite, provenanceUnknown]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProvenanceLine(p))));
      expect(find.text(provenanceLabel(p)!), findsOneWidget, reason: p);
    }
    for (final p in [provenancePerson, provenanceSource]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProvenanceLine(p))));
      expect(find.byType(Text), findsNothing, reason: p);
    }
  });
}
