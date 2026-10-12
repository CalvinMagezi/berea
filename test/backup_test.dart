import 'dart:io';
import 'dart:typed_data';

import 'package:berea/backup.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('backup round trips, and a wrong passphrase leaves data untouched', () async {
    final source = StudyStore(sqlite3.openInMemory());
    source.addNote(RefParser.parse('John 3:16').first, 'Loved first.');
    source.toggleHighlight(bookById(43), 3, 16);
    source.setPlanDay('nt-90', 1, true);
    source.saveStudyPage(RefParser.parse('Psalm 23:1').first, 'O', 'I', 'A');
    final c = source.createConversation('Q?');
    source.addMessage(c, 'user', 'Q?', const []);

    final bytes = await createBackup(source, {'NIV': 'Book,Chapter,Verse,Text\n'}, 'correct horse');

    final target = StudyStore(sqlite3.openInMemory());
    target.addNote(RefParser.parse('Genesis 1:1').first, 'Keep me.');
    await expectLater(readBackup(bytes, 'wrong'), throwsA(isA<BackupException>()));
    expect(target.notes().single.text, 'Keep me.');

    final contents = await readBackup(bytes, 'correct horse');
    target.importTables(contents.tables);
    expect(target.notes().single.text, 'Loved first.');
    expect(target.highlights(bookById(43), 3), {16});
    expect(target.planDaysDone('nt-90'), {1});
    expect(target.studyPageFor(RefParser.parse('Psalm 23:1').first)!.application, 'A');
    expect(target.messages(c).single.text, 'Q?');
    expect(contents.imports.keys, ['NIV']);
  });

  test('rows with unknown columns or impossible books are rejected before anything changes', () {
    final store = StudyStore(sqlite3.openInMemory());
    store.addNote(RefParser.parse('John 3:16').first, 'Keep me.');
    expect(
      () => store.importTables({
        'notes': [
          {'id': 1, 'book': 99, 'chapter': 1, 'verse_start': 1, 'verse_end': 1, 'text': 'x'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => store.importTables({
        'notes': [
          {'id': 1, 'book': 1, 'chapter': 1, 'evil); DROP TABLE notes; --': 1},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => store.importTables({
        'notes': [
          {'id': 1, 'book': 1, 'chapter': 'one', 'verse_start': 1, 'verse_end': 1, 'text': null},
        ],
      }),
      throwsFormatException,
    );
    expect(store.notes().single.text, 'Keep me.');
  });

  test('a truncated backup is reported as damaged', () async {
    final bytes = await createBackup(StudyStore(sqlite3.openInMemory()), const {}, 'correct horse');
    await expectLater(
      readBackup(Uint8List.fromList(bytes.sublist(0, 30)), 'correct horse'),
      throwsA(isA<BackupException>()),
    );
  });

  test('an absurd round count in the header is rejected without deriving a key', () async {
    final bytes = await createBackup(StudyStore(sqlite3.openInMemory()), const {}, 'correct horse');
    final header = 'BEREA-BACKUP-2\n'.length;
    ByteData.sublistView(bytes).setUint32(header, 0xFFFFFFFF);
    await expectLater(readBackup(bytes, 'correct horse'), throwsA(isA<BackupException>()));
  });

  test('notebooks round trip in a version 2 backup, search index included', () async {
    final source = StudyStore(sqlite3.openInMemory());
    final books = NotebookStore(source.db);
    final nb = books.createNotebook('Romans 8');
    final long = List.filled(50, 'Nothing can separate us from the love of God.').join(' ');
    await books.addSource(nb, SourceRequest(SourceKind.text, 'Pasted', text: long));
    source.addNote(RefParser.parse('John 3:16').first, 'Loved first.');
    final bytes = await createBackup(source, const {}, 'correct horse');

    final target = StudyStore(sqlite3.openInMemory());
    final targetBooks = NotebookStore(target.db);
    targetBooks.createNotebook('Replaced');
    final contents = await readBackup(bytes, 'correct horse');
    expect(contents.version, backupVersion);
    expect(contents.hasNotebooks, isTrue);
    target.importTables(contents.tables);
    expect(targetBooks.notebooks().single.title, 'Romans 8');
    final chunks = targetBooks.chunks(nb);
    expect(chunks.map((c) => c.text), books.chunks(nb).map((c) => c.text));
    expect(targetBooks.search(nb, 'separated').length, chunks.length);
    expect(target.notes().single.text, 'Loved first.');
  });

  test('a version 1 backup from 0.3.0 still restores and keeps notebooks', () async {
    final bytes = File('test/fixtures/backup-v1.berea').readAsBytesSync();
    final contents = await readBackup(bytes, 'correct horse');
    expect(contents.version, 1);
    expect(contents.hasNotebooks, isFalse);
    final target = StudyStore(sqlite3.openInMemory());
    final books = NotebookStore(target.db);
    final kept = books.createNotebook('Kept');
    await books.addSource(kept, const SourceRequest(SourceKind.text, 'Mine', text: 'Grace.'));
    target.addNote(RefParser.parse('Genesis 1:1').first, 'Replaced.');
    target.validateTables(contents.tables);
    target.importTables(contents.tables);
    expect(target.notes().single.text, 'Loved first.');
    expect(target.highlights(bookById(43), 3), {16});
    expect(target.studyPageFor(RefParser.parse('Psalm 23:1').first)!.application, 'A');
    expect(books.notebooks().single.title, 'Kept');
    expect(books.search(kept, 'grace').single.sourceTitle, 'Mine');
  });

  test('notebook rows that do not fit together are rejected before anything changes', () async {
    final store = StudyStore(sqlite3.openInMemory());
    final books = NotebookStore(store.db);
    final nb = books.createNotebook('Keep me');
    await books.addSource(nb, const SourceRequest(SourceKind.text, 'T', text: 'In the beginning.'));
    final good = store.exportTables();
    Map<String, List<Map<String, Object?>>> edited(String table, Map<String, Object?> change) => {
      ...good,
      table: [
        for (final r in good[table]!) {...r, ...change},
      ],
    };
    for (final bad in [
      {...good}..remove('notebook_chunks'),
      {'notebooks': good['notebooks']!},
      edited('notebook_chunks', {'text': 'In the end.'}),
      edited('notebook_chunks', {'end_offset': 9999}),
      edited('notebook_chunks', {'source_id': 42}),
      edited('notebook_chunks', {'page': 0}),
      edited('notebook_sources', {'notebook_id': 42}),
      edited('notebook_sources', {'kind': 'video'}),
      edited('notebooks', {'title': null}),
    ]) {
      expect(() => store.importTables(bad), throwsFormatException);
    }
    expect(books.notebooks().single.title, 'Keep me');
    expect(books.search(nb, 'beginning'), hasLength(1));
    // A table older than notebooks that the backup lacks is still cleared, as before.
    store.toggleHighlight(bookById(43), 3, 16);
    store.importTables({
      for (final t in ['notes', 'conversations', 'messages', 'plan_progress', 'study_pages'])
        t: const [],
    });
    expect(store.highlights(bookById(43), 3), isEmpty);
    expect(books.notebooks().single.title, 'Keep me');
  });

  test('a file that is not a backup is rejected', () async {
    await expectLater(
      readBackup(Uint8List.fromList('hello'.codeUnits), 'x'),
      throwsA(isA<BackupException>()),
    );
  });
}
