import 'package:berea/prayer_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late DateTime clock;
  late PrayerStore store;

  setUp(() {
    db = sqlite3.openInMemory()..execute(prayerSchema);
    clock = DateTime(2026, 10, 2, 9);
    store = PrayerStore(db, now: () => clock);
  });

  test('add, edit and read back a prayer', () {
    final id = store.add(title: ' Peace for Brian ', forWhom: 'Brian', verse: 'phil 4:6-7');
    var p = store.prayer(id)!;
    expect(p.title, 'Peace for Brian');
    expect(p.forWhom, 'Brian');
    expect(p.verse, 'Philippians 4:6-7');
    expect(p.ref, RefParser.parse('Philippians 4:6-7').first);
    expect(p.lastPrayed, isNull);
    expect(p.reminder, isNull);

    store.edit(id, title: 'Peace for Brian before his exams', forWhom: 'Brian', verse: '');
    p = store.prayer(id)!;
    expect(p.title, 'Peace for Brian before his exams');
    expect(p.verse, isNull);
    expect(store.praying().single.id, id);
  });

  test('a verse label parses back to the same reference', () {
    for (final typed in ['1 Thessalonians 5:16-18', 'Isaiah 41:10', '1thess 5:16-18']) {
      final label = verseLabel(typed)!;
      expect(verseLabel(label), label);
      expect(RefParser.parse(label).first.label, label);
    }
    expect(verseLabel('not a verse'), isNull);
  });

  test('Amen records today once, and each new day once more', () {
    final id = store.add(title: 'Rain for the harvest');
    store.amen(id);
    store.amen(id);
    expect(store.prayer(id)!.daysPrayed, 1);
    expect(store.prayer(id)!.lastPrayed, DateTime(2026, 10, 2));

    clock = DateTime(2026, 10, 3, 6);
    store.amen(id);
    final p = store.prayer(id)!;
    expect(p.daysPrayed, 2);
    expect(p.firstPrayed, DateTime(2026, 10, 2));
    expect(p.lastPrayed, DateTime(2026, 10, 3));
  });

  test('Pray now goes least recently prayed first, never prayed before all', () {
    final a = store.add(title: 'A');
    clock = clock.add(const Duration(minutes: 1));
    final b = store.add(title: 'B');
    clock = clock.add(const Duration(minutes: 1));
    final c = store.add(title: 'C');
    final d = store.add(title: 'D');
    store.amen(a);
    clock = DateTime(2026, 10, 5);
    store.amen(b);
    store.markAnswered(d, 'Done');

    expect([for (final p in store.prayNowQueue()) p.id], [c, a, b]);
  });

  test('answered keeps the line and date, leaves Pray now, and Undo puts it back', () {
    final id = store.add(title: 'Job interview at the bank', forWhom: 'Me');
    clock = DateTime(2026, 10, 28, 12);
    store.markAnswered(id, ' I got the job. ');
    final p = store.answered().single;
    expect(p.answer, 'I got the job.');
    expect(p.answered, DateTime(2026, 10, 28, 12));
    expect(store.praying(), isEmpty);
    expect(store.prayNowQueue(), isEmpty);

    store.unanswer(id);
    expect(store.answered(), isEmpty);
    expect(store.praying().single.id, id);
  });

  test('stopped prayers are kept but out of the list and Pray now', () {
    final id = store.add(title: 'Old request');
    store.setArchived(id, true);
    expect(store.praying(), isEmpty);
    expect(store.prayNowQueue(), isEmpty);
    expect(store.prayer(id)!.archived, isTrue);
    expect(store.isEmpty, isFalse);
  });

  test('delete removes the prayer and its days', () {
    final id = store.add(title: 'Gone');
    store.amen(id);
    store.delete(id);
    expect(store.isEmpty, isTrue);
    expect(db.select('SELECT * FROM prayer_days'), isEmpty);
  });

  test('markdown and share text are plain and complete', () {
    final a = store.add(title: 'Mama’s knee operation', forWhom: 'Mama', verse: 'Isaiah 41:10');
    store.amen(a);
    final b = store.add(title: 'Job interview', note: 'At the bank');
    store.markAnswered(b, 'I got the job.');
    final c = store.add(title: 'Stopped one');
    store.setArchived(c, true);

    final md = prayersMarkdown(store);
    expect(md, contains('## Praying'));
    expect(md, contains('### Mama’s knee operation'));
    expect(md, contains('For Mama'));
    expect(md, contains('Isaiah 41:10'));
    expect(md, contains('prayed on 1 day\n'));
    expect(md, contains('## Answered'));
    expect(md, contains('Answered 2026-10-02: I got the job.'));
    expect(md, contains('## No longer praying'));

    expect(prayerShareText(store.prayer(a)!), 'Mama’s knee operation (for Mama)\nIsaiah 41:10');
    expect(testimonyText(store.prayer(b)!), 'Job interview\nI got the job.\nAnswered 2026-10-02');
    expect(prayerListText(store.praying()), startsWith('Praying for\n- Mama’s knee operation'));
  });

  test('column types name only never-null columns that the schema has', () {
    final id = store.add(title: 'Typed');
    store.amen(id);
    for (final t in prayerTables) {
      final info = {for (final r in db.select('PRAGMA table_info($t)')) r['name'] as String: r};
      final types = prayerColumnTypes[t]!;
      for (final e in types.entries) {
        expect(info.containsKey(e.key), isTrue, reason: '$t.${e.key}');
        final declared = info[e.key]!['type'] as String;
        expect(declared, e.value == int ? 'INTEGER' : 'TEXT', reason: '$t.${e.key}');
        expect(
          info[e.key]!['notnull'] == 1 || info[e.key]!['pk'] != 0,
          isTrue,
          reason: '$t.${e.key} must never be null',
        );
      }
      for (final row in db.select('SELECT * FROM $t')) {
        for (final e in types.entries) {
          expect(e.value == int ? row[e.key] is int : row[e.key] is String, isTrue);
        }
      }
    }
  });

  test('backup checks catch days without a prayer and bad verses', () {
    final id = store.add(title: 'Kept', verse: 'John 3:16');
    store.amen(id);
    final tables = {
      for (final t in prayerTables)
        t: [for (final r in db.select('SELECT * FROM $t')) Map<String, Object?>.from(r)],
    };
    validatePrayerTables(tables);
    expect(
      () => validatePrayerTables({'prayers': const [], 'prayer_days': tables['prayer_days']!}),
      throwsFormatException,
    );
    expect(
      () => validatePrayerTables({
        'prayers': [
          {...tables['prayers']!.single, 'verse': 'nonsense'},
        ],
      }),
      throwsFormatException,
    );
  });
}
