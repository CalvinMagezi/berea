import 'dart:io';
import 'dart:math';

import 'package:berea/app_state.dart';
import 'package:berea/home_shell.dart';
import 'package:berea/reader_screen.dart';
import 'package:berea/selection_bar.dart';
import 'package:berea/study_button.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

const _mac = Size(1280, 800);

// Wide enough for the reader's chapter bar in the test font, which is wider than real type.
const _chapterBarWidth = 600.0;

/// A phone the chapter bar fits in the test font, for flows that end with the selection cleared.
const _roomyPhone = Size(_chapterBarWidth, 900);

/// Tall enough that verse 3 of John 3 sits above the selection card in the test font.
const _tallPhone = Size(_chapterBarWidth, 1600);
const _phones = [Size(360, 800), Size(412, 915)];
const _phoneActions = ['Highlight', 'Note', 'Pray', 'Ask', 'More'];

/// An action on the selection bar.
Finder action(String label) =>
    find.descendant(of: find.byType(SelectionBar), matching: find.bySemanticsLabel(label));

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

  /// A fresh app open at John 3, with the reader tip already dismissed.
  Future<AppState> open() async {
    final dir = Directory.systemTemp.createTempSync('berea-selection-bar');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({
      'engine': EngineKind.ollama.name,
      'readerBook': 43,
      'readerChapter': 3,
      'tipT14Done': true,
    });
    return AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      prayerContent: PrayerContent.empty,
    );
  }

  /// Opens the shell at [size] with verses [verses] of John 3 selected. The verses are tapped at
  /// [_chapterBarWidth] at least, since the chapter bar overflows a narrow phone in the test font.
  Future<AppState> pumpSelected(WidgetTester tester, Size size, List<int> verses) async {
    final state = (await tester.runAsync(open))!;
    tester.view.physicalSize = Size(max(size.width, _chapterBarWidth), size.height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.light),
        home: HomeShell(state: state),
      ),
    );
    await tester.pumpAndSettle();
    for (final n in verses) {
      final verse = find.byWidgetPredicate(
        (w) => w is Text && (w.textSpan?.toPlainText().startsWith('$n ') ?? false),
      );
      await tester.tap(verse.first);
      await tester.pump();
    }
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('selecting a verse shows Highlight, Note, Pray, Ask and More in order', (
    tester,
  ) async {
    await pumpSelected(tester, _phones.first, [1]);
    expect(find.byType(SelectionBar), findsOneWidget);
    expect(find.text('John 3:1'), findsOneWidget);
    final xs = [for (final a in _phoneActions) tester.getCenter(action(a)).dx];
    expect(xs, [...xs]..sort());
    for (final a in _phoneActions) {
      final size = tester.getSize(action(a));
      expect(size.width >= 48 && size.height >= 48, isTrue, reason: '$a is a 48 px target');
    }
    expect(action('Words'), findsNothing, reason: 'Words sits under More');
  });

  for (final size in _phones) {
    testWidgets('the card floats 24 px above the bar and the raised Study button at $size', (
      tester,
    ) async {
      await pumpSelected(tester, size, [1]);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final card = tester.getRect(find.byType(SelectionBar));
      final study = tester.getRect(find.byType(StudyButton));
      final barTop = tester.getRect(find.byType(ReaderScreen)).bottom;
      expect(study.top, greaterThanOrEqualTo(barTop), reason: 'the bar holds the raised button');
      expect(card.bottom, lessThanOrEqualTo(barTop - selectionBarGap));
      expect(card.bottom, lessThan(study.top));
    });
  }

  testWidgets('Pray opens the prayer sheet with the selected verses filled in', (tester) async {
    await pumpSelected(tester, _roomyPhone, [1, 2]);
    expect(find.text('John 3:1-2'), findsOneWidget);
    expect(find.text('2 verses'), findsOneWidget);
    await tester.tap(action('Pray'));
    await tester.pumpAndSettle();
    expect(find.text('What are you praying for?'), findsOneWidget);
    final verse = find.widgetWithText(TextField, 'A verse to pray (optional)');
    expect(tester.widget<TextField>(verse).controller!.text, 'John 3:1-2');
  });

  testWidgets('More holds Words, Commentary, Study page, Copy and Share; Copy copies the verse', (
    tester,
  ) async {
    final state = await pumpSelected(tester, _roomyPhone, [1]);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    final ys = [
      for (final m in ['Words', 'Commentary', 'Study page', 'Copy', 'Share'])
        tester.getCenter(find.text(m)).dy,
    ];
    expect(ys, [...ys]..sort());

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    final translation = state.settings.translation;
    final ref = Ref(bookById(43), 3, 1);
    final text = state.db.passage(ref, translation: translation).single.text;
    expect(copied, '$text\nJohn 3:1 ($translation)');
    expect(find.byType(SelectionBar), findsNothing, reason: 'the selection clears');
  });

  testWidgets('the Mac toolbar has Pray beside Words and Commentary', (tester) async {
    await pumpSelected(tester, _mac, [1]);
    expect(tester.takeException(), isNull);
    final names = ['Highlight', 'Note', 'Pray', 'Ask', 'Words', 'Commentary', 'More'];
    final xs = [for (final a in names) tester.getCenter(action(a)).dx];
    expect(xs, [...xs]..sort());
    final bar = tester.getRect(find.byType(SelectionBar));
    expect(bar.top, lessThan(_mac.height / 2), reason: 'a toolbar over the text, not a card');

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    for (final m in ['Study page', 'Copy', 'Share']) {
      expect(find.text(m), findsOneWidget);
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    expect(find.byType(SelectionBar), findsNothing);
  });

  testWidgets('the Mac toolbar fits the reader beside the sidebar in a narrow window', (
    tester,
  ) async {
    await pumpSelected(tester, const Size(wideLayoutBreakpoint, 800), [1]);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    final reader = tester.getRect(find.byType(ReaderScreen));
    final bar = tester.getRect(find.byType(SelectionBar));
    expect(bar.left >= reader.left && bar.right <= reader.right, isTrue);
  });

  test('verses with gaps are labelled run by run', () {
    final john = bookById(43);
    expect(verseRuns([5, 1, 2]), [(1, 2), (5, 5)]);
    expect(versesLabel(john, 3, [1, 5]), 'John 3:1, 5');
    expect(versesLabel(john, 3, [1, 2, 5, 7, 8]), 'John 3:1-2, 5, 7-8');
    expect(versesLabel(john, 3, [3, 4]), 'John 3:3-4');
  });

  testWidgets('a selection with a gap copies only the chosen verses and asks before Pray', (
    tester,
  ) async {
    final state = await pumpSelected(tester, _tallPhone, [1, 3]);
    expect(find.text('John 3:1, 3'), findsOneWidget);
    expect(find.text('2 verses'), findsOneWidget);

    await tester.tap(action('Pray'));
    await tester.pumpAndSettle();
    expect(find.text('What are you praying for?'), findsNothing);
    expect(find.textContaining('Pray works on verses next to each other.'), findsOneWidget);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    final translation = state.settings.translation;
    String verse(int n) =>
        state.db.passage(Ref(bookById(43), 3, n), translation: translation).single.text;
    expect(copied, '1 ${verse(1)}\n3 ${verse(3)}\nJohn 3:1, 3 ($translation)');
    expect(find.text('Copied John 3:1, 3.'), findsOneWidget);
  });
}
