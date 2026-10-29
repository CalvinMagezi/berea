import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/brand/prayer_icon.dart';
import 'package:berea/plans.dart';
import 'package:berea/plans_screen.dart';
import 'package:berea/reader_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

const _phone = Size(600, 1000);
final _nt = planById('nt-90')!;
final _days = _nt.schedule();

PrayerContent _content() => PrayerContent(
  topics: [
    const PrayerTopic(
      'looking',
      'Daily life',
      'Looking for work',
      ['interview'],
      [PrayerPoint('Open the right door.', 'John 3:2')],
    ),
  ],
  chapters: {
    PrayerContent.chapterKey(_days[0][0].book, _days[0][0].chapter): [
      const PrayerPoint('Line for the first chapter.', 'Matthew 1:21'),
    ],
  },
  plans: [
    const PrayerPlan('work-7', '7 days for your work', 'Work, a job, a business', true, [
      PlanDay('Ask for wisdom', 'James 1:5', [
        PrayerPoint('Give me wisdom for this week.', 'James 1:5'),
        PrayerPoint('I commit my plans to You.', 'Proverbs 16:3'),
      ]),
      PlanDay('Daily bread', 'Matthew 6:11', [
        PrayerPoint('Give us today our bread.', 'Matthew 6:11'),
      ]),
    ]),
  ],
);

