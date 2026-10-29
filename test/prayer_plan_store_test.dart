import 'dart:io';

import 'package:berea/backup.dart';
import 'package:berea/prayer_plan_store.dart';
import 'package:berea/prayer_store.dart';
import 'package:berea/study_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late StudyStore study;
  late PrayerStore prayers;
  late PrayerPlanStore plans;
  var clock = DateTime(2026, 10, 29, 9);

  setUp(() {
    clock = DateTime(2026, 10, 29, 9);
    study = StudyStore(sqlite3.openInMemory());
    prayers = PrayerStore(study.db, now: () => clock);
    plans = PrayerPlanStore(study.db, now: () => clock);
  });

  test('a plan starts at day 1 and moves on one Amen at a time', () {
    plans.start('work-7');
    expect(plans.running().single.planId, 'work-7');
    expect(plans.currentDay('work-7', 7), 1);

    plans.pray('work-7', 1, 7);
    plans.pray('work-7', 1, 7);
    expect(plans.daysPrayed('work-7'), {1});
    expect(plans.currentDay('work-7', 7), 2);
  });

  test('a missed day is picked up where the reader was, with no streak to lose', () {
    plans.start('work-7');
    plans.pray('work-7', 1, 7);
    clock = clock.add(const Duration(days: 3));
    expect(plans.currentDay('work-7', 7), 2);
  });

  test('the last day finishes the plan and takes it off the running list', () {
    plans.start('exam-5');
    for (var d = 1; d <= 5; d++) {
      plans.pray('exam-5', d, 5);
    }
    expect(plans.currentDay('exam-5', 5), isNull);
    expect(plans.running(), isEmpty);
    expect(plans.run('exam-5')!.finished, isNotNull);
  });

  test('starting a plan again clears its days', () {
    plans.start('work-7');
    plans.pray('work-7', 1, 7);
    plans.start('work-7');
    expect(plans.daysPrayed('work-7'), isEmpty);
    expect(plans.run('work-7')!.fasting, isFalse);
  });

  test('fasting is off until the reader turns it on', () {
    plans.start('work-7');
    expect(plans.run('work-7')!.fasting, isFalse);
    plans.setFasting('work-7', true);
    expect(plans.run('work-7')!.fasting, isTrue);
  });

  test('a linked prayer is unlinked when the prayer is deleted', () {
    final id = prayers.add(title: 'Wisdom in the new job');
    plans.start('work-7');
    plans.linkPrayer('work-7', id);
    expect(plans.run('work-7')!.prayerId, id);
    prayers.delete(id);
    expect(plans.run('work-7')!.prayerId, isNull);
  });

  test('Pray what you read ticks a day of a reading plan once', () {
    plans.prayReading('nt-90', 3);
    plans.prayReading('nt-90', 3);
    expect(plans.readingPrayed('nt-90'), {3});
    study.clearPlan('nt-90');
    expect(plans.readingPrayed('nt-90'), isEmpty);
  });

  test('a prayer keeps the topic it is prayed with', () {
    final id = prayers.add(title: 'Daniel\'s interview', topic: 'job-search');
    expect(prayers.prayer(id)!.topic, 'job-search');
    prayers.edit(id, title: 'Daniel\'s interview', topic: null);
    expect(prayers.prayer(id)!.topic, isNull);
  });

  test('plans, days and topics round trip in a backup', () async {
    final id = prayers.add(title: 'For Sam', topic: 'healing');
    plans.start('work-7');
    plans.pray('work-7', 1, 7);
    plans.setFasting('work-7', true);
    plans.linkPrayer('work-7', id);
    plans.prayReading('nt-90', 2);

    final bytes = await createBackup(study, const {}, 'correct horse');
    final target = StudyStore(sqlite3.openInMemory());
    target.importTables((await readBackup(bytes, 'correct horse')).tables);

    final back = PrayerPlanStore(target.db);
    final run = back.run('work-7')!;
    expect(run.fasting, isTrue);
    expect(run.prayerId, id);
    expect(back.daysPrayed('work-7'), {1});
    expect(back.readingPrayed('nt-90'), {2});
    expect(PrayerStore(target.db).praying().single.topic, 'healing');
  });

  test('restoring a backup made before prayer plans keeps the plans on the device', () async {
    plans.start('work-7');
    final old = await readBackup(
      File('test/fixtures/backup-v2.berea').readAsBytesSync(),
      'correct horse',
    );
    final tables = Map.of(old.tables)
      ..['prayers'] = []
      ..['prayer_days'] = [];
    study.importTables(tables);
    expect(plans.running().single.planId, 'work-7');
  });

  test('the notes export lists prayer plans and the days prayed, and nothing else of them', () {
    prayers.add(title: 'Keep me');
    plans.start('work-7');
    plans.pray('work-7', 1, 7);
    plans.setFasting('work-7', true);
    plans.prayReading('nt-90', 3);
    final md = prayersMarkdown(
      prayers,
      plans: plans,
      planTitles: {'work-7': '7 days for your work', 'nt-90': 'New Testament in 90 days'},
    );
    expect(md, contains('## Prayer plans'));
    expect(md, contains('- 7 days for your work: started 2026-10-29, prayed on 1 day, fasting on'));
    expect(md, contains('- Pray what you read, New Testament in 90 days: 1 day'));
    expect(prayersMarkdown(prayers), isNot(contains('Prayer plans')));
  });

  test('a restore that removes the linked prayer unlinks it', () {
    final id = prayers.add(title: 'Wisdom');
    plans.start('work-7');
    plans.linkPrayer('work-7', id);
    final tables = study.exportTables();
    tables['prayers'] = [];
    tables['prayer_days'] = [];
    tables['prayer_plan_runs'] = [
      {'plan_id': 'work-7', 'started': 1, 'fasting': 0, 'prayer_id': null, 'finished': null},
    ];
    study.importTables(tables);
    expect(plans.run('work-7')!.prayerId, isNull);
  });

  test('restoring prayers without the plan tables unlinks every plan prayer', () {
    final id = prayers.add(title: 'Wisdom');
    plans.start('work-7');
    plans.linkPrayer('work-7', id);
    final tables = study.exportTables()
      ..remove('prayer_plan_runs')
      ..remove('prayer_plan_days')
      ..remove('plan_prayed');
    // The backup's prayer 1 is another prayer than the one the plan linked.
    tables['prayers'] = [
      {'id': id, 'title': 'Someone else', 'for_whom': '', 'note': '', 'created': 1, 'archived': 0},
    ];
    study.importTables(tables);
    expect(plans.run('work-7')!.prayerId, isNull);
  });

  test('plan runs restored without the prayers lose their links', () {
    final id = prayers.add(title: 'Wisdom');
    plans.start('work-7');
    final tables = study.exportTables()
      ..remove('prayers')
      ..remove('prayer_days');
    tables['prayer_plan_runs'] = [
      {'plan_id': 'work-7', 'started': 1, 'fasting': 0, 'prayer_id': id, 'finished': null},
    ];
    study.importTables(tables);
    expect(plans.run('work-7')!.prayerId, isNull);
    expect(prayers.praying().single.title, 'Wisdom');
  });

  test('a plan date out of range is refused before anything changes', () {
    plans.start('work-7');
    final base = study.exportTables();
    expect(
      () => study.importTables({
        ...base,
        'prayer_plan_runs': [
          {'plan_id': 'work-7', 'started': 9223372036854775807, 'fasting': 0, 'prayer_id': null},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => study.importTables({
        ...base,
        'plan_prayed': [
          {'plan_id': 'nt-90', 'day': 1, 'done_at': -5},
        ],
      }),
      throwsFormatException,
    );
    expect(plans.running().single.planId, 'work-7');
  });

  test('a plan day with no plan is refused, and a link to a missing prayer is dropped', () {
    plans.start('work-7');
    final base = study.exportTables();
    expect(
      () => study.importTables({
        ...base,
        'prayer_plan_days': [
          {'plan_id': 'gone', 'day': 1, 'done_at': 1},
        ],
      }),
      throwsFormatException,
    );
    expect(plans.running().single.planId, 'work-7');
    study.importTables({
      ...base,
      'prayer_plan_runs': [
        {'plan_id': 'work-7', 'started': 1, 'fasting': 0, 'prayer_id': 99, 'finished': null},
      ],
    });
    expect(plans.run('work-7')!.prayerId, isNull);
  });
}
