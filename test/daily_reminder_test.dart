import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/daily_reminder.dart';
import 'package:berea/prayer_today.dart';
import 'package:berea/reminder_settings.dart';
import 'package:berea/theme.dart';
import 'package:berea/today.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

class FakePlatform implements ReminderPlatform {
  var granted = true;
  var failToSchedule = false;
  var enabled = true;
  var asked = 0;
  List<ReminderMessage> scheduled = [];

  @override
  Future<bool> allowed() async => enabled;

  @override
  Future<bool> requestPermission() async {
    asked++;
    enabled = granted;
    return granted;
  }

  @override
  Future<void> replaceAll(List<ReminderMessage> messages) async {
    if (failToSchedule) throw StateError('no such time zone');
    scheduled = messages;
  }
}

Ref _verse(DateTime day) => Ref(bookById(23), 41, 1 + day.day % 10);

void main() {
  final verseText = {for (var v = 1; v <= 10; v++) 'Isaiah 41:$v': 'Verse text $v.'};

  List<ReminderMessage> build(DateTime now, ReminderSettings s, {bool prayer = true}) =>
      buildReminders(
        now: now,
        settings: s,
        verseOn: _verse,
        textOf: (v) => verseText[v.label] ?? '',
        prayerOn: (d) => prayer
            ? TodayPrayer(PrayerPoint('Prayer for day ${d.day}.', _verse(d).label), 'x')
            : null,
      );

  group('building the notifications', () {
    final morning = DateTime(2026, 10, 29, 5);

    test('off schedules nothing', () {
      expect(build(morning, const ReminderSettings()), isEmpty);
    });

    test('fourteen days from today at the chosen time, each with its own verse and prayer', () {
      final out = build(morning, const ReminderSettings(on: true));
      expect(out.length, reminderDaysAhead);
      expect(out.first.when, DateTime(2026, 10, 29, 6, 30));
      expect(out[1].when, DateTime(2026, 10, 30, 6, 30));
      expect(out.first.title, 'Isaiah 41:10');
      expect(out.first.body, 'Verse text 10.\nPray: Prayer for day 29.');
      expect(out[1].body, contains('Prayer for day 30.'));
      expect({for (final m in out) m.id}.length, reminderDaysAhead);
    });

    test('every day is at the clock time chosen, never shifted by an hour', () {
      final out = build(morning, const ReminderSettings(on: true));
      expect(out.every((m) => m.when.hour == 6 && m.when.minute == 30), isTrue);
    });

    test('a time already past today starts tomorrow', () {
      final out = build(DateTime(2026, 10, 29, 9), const ReminderSettings(on: true));
      expect(out.first.when, DateTime(2026, 10, 30, 6, 30));
      expect(out.length, reminderDaysAhead);
    });

    test('the same day has the same id, so a new schedule replaces the old', () {
      final a = build(morning, const ReminderSettings(on: true));
      final b = build(DateTime(2026, 10, 29, 5, 30), const ReminderSettings(on: true));
      expect(b.first.id, a.first.id);
    });

    test('reference only keeps the words off the lock screen', () {
      final out = build(morning, const ReminderSettings(on: true, referenceOnly: true));
      expect(out.first.title, 'Verse of the day');
      expect(out.first.body, 'Isaiah 41:10');
      expect(out.every((m) => !m.body.contains('Pray')), isTrue);
    });

    test('a day with no prayer line still shows the verse', () {
      final out = build(morning, const ReminderSettings(on: true), prayer: false);
      expect(out.first.body, 'Verse text 10.');
    });

    test('times read as a clock does', () {
      expect(reminderTimeLabel(390), '6:30');
      expect(reminderTimeLabel(480), '8:00');
      expect(reminderTimeLabel(5), '0:05');
    });
  });

  final why = needsBuiltBible;
  if (why != null) {
    test('the settings tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final dirs = <Directory>[];
  tearDownAll(() {
    for (final d in dirs) {
      d.deleteSync(recursive: true);
    }
  });

  Future<AppState> open({Map<String, Object> prefs = const {}, FakePlatform? platform}) async {
    final dir = Directory.systemTemp.createTempSync('berea-reminder');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name, ...prefs});
    final s = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      prayerContent: PrayerContent.empty,
    );
    s.reminderPlatform = platform;
    return s;
  }

  group('turning it on and off', () {
    test('asking is refused: nothing is saved or scheduled', () async {
      final p = FakePlatform()..granted = false;
      final s = await open(platform: p);
      expect(await s.turnOnReminder(390, referenceOnly: false), isFalse);
      expect(s.reminder.on, isFalse);
      expect(p.scheduled, isEmpty);
    });

    test('allowed: it is saved and the next days are scheduled', () async {
      final p = FakePlatform();
      final s = await open(platform: p);
      expect(await s.turnOnReminder(420, referenceOnly: true), isTrue);
      expect(s.reminder.on, isTrue);
      expect(s.reminder.minutes, 420);
      expect(s.reminder.referenceOnly, isTrue);
      expect(p.scheduled.length, reminderDaysAhead);
      expect(p.scheduled.first.when.hour, 7);
    });

    test('turning it off drops everything scheduled', () async {
      final p = FakePlatform();
      final s = await open(platform: p);
      await s.turnOnReminder(390, referenceOnly: false);
      await s.turnOffReminder();
      expect(s.reminder.on, isFalse);
      expect(p.scheduled, isEmpty);
    });

    test('opening Berea again keeps the schedule going', () async {
      final p = FakePlatform();
      final s = await open(prefs: {'reminderOn': true, 'reminderMinutes': 390}, platform: p);
      await s.syncReminder();
      expect(p.scheduled.length, reminderDaysAhead);
    });

    test('notifications turned off in the system drop the schedule', () async {
      final p = FakePlatform()..enabled = false;
      final s = await open(prefs: {'reminderOn': true}, platform: p);
      p.scheduled = [ReminderMessage(1, DateTime(2030), 'x', 'y')];
      await s.syncReminder();
      expect(p.scheduled, isEmpty);
    });

    test('without a platform nothing happens and nothing is saved', () async {
      final s = await open();
      expect(await s.turnOnReminder(390, referenceOnly: false), isFalse);
      await s.syncReminder();
      expect(s.reminder.on, isFalse);
    });

    test('a failure while scheduling leaves it off and says so', () async {
      final p = FakePlatform()..failToSchedule = true;
      final s = await open(platform: p);
      expect(await s.turnOnReminder(390, referenceOnly: false), isFalse);
      expect(s.reminder.on, isFalse);
      await s.syncReminder();
    });

    test(
      'the prayer in a notification is the day\'s line, never one of the reader\'s own',
      () async {
        final p = FakePlatform();
        final s = await open(platform: p);
        final now = DateTime.now();
        s.prayerContent = PrayerContent(
          topics: [
            const PrayerTopic(
              'healing',
              'Home and health',
              'Sickness and healing',
              ['sick', 'surgery'],
              [PrayerPoint('Heal the sick.', 'Psalms 23:1')],
            ),
          ],
          daily: {
            for (var i = 0; i < 16; i++)
              verseOfTheDay(s.db, DateTime(now.year, now.month, now.day + i)).label:
                  'Line for the day.',
          },
        );
        s.prayers.add(title: "Sam's surgery on Friday", forWhom: 'Sam', note: 'sick and afraid');
        await s.turnOnReminder(390, referenceOnly: false);
        expect(p.scheduled.length, reminderDaysAhead);
        for (final m in p.scheduled) {
          expect(m.body, contains('Pray: Line for the day.'));
          expect(m.title + m.body, isNot(contains('Sam')));
          expect(m.body, isNot(contains('surgery')));
        }
      },
    );
  });

  group('the settings section', () {
    Future<void> pump(WidgetTester tester, AppState s, List<String> said) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: bereaTheme(Brightness.light),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: s,
              builder: (_, _) => ReminderSettingsSection(state: s, onMessage: said.add),
            ),
          ),
        ),
      );
    }

    testWidgets('hidden where notifications cannot be scheduled', (tester) async {
      final s = (await tester.runAsync(open))!;
      await pump(tester, s, []);
      expect(find.text('Daily prayer'), findsNothing);
    });

    testWidgets('the switch opens the sheet, and Turn on schedules', (tester) async {
      final p = FakePlatform();
      final s = (await tester.runAsync(() => open(platform: p)))!;
      await pump(tester, s, []);
      expect(find.text('Daily prayer'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Your device will ask to allow notifications from Berea.'), findsOneWidget);
      await tester.tap(find.text('7:00'));
      await tester.tap(find.text('Reference only'));
      await tester.pump();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(p.asked, 1);
      expect(s.reminder.on, isTrue);
      expect(s.reminder.minutes, 420);
      expect(find.text('At 7:00'), findsOneWidget);
      expect(find.text('The reference only on the lock screen'), findsOneWidget);
    });

    testWidgets('a refusal says how to allow notifications and changes nothing', (tester) async {
      final said = <String>[];
      final p = FakePlatform()..granted = false;
      final s = (await tester.runAsync(() => open(platform: p)))!;
      await pump(tester, s, said);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(said, [deniedMessage]);
      expect(s.reminder.on, isFalse);
    });

    testWidgets('Change moves the time', (tester) async {
      final p = FakePlatform();
      final s = (await tester.runAsync(
        () => open(prefs: {'reminderOn': true, 'reminderMinutes': 390}, platform: p),
      ))!;
      await pump(tester, s, []);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8:00'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(s.reminder.minutes, 480);
      expect(p.scheduled.first.when.hour, 8);
    });
  });
}