void main() {
  if (needsBuiltBible case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final dirs = <Directory>[];
  tearDownAll(() {
    for (final d in dirs) {
      d.deleteSync(recursive: true);
    }
  });

  Future<AppState> open(Map<String, Object> prefs) async {
    final dir = Directory.systemTemp.createTempSync('berea-ties');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({
      'engine': EngineKind.ollama.name,
      'tipT14Done': true,
      ...prefs,
    });
    return AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      prayerContent: _content(),
    );
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: bereaTheme(Brightness.light), home: home));
    await tester.pumpAndSettle();
  }

  const john3 = {'readerBook': 43, 'readerChapter': 3};

  group('verse ties in the reader', () {
    testWidgets('only a verse with prayer points has a mark, and the mark opens Pray this verse', (
      tester,
    ) async {
      final state = (await tester.runAsync(() => open(john3)))!;
      await pump(tester, ReaderScreen(state: state));

      expect(find.byType(PrayerIcon), findsOneWidget);
      await tester.tap(find.byType(PrayerIcon));
      await tester.pumpAndSettle();
      expect(find.text('Pray John 3:2'), findsOneWidget);
      expect(find.text('One prayer point from the Word, written for Berea'), findsOneWidget);
      expect(find.text('Open the right door.'), findsOneWidget);
      expect(find.text('Add to my list'), findsOneWidget);
      expect(find.text('Pray now'), findsOneWidget);
    });

    testWidgets('a verse one of your prayers stands on says so under the verse', (tester) async {
      final state = (await tester.runAsync(() => open(john3)))!;
      state.prayers.add(title: 'Peace for Brian', verse: 'John 3:3');
      await pump(tester, ReaderScreen(state: state));

      expect(find.byType(PrayerIcon), findsNWidgets(2));
      expect(find.text('Your prayer · Peace for Brian'), findsOneWidget);
    });

    testWidgets('a marked verse keeps the same text position as an unmarked one', (tester) async {
      final state = (await tester.runAsync(() => open(john3)))!;
      await pump(tester, ReaderScreen(state: state));
      Finder verse(int n) => find.byWidgetPredicate(
        (w) => w is Text && (w.textSpan?.toPlainText().startsWith('$n ') ?? false),
      );
      // Verse 2 has prayer points in this content; verse 1 has none.
      expect(tester.getTopLeft(verse(2)).dx, tester.getTopLeft(verse(1)).dx);
      expect(tester.getSize(verse(2)).width, tester.getSize(verse(1)).width);
    });

    testWidgets('the mark is a button for a screen reader and names its verse', (tester) async {
      final handle = tester.ensureSemantics();
      final state = (await tester.runAsync(() => open(john3)))!;
      await pump(tester, ReaderScreen(state: state));
      expect(find.bySemanticsLabel('Pray John 3:2'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Pray John 3:2'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('an answered prayer keeps its mark on the verse', (tester) async {
      final state = (await tester.runAsync(() => open(john3)))!;
      final id = state.prayers.add(title: 'The interview', verse: 'John 3:3');
      state.prayers.markAnswered(id, 'I got the job.');
      await pump(tester, ReaderScreen(state: state));
      expect(find.byType(PrayerIcon), findsNWidgets(2));
      expect(find.text('Answered \u00B7 The interview'), findsOneWidget);
    });

    testWidgets('a new prayer shows on the verse at once', (tester) async {
      final state = (await tester.runAsync(() => open(john3)))!;
      await pump(tester, ReaderScreen(state: state));
      expect(find.text('Your prayer · Rain'), findsNothing);
      state.prayers.add(title: 'Rain', verse: 'John 3:4');
      await tester.pumpAndSettle();
      expect(find.text('Your prayer · Rain'), findsOneWidget);
    });

    testWidgets('Pray on a verse with no points says to pray it as it is', (tester) async {
      final state = (await tester.runAsync(() => open(john3)))!;
      await pump(tester, ReaderScreen(state: state));
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Text && (w.textSpan?.toPlainText().startsWith('1 ') ?? false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pray'));
      await tester.pumpAndSettle();
      expect(find.text('Pray John 3:1'), findsOneWidget);
      expect(
        find.text('No prayer points for this verse. Pray it as it is, or in your own words.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pray now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nicodemus', findRichText: true), findsWidgets);
    });

    testWidgets('Add to my list from the sheet opens a prayer on the verse', (tester) async {
      final state = (await tester.runAsync(() => open(john3)))!;
      await pump(tester, ReaderScreen(state: state));
      await tester.tap(find.byType(PrayerIcon));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to my list'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'John 3:2'), findsOneWidget);
    });
  });

  group('plans', () {
    testWidgets(
      'Pray what you read offers lines from the chapters ticked, and Amen ticks the day',
      (tester) async {
        final start = DateTime.now().toIso8601String();
        final state = (await tester.runAsync(
          () => open({'activePlan': _nt.id, 'activePlanStart': start}),
        ))!;
        await pump(tester, PlansScreen(state: state));
        expect(find.text('PRAY WHAT YOU READ'), findsNothing);

        state.study.setPlanChapter(_nt.id, _days[0][0], true);
        state.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('PRAY WHAT YOU READ'), findsOneWidget);
        expect(find.text('Line for the first chapter.'), findsOneWidget);
        expect(find.text('Amen ticks day 1'), findsOneWidget);

        await tester.tap(find.text('Pray these'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Amen'));
        await tester.pumpAndSettle();
        expect(state.prayerPlans.readingPrayed(_nt.id), {1});
        expect(find.text('Day 1 prayed'), findsOneWidget);
      },
    );

    testWidgets('a prayer plan is started from the list and prayed a day at a time', (
      tester,
    ) async {
      final state = (await tester.runAsync(() => open({})))!;
      await pump(tester, PlansScreen(state: state));
      expect(find.text('PRAYER PLANS'), findsOneWidget);
      await tester.tap(find.text('7 days for your work'));
      await tester.pumpAndSettle();

      expect(find.text('PRAYER PLAN · DAY 1 OF 2'), findsOneWidget);
      expect(find.text('Ask for wisdom'), findsOneWidget);
      expect(find.text('Give me wisdom for this week.'), findsOneWidget);
      expect(find.text('Fasting with this plan · off'), findsOneWidget);
      expect(find.textContaining('never water'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Fasting with this plan · on'), findsOneWidget);
      expect(find.textContaining('never water'), findsOneWidget);
      expect(state.prayerPlans.run('work-7')!.fasting, isTrue);

      await tester.tap(find.text('Amen · day 1 done'));
      await tester.pumpAndSettle();
      expect(state.prayerPlans.daysPrayed('work-7'), {1});
      expect(find.text('PRAYER PLAN · DAY 2 OF 2'), findsOneWidget);
      expect(find.text('Daily bread'), findsOneWidget);
    });

    testWidgets('finishing the last day ends the plan and leaves it off the running list', (
      tester,
    ) async {
      final state = (await tester.runAsync(() => open({})))!;
      state.prayerPlans.start('work-7');
      state.prayerPlans.pray('work-7', 1, 2);
      await pump(tester, PlansScreen(state: state));
      expect(find.textContaining('Day 2 of 2'), findsOneWidget);
      await tester.tap(find.text('Pray'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amen · day 2 done'));
      await tester.pumpAndSettle();
      expect(state.prayerPlans.running(), isEmpty);
      expect(find.textContaining('is finished'), findsOneWidget);
    });

    testWidgets('a finished plan asks before it starts again', (tester) async {
      final state = (await tester.runAsync(() => open({})))!;
      state.prayerPlans.start('work-7');
      state.prayerPlans.pray('work-7', 1, 2);
      state.prayerPlans.pray('work-7', 2, 2);
      await pump(tester, PlansScreen(state: state));
      expect(find.textContaining('Finished'), findsOneWidget);
      await tester.tap(find.text('7 days for your work'));
      await tester.pumpAndSettle();
      expect(find.text('Start 7 days for your work again?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.prayerPlans.daysPrayed('work-7'), {1, 2});
      await tester.tap(find.text('7 days for your work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start again'));
      await tester.pumpAndSettle();
      expect(state.prayerPlans.daysPrayed('work-7'), isEmpty);
      expect(find.text('PRAYER PLAN \u00B7 DAY 1 OF 2'), findsOneWidget);
    });

    testWidgets('a prayer of your own can be linked to the plan', (tester) async {
      final state = (await tester.runAsync(() => open({})))!;
      state.prayers.add(title: 'Wisdom in the new job');
      state.prayerPlans.start('work-7');
      await pump(tester, PlansScreen(state: state));
      await tester.tap(find.text('Pray'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link a prayer of your own'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wisdom in the new job'));
      await tester.pumpAndSettle();
      expect(find.text('Your prayer today'), findsOneWidget);
      expect(state.prayerPlans.run('work-7')!.prayerId, isNotNull);
    });

    testWidgets('stopping a plan asks first and removes its days only', (tester) async {
      final state = (await tester.runAsync(() => open({})))!;
      state.prayers.add(title: 'Keep me');
      state.prayerPlans.start('work-7');
      state.prayerPlans.pray('work-7', 1, 2);
      await pump(tester, PlansScreen(state: state));
      await tester.tap(find.text('Pray'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plan options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop plan'));
      await tester.pumpAndSettle();
      expect(find.text('Stop 7 days for your work?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop plan'));
      await tester.pumpAndSettle();
      expect(state.prayerPlans.running(), isEmpty);
      expect(state.prayerPlans.daysPrayed('work-7'), isEmpty);
      expect(state.prayers.praying().single.title, 'Keep me');
    });
  });
}
