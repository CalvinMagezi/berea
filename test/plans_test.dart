
import 'package:berea/plans.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bible.dart';

void main() {
  test('every plan covers each chapter exactly once with no empty days', () {
    for (final p in readingPlans) {
      final days = p.schedule();
      expect(days.length, p.days, reason: p.id);
      expect(days.every((d) => d.isNotEmpty), isTrue, reason: p.id);
      final all = days.expand((d) => d).toList();
      expect(all.length, p.chapters, reason: p.id);
      expect(all.toSet().length, all.length, reason: p.id);
    }
    expect(planById('bible-year')!.schedule().expand((d) => d).length, 1189);
  });

  test('the two psalm plans read all 150 psalms whole, five a day or one a day', () {
    final month = planById('psalms-30')!.schedule();
    expect(month.every((d) => d.length == 5), isTrue);
    expect(month.first.map((r) => r.chapter), [1, 2, 3, 4, 5]);
    expect(month.last.map((r) => r.chapter), [146, 147, 148, 149, 150]);
    final each = planById('psalms-150')!.schedule();
    expect(each.every((d) => d.length == 1), isTrue);
    expect(each[118].single.chapter, 119, reason: 'Psalm 119 is its own day, never cut');
    for (final plan in [month, each]) {
      final chapters = plan.expand((d) => d).toList();
      expect(chapters.map((r) => r.chapter), List.generate(150, (i) => i + 1));
      expect(chapters.every((r) => r.book.name == 'Psalms'), isTrue);
    }
  });

  test('the fixed chapter counts match every translation of the bundled Bible', skip: needsBibleText, () {
    final db = BibleDb.open(bibleDbFile().absolute.path);
    for (final t in db.translations()) {
      for (final b in books) {
        expect(chapterCount(b), db.chapterCount(b, translation: t), reason: '${b.name} $t');
      }
    }
  });

  test('reading labels group consecutive chapters', () {
    final refs = [
      ...RefParser.parse('Genesis 1, Genesis 2, Genesis 3'),
      ...RefParser.parse('Exodus 1'),
    ];
    expect(readingLabel(refs), 'Genesis 1-3, Exodus 1');
  });

  test('progress reads next from today, and offers the unread chapters of missed days', () {
    final plan = planById('nt-90')!;
    final days = plan.schedule();
    final done = {...days[0], days[1].first, days[2].first};
    final p = PlanProgress(plan, done, 3);
    expect(p.portion, days[2]);
    expect(p.next, days[2][1]);
    expect(p.missed, [2]);
    expect(p.catchUp, days[1].skip(1));
    expect(p.chaptersDone, days[0].length + 2);
    expect(PlanProgress(plan, {...done, ...days[2]}, 3).next, isNull);
    expect(plan.dailyLoad, 3);
  });
}
