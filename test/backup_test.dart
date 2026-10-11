import 'dart:typed_data';

import 'package:berea/backup.dart';
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
    expect(store.notes().single.text, 'Keep me.');
  });

  test('a truncated backup is reported as damaged', () async {
    final bytes = await createBackup(StudyStore(sqlite3.openInMemory()), const {}, 'correct horse');
    await expectLater(
      readBackup(Uint8List.fromList(bytes.sublist(0, 30)), 'correct horse'),
      throwsA(isA<BackupException>()),
    );
  });

  test('a file that is not a backup is rejected', () async {
    await expectLater(
      readBackup(Uint8List.fromList('hello'.codeUnits), 'x'),
      throwsA(isA<BackupException>()),
    );
  });
}
