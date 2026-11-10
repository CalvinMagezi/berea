import 'package:berea/hide_words.dart';
import 'package:berea/practice_store.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late PracticeStore practice;
  var today = DateTime(2026, 11, 10, 9);
  final john316 = RefParser.parse('John 3:16').first;
  setUp(() {
    today = DateTime(2026, 11, 10, 9);
    practice = PracticeStore(
      StudyStore(sqlite3.openInMemory()).db,
      now: () => today,
    );
  });

  int daysUntilDue(int id) =>
      practice.items().firstWhere((i) => i.id == id).dueDay - epochDay(today);

  test('a new item is due today, and the same passage is added once', () {
    final id = practice.addItem(john316, 'BSB');
    expect(practice.addItem(john316, 'BSB'), id);
    expect(
      practice.addItem(john316, 'KJV'),
      isNot(id),
      reason: 'another translation',
    );
    expect(practice.due().map((i) => i.id), contains(id));
    expect(daysUntilDue(id), 0);
  });

  test('each pass waits twice as long, to 128 days, and stays there', () {
    final id = practice.addItem(john316, 'BSB');
    final waits = <int>[];
    for (var i = 0; i < 10; i++) {
      practice.record(id, passed: true);
      waits.add(daysUntilDue(id));
      today = today.add(Duration(days: waits.last));
    }
    expect(waits, [1, 2, 4, 8, 16, 32, 64, 128, 128, 128]);
  });

  test('a miss goes back to the first rung and is due tomorrow', () {
    final id = practice.addItem(john316, 'BSB');
    for (var i = 0; i < 4; i++) {
      practice.record(id, passed: true);
      today = today.add(Duration(days: daysUntilDue(id)));
    }
    practice.record(id, passed: false);
    expect(daysUntilDue(id), 1);
    expect(practice.items().single.rung, 0);
    practice.record(id, passed: true);
    expect(daysUntilDue(id), 1, reason: 'the climb starts again');
  });

  test(
    'what is due comes from the stored day, so a week away loses nothing',
    () {
      final id = practice.addItem(john316, 'BSB');
      practice.record(id, passed: true);
      expect(practice.due(), isEmpty);
      expect(
        practice.due(on: today.add(const Duration(days: 1))).map((i) => i.id),
        [id],
      );
      expect(
        practice.due(on: today.add(const Duration(days: 9))).map((i) => i.id),
        [id],
      );
    },
  );

  test('the last word for word is kept only while the last try was one', () {
    final id = practice.addItem(john316, 'BSB');
    expect(practice.lastWordForWord, isNull);
    practice.record(id, passed: true);
    expect(practice.lastWordForWord, isNotNull);
    expect(practice.items().single.lastWordForWord, isNotNull);
    today = today.add(const Duration(days: 2));
    practice.record(id, passed: false);
    // Only the last result is stored, so a miss leaves no word-for-word date to show.
    expect(practice.items().single.lastWordForWord, isNull);
    expect(practice.lastWordForWord, isNull);
    practice.record(id, passed: true);
    expect(practice.lastWordForWord, DateTime(2026, 11, 12, 9));
  });

  test('items in a chapter of today\'s reading are found by chapter', () {
    practice.addItem(john316, 'BSB');
    practice.addItem(RefParser.parse('Psalm 23:1').first, 'BSB');
    final reading = [Ref(bookById(43), 3), Ref(bookById(43), 4)];
    expect(practice.inReading(reading).map((i) => i.ref.label), ['John 3:16']);
    expect(practice.inReading([Ref(bookById(43), 5)]), isEmpty);
    practice.removeItem(practice.items().first.id);
    expect(practice.items(), hasLength(1));
  });

  group('hiding words', () {
    const verse =
        'For God so loved the world, that He gave His one and only Son.';

    test('each stage hides everything the stage before it did, 0 to all', () {
      final stages = hideStages(verse, seedText: 'John 3:16');
      final n = verseWords(verse).length;
      expect(
        [for (final s in stages) s.length],
        [0, (n * 0.25).ceil(), (n * 0.5).ceil(), (n * 0.75).ceil(), n],
      );
      for (var i = 1; i < stages.length; i++) {
        expect(
          stages[i].containsAll(stages[i - 1]),
          isTrue,
          reason: 'stage $i',
        );
      }
    });

    test('the same verse hides the same words on every run, and another verse differs', () {
      expect(
        hideStages(verse, seedText: 'John 3:16'),
        hideStages(verse, seedText: 'John 3:16'),
      );
      expect(
        stableSeed('John 3:16'),
        3585100390,
        reason: 'fixed, unlike String.hashCode',
      );
      expect(
        hideStages(verse, seedText: 'John 3:17')[2],
        isNot(hideStages(verse, seedText: 'John 3:16')[2]),
      );
    });
  });
}
