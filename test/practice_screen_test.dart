import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/plans.dart';
import 'package:berea/practice_screen.dart';
import 'package:berea/search_screen.dart';
import 'package:berea/step_through_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

const _phone = Size(600, 1000);

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

  Future<AppState> open([Map<String, Object> prefs = const {}]) async {
    final dir = Directory.systemTemp.createTempSync('berea-practice-screen');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({
      'readerBook': 43,
      'readerChapter': 1,
      'tipT14Done': true,
      ...prefs,
    });
    return AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      prayerContent: PrayerContent.empty,
    );
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: bereaTheme(Brightness.light), home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('only "Where you are reading" on a new install', (tester) async {
    final state = (await tester.runAsync(open))!;
    await pump(tester, PracticeScreen(state: state));

    expect(find.text('Practice'), findsOneWidget);
    expect(find.text(practiceCaption), findsOneWidget);
    expect(find.text('Where you are reading'), findsOneWidget);
    expect(find.text('John 1'), findsOneWidget);
    expect(find.text("Today's plan reading"), findsNothing);
    expect(find.text('MY SETS'), findsOneWidget);
    expect(find.text('Sets you save appear here.'), findsOneWidget);
    expect(find.text('Your highlighted verses'), findsNothing);

    // Tapping Where you are reading opens StepThroughScreen for the chapter.
    await tester.tap(find.text('Where you are reading'));
    await tester.pumpAndSettle();
    expect(find.byType(StepThroughScreen), findsOneWidget);
    expect(find.text('Where you are reading'), findsOneWidget);
  });

  testWidgets('sets are listed under My sets and tap opens StepThroughScreen', (tester) async {
    final state = (await tester.runAsync(open))!;
    final refs = RefParser.parse('Psalm 23').toList();
    state.practice.saveSet(refs, title: 'Psalm 23');

    await pump(tester, PracticeScreen(state: state));

    expect(find.text('Psalm 23'), findsOneWidget);
    expect(find.text('1 passage'), findsOneWidget);
    expect(find.text('Sets you save appear here.'), findsNothing);

    await tester.tap(find.text('Psalm 23'));
    await tester.pumpAndSettle();
    expect(find.byType(StepThroughScreen), findsOneWidget);
    expect(find.text('Psalm 23'), findsWidgets);
  });

  testWidgets('highlights row appears after a highlight is added and steps through them', (tester) async {
    final state = (await tester.runAsync(open))!;
    await pump(tester, PracticeScreen(state: state));

    expect(find.text('Your highlighted verses'), findsNothing);
    expect(find.text('Sets you save appear here.'), findsOneWidget);

    // Add a highlight and notify state.
    state.study.toggleHighlight(bookById(43), 3, 16);
    state.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('Your highlighted verses'), findsOneWidget);
    expect(find.text('1 passage'), findsOneWidget);
    expect(find.text('Sets you save appear here.'), findsNothing);

    // Tap steps through the highlighted verses.
    await tester.tap(find.text('Your highlighted verses'));
    await tester.pumpAndSettle();
    expect(find.byType(StepThroughScreen), findsOneWidget);
    expect(find.text('John 3:16'), findsOneWidget);
  });

  testWidgets('Save as a set from highlights creates one', (tester) async {
    final state = (await tester.runAsync(open))!;
    state.study.toggleHighlight(bookById(43), 3, 16);
    await pump(tester, PracticeScreen(state: state));

    expect(state.practice.sets(), isEmpty);
    await tester.tap(find.text('Save as a set'));
    await tester.pumpAndSettle();

    // Set was created with title "Your highlighted verses".
    expect(state.practice.sets(), hasLength(1));
    expect(state.practice.sets().first.title, 'Your highlighted verses');
  });

  testWidgets('Delete removes a set', (tester) async {
    final state = (await tester.runAsync(open))!;
    final id = state.practice.saveSet([Ref(bookById(19), 23)], title: 'To Delete')!;
    await pump(tester, PracticeScreen(state: state));

    expect(find.text('To Delete'), findsOneWidget);

    // Open popup menu on the set.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    // Tap Delete in menu.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirm dialog is shown.
    expect(find.text('Delete set'), findsOneWidget);
    expect(find.text('Delete "To Delete"?'), findsOneWidget);

    // Confirm deletion.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(state.practice.set(id), isNull);
    expect(find.text('To Delete'), findsNothing);
    expect(find.text('Sets you save appear here.'), findsOneWidget);
  });

  testWidgets("Today's plan reading appears when an active plan exists", (tester) async {
    final state = (await tester.runAsync(open))!;
    final nt = planById('nt-90')!;
    state.startPlan(nt);

    await pump(tester, PracticeScreen(state: state));

    expect(find.text("Today's plan reading"), findsOneWidget);
    final reading = state.todaysReading!;
    expect(find.text(reading.map((r) => r.label).join('; ')), findsOneWidget);

    await tester.tap(find.text("Today's plan reading"));
    await tester.pumpAndSettle();
    expect(find.byType(StepThroughScreen), findsOneWidget);
    expect(find.text("Today's plan reading"), findsOneWidget);
  });

  testWidgets('SearchScreen offers Save as a set on Scripture groups', (tester) async {
    final state = (await tester.runAsync(open))!;
    await pump(tester, SearchScreen(state: state));
    await tester.enterText(find.byType(TextField), 'Jesus');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pumpAndSettle();

    expect(find.text('Save as a set'), findsWidgets);
    await tester.tap(find.text('Save as a set').first);
    await tester.pump();

    expect(find.text('Saved as a set.'), findsOneWidget);
    expect(state.practice.sets(), isNotEmpty);
  });
}
