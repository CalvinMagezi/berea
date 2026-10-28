import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/reader_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea/today.dart';
import 'package:berea/today_card.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(number.height, greaterThan(0));

    // The whole title shrinks to its floor before the name is cut, and only below the floor.
    const full = 22.0;
    const floor = full * 0.8;
    RenderParagraph paragraph(String text) =>
        tester.renderObject(find.descendant(of: find.byType(AppBar), matching: find.text(text)));
    final long = paragraph('1 Thessalonians');
    expect(long.text.style!.fontSize, closeTo(floor, 0.01));
    expect(paragraph(' 5').text.style!.fontSize, closeTo(floor, 0.01), reason: 'scaled together');
    var scaledWhole = 0;
    var fullSize = 0;
    for (final b in books) {
      state.setReader(b, 1);
      await tester.pump();
      final p = paragraph(b.name);
      final size = p.text.style!.fontSize!;
      expect(size, inInclusiveRange(floor - 0.01, full), reason: b.name);
      if (p.didExceedMaxLines) expect(size, closeTo(floor, 0.01), reason: '${b.name} cut early');
      if (size > floor + 0.01 && size < full) scaledWhole++;
      if (size == full) fullSize++;
    }
    expect(scaledWhole, greaterThan(0), reason: 'some names fit by scaling alone');
    expect(fullSize, greaterThan(0), reason: 'short names keep the full size');
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

  testWidgets('left open past midnight, the folded card opens on the new day', (tester) async {
    final now = DateTime.now();
    final state = await tester.runAsync(
      () => open({
        'readerBook': 43,
        'readerChapter': 3,
        'todayCardFullOn': dayKey(now),
        'tipT14Done': true,
      }),
    );
    await pumpReader(tester, state!);
    expect(find.textContaining('VERSE OF THE DAY'), findsNothing, reason: 'seen today already');

    // The clock in a test does not move, so the remembered day stands in for yesterday's.
    await state.prefs.setString('todayCardFullOn', 'yesterday');
    await tester.pump(const Duration(hours: 24, seconds: 2));
    expect(find.textContaining('VERSE OF THE DAY'), findsOneWidget);
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

  testWidgets('the folded card shortens book names at phone width, as the board does', (
    tester,
  ) async {
    final now = DateTime.now();
    final state = await tester.runAsync(
      () => open({
        'readerBook': 43,
        'todayCardFullOn': dayKey(now),
        'tipT14Done': true,
        'activePlan': 'nt-90',
        'activePlanStart': now.toIso8601String(),
      }),
    );
    final daily = verseOfTheDay(state!.db, now);
    String line() => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((t) => t.text.toPlainText())
        .firstWhere((t) => t.startsWith('Today ·'));

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.light),
        home: ReaderScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(line(), 'Today · ${shortLabel(daily)}');
    expect(find.text('Matt 1-3'), findsOneWidget);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(line(), 'Today · ${daily.label}');
    expect(find.text('Matthew 1-3'), findsOneWidget);
  });

  test('every book has a short name', () {
    expect(bookAbbreviations, hasLength(books.length));
    expect(shortLabel(RefParser.parse('2 Corinthians 4:18').first), '2 Cor 4:18');
    expect(shortLabel(RefParser.parse('Song of Solomon 2:4').first), 'Song 2:4');
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
