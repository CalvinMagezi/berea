import 'dart:io';

import 'package:berea/backup.dart';
import 'package:berea/export.dart';
import 'package:berea/prayer_store.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('prayers round trip in a backup', () async {
    final source = StudyStore(sqlite3.openInMemory());
    final prayers = PrayerStore(source.db);
    final id = prayers.add(title: 'For Sam', verse: 'Philippians 4:6-7');
    prayers.amen(id);

    final bytes = await createBackup(source, const {}, 'correct horse');
    final target = StudyStore(sqlite3.openInMemory());
    target.importTables((await readBackup(bytes, 'correct horse')).tables);

    final back = PrayerStore(target.db).praying().single;
    expect(back.title, 'For Sam');
    expect(back.verse, 'Philippians 4:6-7');
    expect(back.daysPrayed, 1);
  });

  test(
    'restoring a backup made before Prayer keeps the prayers on the device',
    () async {
      final target = StudyStore(sqlite3.openInMemory());
      PrayerStore(target.db).add(title: 'Keep me');
      final old = await readBackup(
        File('test/fixtures/backup-v2.berea').readAsBytesSync(),
        'correct horse',
      );
      expect(old.tables.containsKey('prayers'), isFalse);

      target.importTables(old.tables);

      expect(PrayerStore(target.db).praying().single.title, 'Keep me');
    },
  );

  test('a prayer day with no prayer is refused before anything changes', () {
    final store = StudyStore(sqlite3.openInMemory());
    PrayerStore(store.db).add(title: 'Keep me');
    final tables = store.exportTables()
      ..['prayer_days'] = [
        {'prayer_id': 99, 'day': 20261028},
      ];
    expect(() => store.importTables(tables), throwsFormatException);
    expect(PrayerStore(store.db).praying().single.title, 'Keep me');
  });

  test('the notes export includes prayers', () {
    final store = StudyStore(sqlite3.openInMemory());
    PrayerStore(store.db).add(title: 'For Sam');
    final md = allNotesMarkdown(store, BibleDb.open(':memory:'), 'BSB');
    expect(md, contains('## Prayer'));
    expect(md, contains('#### For Sam'));
  });
}
