import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/plans.dart';
import 'package:berea/plans_screen.dart';
import 'package:berea/reader_screen.dart';
import 'package:berea/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(600, 1000);
final _streakCount = RegExp(
  r'\d+\s*(-|\s)?\s*days?\s+(streak|in a row)|streak\s*:?\s*\d',
  caseSensitive: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dirs = <Directory>[];
  tearDownAll(() {
    for (final d in dirs) {
      d.deleteSync(recursive: true);
    }
  });
  final nt = planById('nt-90')!;
  final days = nt.schedule();

  Future<AppState> open(Map<String, Object> prefs) async {
    final dir = Directory.systemTemp.createTempSync('berea-plans');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({
      'engine': EngineKind.ollama.name,
      'readerBook': 43,
      'tipT14Done': true,
      ...prefs,
    });
    return AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: bereaTheme(Brightness.light), home: home));
    await tester.pumpAndSettle();
  }

  void expectNoStreakCount(WidgetTester tester) {
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final text = t.data ?? t.textSpan?.toPlainText() ?? '';
      expect(_streakCount.hasMatch(text), isFalse, reason: text);
    }
  }

  testWidgets('starting a plan shows today\'s portion; ticks persist and Read next moves on', (
    tester,
  ) async {
    final state = (await tester.runAsync(() => open({})))!;
    await pump(tester, PlansScreen(state: state));
    expect(find.text('CHOOSE A PLAN'), findsOneWidget);
    await tester.tap(find.text(nt.name));
    await tester.pumpAndSettle();

    final first = days[0].first;
    expect(find.text(readingLabel(days[0])), findsOneWidget);
    expect(find.text('Read ${first.label}'), findsOneWidget);
    expect(find.text('0 of ${nt.chapters} chapters'), findsOneWidget);
    expect(find.text(plansCaption), findsOneWidget);
    expect(find.text('START ANOTHER'), findsOneWidget);
    expect(find.text('The Gospels in 30 days'), findsOneWidget);
    expect(find.text('89 chapters · about 3 a day'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, first.label));
    await tester.pumpAndSettle();
    expect(state.study.planChaptersDone(nt.id), {first});
    expect(find.text('1 of ${nt.chapters} chapters'), findsOneWidget);
    final second = days[0][1];
    expect(find.text('Read ${second.label}'), findsOneWidget);

    final opened = state.openReaderRequest.value;
    await tester.tap(find.text('Read ${second.label}'));
    expect((state.readerBook, state.readerChapter), (second.book.id, second.chapter));
    expect(state.openReaderRequest.value, opened + 1);
    expectNoStreakCount(tester);
  });

  testWidgets('a missed day offers Catch up, and nothing counts a streak', (tester) async {
    final start = DateTime.now().subtract(const Duration(days: 2));
    final state = (await tester.runAsync(
      () => open({'activePlan': nt.id, 'activePlanStart': start.toIso8601String()}),
    ))!;
    state.study.setPlanDay(nt.id, 1, true);
    await pump(tester, PlansScreen(state: state));

    expect(find.textContaining('DAY 3 OF 90'), findsOneWidget);
    expect(find.text(readingLabel(days[2])), findsOneWidget);
    expect(find.text('One earlier day to catch up'), findsOneWidget);
    expect(find.text(readingLabel(days[1])), findsOneWidget);
    expect(find.byIcon(Icons.check), findsWidgets, reason: 'day 1 is ticked in the week row');
    expectNoStreakCount(tester);

    await tester.tap(find.text('Catch up'));
    expect((state.readerBook, state.readerChapter), (days[1].first.book.id, days[1].first.chapter));
  });

  testWidgets('starting another plan asks before replacing the running one', (tester) async {
    final state = (await tester.runAsync(
      () => open({'activePlan': nt.id, 'activePlanStart': DateTime.now().toIso8601String()}),
    ))!;
    await pump(tester, PlansScreen(state: state));
    await tester.tap(find.text('The Gospels in 30 days'));
    await tester.pumpAndSettle();
    expect(find.text('Start The Gospels in 30 days?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state.activePlan, nt);

    await tester.tap(find.text('The Gospels in 30 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pumpAndSettle();
    expect(state.activePlan!.id, 'gospels-30');
  });

  testWidgets('today\'s card names the portion and opens the next unread chapter', (tester) async {
    final state = (await tester.runAsync(
      () => open({'activePlan': nt.id, 'activePlanStart': DateTime.now().toIso8601String()}),
    ))!;
    state.study.setPlanChapter(nt.id, days[0].first, true);
    await pump(tester, ReaderScreen(state: state));
    expect(find.text('Today: ${readingLabel(days[0])}'), findsOneWidget);
    expect(find.text('${nt.name} · day 1 of 90'), findsOneWidget);

    final plans = state.openPlansRequest.value;
    await tester.tap(find.text('Open Plans'));
    expect(state.openPlansRequest.value, plans + 1);

    await tester.tap(find.text('Today: ${readingLabel(days[0])}'));
    await tester.pumpAndSettle();
    expect((state.readerBook, state.readerChapter), (days[0][1].book.id, days[0][1].chapter));
  });
}
