import 'package:berea/daily_practices.dart';
import 'package:berea/daily_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the two practices', () {
    test('there are only two, each with its own keys and times', () {
      expect(Practice.values, hasLength(2));
      expect(Practice.building.title, 'Daily inner building');
      expect(Practice.reflection.title, 'Daily reflection');
      expect(Practice.building.onKey, isNot(Practice.reflection.onKey));
      expect(Practice.building.minutesKey, isNot(Practice.reflection.minutesKey));
      for (final p in Practice.values) {
        expect(p.times, contains(p.defaultMinutes));
      }
    });

    test('building is offered in the morning and reflection in the evening', () {
      expect(Practice.building.defaultMinutes, lessThan(12 * 60));
      expect(Practice.reflection.defaultMinutes, greaterThan(18 * 60));
    });
  });

  group('daily inner building', () {
    test('every stone says what it looks like and what to do', () {
      expect(stones, isNotEmpty);
      for (final s in stones) {
        expect(s.name, isNotEmpty);
        expect(s.picture, isNotEmpty);
        expect(s.practice, isNotEmpty);
      }
      expect(stones.map((s) => s.name).toSet(), hasLength(stones.length));
    });

    test('one stone a day, the next stone the next day, round and round', () {
      final today = DateTime(2026, 11, 17);
      final index = stones.indexOf(stoneFor(today));
      expect(stoneFor(DateTime(2026, 11, 18)), stones[(index + 1) % stones.length]);
      expect(stoneFor(today.add(Duration(days: stones.length))), stoneFor(today));
    });

    test('the time of day does not change the stone', () {
      expect(stoneFor(DateTime(2026, 11, 17, 0, 1)), stoneFor(DateTime(2026, 11, 17, 23, 59)));
    });

    test('a month end and a year end are one day apart like any other', () {
      final dec31 = stones.indexOf(stoneFor(DateTime(2026, 12, 31)));
      expect(stoneFor(DateTime(2027, 1, 1)), stones[(dec31 + 1) % stones.length]);
    });
  });

  group('daily reflection', () {
    test('the three lenses are sin, iniquity and transgression, in that order', () {
      expect(lenses.map((l) => l.name), ['Sin', 'Iniquity', 'Transgression']);
    });

    test('each lens asks one question and gives three prompts', () {
      for (final l in lenses) {
        expect(l.question, endsWith('?'));
        expect(l.prompts, hasLength(3));
      }
    });
  });

  group('the notifications', () {
    final morning = DateTime(2026, 11, 17, 5);

    test('fourteen days from today at the chosen time', () {
      final out = buildPracticeReminders(
        practice: Practice.building,
        now: morning,
        minutes: 7 * 60,
      );
      expect(out, hasLength(reminderDaysAhead));
      expect(out.first.when, DateTime(2026, 11, 17, 7));
      expect(out[1].when, DateTime(2026, 11, 18, 7));
    });

    test('a time already past today starts tomorrow', () {
      final out = buildPracticeReminders(
        practice: Practice.reflection,
        now: DateTime(2026, 11, 17, 22),
        minutes: 21 * 60,
      );
      expect(out.first.when, DateTime(2026, 11, 18, 21));
    });

    test('building names that day’s stone; reflection asks the same question each day', () {
      final b = buildPracticeReminders(practice: Practice.building, now: morning, minutes: 420);
      expect(b.first.body, startsWith(stoneFor(DateTime(2026, 11, 17)).name));
      expect(b[1].body, startsWith(stoneFor(DateTime(2026, 11, 18)).name));
      final r = buildPracticeReminders(practice: Practice.reflection, now: morning, minutes: 1260);
      expect(r.map((m) => m.body).toSet(), hasLength(1));
      expect(r.first.title, 'Daily reflection');
    });

    test('ids never collide: not between days, practices, or with the reading reminder', () {
      final b = buildPracticeReminders(practice: Practice.building, now: morning, minutes: 420);
      final r = buildPracticeReminders(practice: Practice.reflection, now: morning, minutes: 1260);
      final reading = reminderId(DateTime(2026, 11, 17));
      final ids = [...b, ...r].map((m) => m.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, isNot(contains(reading)));
      expect(ids.every((id) => id < 2147483647), isTrue, reason: 'Android ids are 32-bit');
    });
  });
}
