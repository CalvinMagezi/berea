import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/reader_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea/today.dart';
import 'package:berea/today_card.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(600, 900);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dirs = <Directory>[];
  tearDownAll(() {
    for (final d in dirs) {
      d.deleteSync(recursive: true);
    }
  });

  /// A fresh app with [prefs] as what an earlier session left behind.
  Future<AppState> open(Map<String, Object> prefs) async {
    final dir = Directory.systemTemp.createTempSync('berea-bible-home');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name, ...prefs});
    return AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
  }

  Future<void> pumpReader(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.light),
        home: ReaderScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The reader title: the book and the chapter number, in the app bar.
  void expectTitle(String book, int chapter) {
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.text(book)), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text(' $chapter')), findsOneWidget);
  }

  testWidgets('a long book name fits the phone app bar on one line, chapter number whole', (
    tester,
  ) async {
    final state = await tester.runAsync(
      () => open({'readerBook': 52, 'readerChapter': 5, 'tipT14Done': true}),
    );
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.dark),
        home: ReaderScreen(state: state!),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expectTitle('1 Thessalonians', 5);

    final bar = tester.getRect(find.byType(AppBar));
    final name = find.text('1 Thessalonians');
    final number = tester.getRect(find.text(' 5'));
    expect(bar.contains(number.topLeft) && bar.contains(number.bottomRight), isTrue);
    expect(tester.getRect(name).height, number.height, reason: 'the name stays on one line');
    expect(tester.getRect(name).right, lessThanOrEqualTo(number.left));
    final search = tester.getRect(find.byTooltip('Search'));
    expect(number.right, lessThanOrEqualTo(search.left), reason: 'clear of the actions');
  });

  testWidgets('the first ever open lands on John 1 with today\'s card and tip T14', (tester) async {
    final state = await tester.runAsync(() => open({}));
    await pumpReader(tester, state!);
    expectTitle('John', 1);
    expect(find.textContaining('VERSE OF THE DAY'), findsOneWidget);
    expect(find.text('Start a reading plan'), findsOneWidget);
    expect(find.textContaining('Where you stopped'), findsNothing);
    expect(find.byTooltip('Reading plans'), findsNothing);
    expect(state.prefs.getInt('readerBook'), 43, reason: 'a first open is remembered');

    expect(find.text(tipT14), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pump();
    expect(find.text(tipT14), findsNothing);
    expect(state.prefs.getBool('tipT14Done'), isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.textContaining('VERSE OF THE DAY'), findsNothing, reason: 'reading folds it');
    expect(find.byTooltip('Show today'), findsOneWidget);
  });

  testWidgets('a later open resumes where the reader stopped, with a marker and a folded card', (
    tester,
  ) async {
    final now = DateTime.now();
    final state = await tester.runAsync(
      () => open({
        'readerBook': 43,
        'readerChapter': 3,
        'readerVerse': 16,
        'readerReadAt': now.subtract(const Duration(days: 1)).toIso8601String(),
        'todayCardFullOn': dayKey(now),
        'tipT14Done': true,
      }),
    );
    await pumpReader(tester, state!);
    expectTitle('John', 3);
    expect(find.text('Where you stopped yesterday').hitTestable(), findsOneWidget);
    expect(find.text(tipT14), findsNothing);
    expect(find.textContaining('VERSE OF THE DAY'), findsNothing, reason: 'seen today already');

    await tester.tap(find.byTooltip('Show today'));
    await tester.pump();
    expect(find.textContaining('VERSE OF THE DAY'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Where you stopped'), findsNothing);
    expect(find.textContaining('VERSE OF THE DAY'), findsNothing, reason: 'folds after a look');
  });

  testWidgets('a jump from elsewhere starts the chapter at the top and moves the resume point', (
    tester,
  ) async {
    final state = await tester.runAsync(
      () => open({'readerBook': 43, 'readerChapter': 3, 'readerVerse': 16, 'tipT14Done': true}),
    );
    await pumpReader(tester, state!);
    double offset() => tester.widget<ListView>(find.byType(ListView)).controller!.offset;
    expect(offset(), greaterThan(0));

    state.openInReader(Ref(bookById(40), 8));
    await tester.pumpAndSettle();
    expectTitle('Matthew', 8);
    expect(offset(), 0);
    expect(find.textContaining('Where you stopped'), findsNothing);
    expect(state.prefs.getInt('readerVerse'), 1);
  });

  testWidgets('the resume marker shows once, not again when the reader is rebuilt', (tester) async {
    final state = await tester.runAsync(
      () => open({'readerBook': 43, 'readerChapter': 3, 'readerVerse': 16, 'tipT14Done': true}),
    );
    await pumpReader(tester, state!);
    expect(find.textContaining('Where you stopped'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpReader(tester, state);
    expect(find.textContaining('Where you stopped'), findsNothing);
  });

  test('the card is in full on the first look of the day, then folds', () async {
    final first = await open({'readerBook': 43});
    expect(first.todayCardFull, isTrue);
    final again = await AppState.bootstrap(supportDir: dirs.last, prefs: first.prefs);
    expect(again.todayCardFull, isFalse);
  });

  test('the marker names the day the reader stopped', () {
    final now = DateTime(2026, 10, 28, 9);
    expect(stoppedLabel(DateTime(2026, 10, 28, 1), now), 'Where you stopped');
    expect(stoppedLabel(DateTime(2026, 10, 27, 23), now), 'Where you stopped yesterday');
    expect(stoppedLabel(DateTime(2026, 10, 26), now), 'Where you stopped on Mon 26 Oct');
  });
}
