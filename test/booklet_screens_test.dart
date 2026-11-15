import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/booklet_screens.dart';
import 'package:berea/booklets.dart';
import 'package:berea/notes_screen.dart';
import 'package:berea/plans_screen.dart';
import 'package:berea/prayer_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

const _phone = Size(600, 1000);
final _streakCount = RegExp(
  r'\d+\s*(-|\s)?\s*days?\s+(streak|in a row)|streak\s*:?\s*\d',
  caseSensitive: false,
);

void main() {
  if (needsBibleText case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureBereaDbAssets();
  final dirs = <Directory>[];
  tearDownAll(() {
    for (final d in dirs) {
      d.deleteSync(recursive: true);
    }
  });

  Future<AppState> open() async {
    final dir = Directory.systemTemp.createTempSync('berea-booklets');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({'readerBook': 43, 'tipT14Done': true});
    return AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: bereaTheme(Brightness.light), home: home));
    await tester.pumpAndSettle();
  }

  Finder rich(String text) => find.textContaining(text, findRichText: true);

  /// Scrolls the screen's list until [what] is built and on screen; long text sits above it.
  Future<void> reveal(WidgetTester tester, Finder what) =>
      tester.scrollUntilVisible(what, 300, scrollable: find.byType(Scrollable).first);

  testWidgets('the app loads both booklets from its assets', (tester) async {
    final s = (await tester.runAsync(open))!;
    expect(s.booklets.map((b) => b.id), ['inner-city', 'three-ways']);
  });

  testWidgets(
    'blocks draw their marks: bold, italic, a boxed passage, a quotation and its Bible button',
    (tester) async {
      Ref? opened;
      await pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: BookletBlocks(
              parseBookletBlocks(
                '### A part\n#### A label\nPlain with **bold** and *italic*.\n- one\n- two\n'
                '::: callout The blind spot\nBox text.\n:::\n'
                '> A quoted line.\n> — Psalm 51:10\n::: berea\nA note from Berea.\n:::\n',
              ),
              onOpenRef: (r) => opened = r,
            ),
          ),
        ),
      );
      expect(find.text('A part'), findsOneWidget);
      expect(find.text('A LABEL'), findsOneWidget);
      expect(rich('Plain with bold and italic.'), findsOneWidget);
      expect(find.text('THE BLIND SPOT'), findsOneWidget);
      expect(rich('Box text.'), findsOneWidget);
      expect(find.text('Psalm 51:10'), findsOneWidget);
      expect(find.text('A note from Berea.'), findsOneWidget);
      // No stray marks are left on screen.
      expect(find.textContaining('**', findRichText: true), findsNothing);
      expect(find.textContaining('::: ', findRichText: true), findsNothing);

      await tester.tap(find.byTooltip('Open Psalms 51:10 in the Bible'));
      expect(opened?.label, 'Psalms 51:10');
    },
  );

  testWidgets(
    'Plans lists both booklets; starting one shows a card that moves on as sections are read',
    (tester) async {
      final s = (await tester.runAsync(open))!;
      await pump(tester, PlansScreen(state: s));
      expect(find.text('CHOOSE A PLAN'), findsOneWidget);
      expect(find.text('BOOKLETS'), findsOneWidget);
      expect(find.text('Building the Inner City of God'), findsOneWidget);
      expect(find.text('Three Ways We Fall'), findsOneWidget);
      expect(find.text('11 sections · about 12 minutes'), findsOneWidget);

      // The tile opens the booklet's contents, with its label and counted facts.
      await tester.tap(find.text('Three Ways We Fall'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sin, iniquity and transgression, with reflections and a prayer of confession'),
        findsOneWidget,
      );
      expect(find.text(bookletLabel), findsOneWidget);
      expect(find.text('0 of 11 sections read'), findsOneWidget);

      await tester.tap(find.text('Start reading'));
      await tester.pumpAndSettle();
      expect(find.text('1 OF 11'), findsOneWidget);
      expect(s.bookletReading.isStarted('three-ways'), isTrue);

      // Reading a section: mark it, go to the next, come back out to Plans.
      await tester.tap(find.text('Mark this section read'));
      await tester.pumpAndSettle();
      expect(s.bookletReading.isRead('three-ways', 'cover'), isTrue);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2 OF 11'), findsOneWidget);
      expect(find.text('One word is not enough'), findsOneWidget);
      await reveal(tester, find.text('Previous'));
      expect(find.text('Previous'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('THREE WAYS WE FALL · SECTION 2 OF 11'), findsOneWidget);
      expect(find.text('One word is not enough'), findsOneWidget);
      expect(find.text('1 of 11 sections'), findsOneWidget);
      expect(find.text('Building the Inner City of God'), findsOneWidget, reason: 'still offered');
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final text = t.data ?? t.textSpan?.toPlainText() ?? '';
        expect(_streakCount.hasMatch(text), isFalse, reason: text);
      }
    },
  );

  testWidgets(
    'a running Bible plan and a running booklet sit together, neither replacing the other',
    (tester) async {
      final s = (await tester.runAsync(open))!;
      await pump(tester, PlansScreen(state: s));
      await tester.tap(find.text('The Gospels in 30 days'));
      await tester.pumpAndSettle();
      s.bookletReading.start('inner-city');
      await tester.pumpAndSettle();
      expect(find.textContaining('THE GOSPELS IN 30 DAYS · DAY 1 OF 30'), findsOneWidget);
      expect(find.text('BUILDING THE INNER CITY OF GOD · SECTION 1 OF 8'), findsOneWidget);
      expect(s.activePlan?.id, 'gospels-30');
      // Stopping the booklet leaves the Bible plan running.
      s.bookletReading.stop('inner-city');
      await tester.pumpAndSettle();
      expect(s.activePlan?.id, 'gospels-30');
    },
  );

  testWidgets('with no booklets there is no Booklets heading', (tester) async {
    final s = (await tester.runAsync(open))!;
    s.booklets = const [];
    await pump(tester, PlansScreen(state: s));
    expect(find.text('BOOKLETS'), findsNothing);
  });

  testWidgets('a finished booklet says so and offers to start over', (tester) async {
    final s = (await tester.runAsync(open))!;
    final b = s.booklets.firstWhere((b) => b.id == 'three-ways');
    s.bookletReading.start(b.id);
    for (final section in b.sections) {
      s.bookletReading.setRead(b.id, section.id, true);
    }
    await pump(tester, PlansScreen(state: s));
    expect(find.text('THREE WAYS WE FALL · ALL READ'), findsOneWidget);
    expect(find.text('Every section is read.'), findsOneWidget);
    expect(find.text('11 of 11 sections'), findsOneWidget);
    await tester.tap(find.byTooltip('Booklet options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();
    expect(find.text('THREE WAYS WE FALL · SECTION 1 OF 11'), findsOneWidget);
  });

  testWidgets(
    'Prayer links to the booklet prayers, shown whole and apart from the person\'s list',
    (tester) async {
      final s = (await tester.runAsync(open))!;
      await pump(
        tester,
        PrayerScreen(
          store: s.prayers,
          passage: (_) => const [],
          translation: () => 'BSB',
          onBookletPrayers: () {},
        ),
      );
      expect(find.text('Prayers from booklets'), findsOneWidget);
      // Nothing was added to the person's own list.
      expect(s.prayers.isEmpty, isTrue);

      await pump(tester, BookletPrayersScreen(state: s));
      expect(rich(bookletPrayersSelector), findsOneWidget);
      expect(find.text('Prayer: A Prayer of Confession'), findsOneWidget);
      expect(find.text('Simple Everyday Practice'), findsOneWidget);
      await tester.tap(find.text('Prayer: A Prayer of Confession'));
      await tester.pumpAndSettle();
      expect(find.text(bookletLabel), findsOneWidget);
      expect(find.text('II. I have sinned'), findsOneWidget);
      expect(find.text('Pause. Name the person, the word, the omission.'), findsOneWidget);
      await reveal(tester, find.text('Read it in the booklet'));
      expect(find.text('Read it in the booklet'), findsOneWidget);
      expect(s.prayers.isEmpty, isTrue, reason: 'reading a booklet prayer writes nothing');
    },
  );

  testWidgets('Prayer without the callback shows no booklet row', (tester) async {
    final s = (await tester.runAsync(open))!;
    await pump(
      tester,
      PrayerScreen(store: s.prayers, passage: (_) => const [], translation: () => 'BSB'),
    );
    expect(find.text('Prayers from booklets'), findsNothing);
  });

  testWidgets(
    'Add to a notebook copies the booklet in once, and says so when it is already there',
    (tester) async {
      final s = (await tester.runAsync(open))!;
      final nb = s.notebooks.createNotebook('Confession');
      final three = s.booklets.firstWhere((b) => b.id == 'three-ways');
      await pump(tester, BookletScreen(state: s, booklet: three));

      Future<void> add() async {
        await tester.tap(find.byTooltip('Booklet options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add to a notebook'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confession'));
        await tester.pump();
      }

      await add();
      // The booklet is read on a background isolate; wait for it to land.
      await tester.runAsync(() async {
        for (var i = 0; i < 200 && s.notebooks.sources(nb).isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pumpAndSettle();
      final source = s.notebooks.sources(nb).single;
      expect(source.title, 'Three Ways We Fall');
      expect(source.origin, three.origin);
      expect(s.notebooks.sourceText(source.id), contains('Father, I have sinned.'));
      expect(find.text('Added to Confession.'), findsOneWidget);

      await add();
      await tester.pumpAndSettle();
      expect(find.text('Three Ways We Fall is already in Confession.'), findsOneWidget);
      expect(s.notebooks.sources(nb), hasLength(1), reason: 'no second copy');
    },
  );

  testWidgets('Notes lists the booklets under the notebooks and opens one', (tester) async {
    final s = (await tester.runAsync(open))!;
    await pump(tester, NotesScreen(state: s));
    expect(find.text('BOOKLETS'), findsOneWidget);
    await tester.tap(find.text('Building the Inner City of God'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 8 sections read'), findsOneWidget);
    expect(find.textContaining('Introduction: Why Build an Inner City for God?'), findsOneWidget);
    await reveal(tester, find.textContaining('Section 7: Visual Blueprint Summary'));
    expect(find.textContaining('Section 7: Visual Blueprint Summary'), findsOneWidget);
  });
}
