import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/chat_screen.dart';
import 'package:berea/home_shell.dart';
import 'package:berea/notebooks_screen.dart';
import 'package:berea/notes_screen.dart';
import 'package:berea/prayer_screen.dart';
import 'package:berea/reader_screen.dart';
import 'package:berea/study_button.dart';
import 'package:berea/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Wide enough for the reader's chapter bar in the test font, which is wider than real type.
const _phone = Size(600, 900);
const _mac = Size(1280, 800);
const _places = ['Bible', 'Plans', 'Study', 'Prayer', 'Notes'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppState state;
  var setUpCalls = 0;
  final launch = Stopwatch();

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('berea-shell-test');
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
    launch.start();
    state = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      onFirstSetup: () => setUpCalls++,
    );
    launch.stop();
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  /// Whether the helper had not yet started when the shell first built.
  bool? shellBeforeHelper;

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            shellBeforeHelper ??= state.harness == null && state.helperState is HelperChecking;
            return HomeShell(state: state);
          },
        ),
      ),
    );
  }

  test('bootstrap opens the Bible without loading the helper', () {
    // A fresh folder copies the bundled Bible, which is when the setup screen says so.
    expect(setUpCalls, 1);
    expect(state.harness, isNull);
    expect(state.helperState, isA<HelperChecking>());
    // ignore: avoid_print
    print('Bootstrap to Bible ready: ${launch.elapsedMilliseconds} ms (first launch, with copy)');
  });

  testWidgets('the Bible is on screen in the first frame, before the helper is ready', (
    tester,
  ) async {
    await pumpShell(tester, _phone);
    expect(shellBeforeHelper, isTrue, reason: 'the helper starts after the first frame');
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing, reason: 'Study waits offstage');
    await tester.pump();
    await tester.pump();
    expect(state.helperState, isA<HelperReady>());
    expect(state.harness, isNotNull);
  });

  testWidgets('the phone bar has five places in order, Study raised in the middle', (
    tester,
  ) async {
    await pumpShell(tester, _phone);
    final xs = [for (final p in _places) tester.getCenter(find.text(p).last).dx];
    expect(xs, [...xs]..sort());
    final study = tester.getRect(find.byType(StudyButton));
    final bible = tester.getRect(find.text('Bible').last);
    expect(study.top, lessThan(bible.top - studyButtonSize / 2), reason: 'Study is raised');
    expect((study.center.dx - _phone.width / 2).abs(), lessThan(1));

    await tester.tap(find.text('Study').last);
    await tester.pump();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.byTooltip('Ask Berea'), findsNothing, reason: 'Study is always one tap');
  });

  testWidgets('the bar hides under the keyboard', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await pumpShell(tester, _phone);
    expect(find.byType(StudyButton), findsNothing);
  });

  testWidgets('the Mac sidebar keeps the order, takes Cmd 1 to 5 and shows the helper', (
    tester,
  ) async {
    await pumpShell(tester, _mac);
    await tester.pump();
    final ys = [for (final p in _places) tester.getCenter(find.text(p).first).dy];
    expect(ys, [...ys]..sort());
    expect(tester.getSize(find.text('NOTEBOOKS')).width, greaterThan(0));
    expect(find.textContaining('Helper ready, Ollama on this'), findsOneWidget);

    final modifier = Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(find.byType(ChatScreen), findsOneWidget);

    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('a notebook is listed under Notes in the sidebar and opens beside it', (
    tester,
  ) async {
    final id = state.notebooks.createNotebook('Sunday sermons');
    await pumpShell(tester, _mac);
    await tester.tap(find.text('Sunday sermons'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookScreen), findsOneWidget);
    expect(find.text('NOTEBOOKS'), findsOneWidget);

    // Ask about this notebook, from inside it, lands on Study scoped to it.
    await tester.tap(find.text('Ask about this notebook'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(NotebookScreen), findsNothing);
    expect(state.studyScope.value, id);
    state.studyScope.value = null;
    state.notebooks.deleteNotebook(id);
  });

  testWidgets('the Notes place shows the notebooks row and Recent under the bar', (tester) async {
    final id = state.notebooks.createNotebook('Romans with the youth');
    await pumpShell(tester, _phone);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesScreen), findsOneWidget);
    expect(find.text('RECENT'), findsOneWidget);
    await tester.tap(find.text('Romans with the youth'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookScreen), findsOneWidget);
    // The bar stays under a notebook.
    expect(find.byType(StudyButton), findsOneWidget);
    state.notebooks.deleteNotebook(id);
  });

  testWidgets('the Prayer place is the prayer list', (tester) async {
    await pumpShell(tester, _phone);
    await tester.tap(find.text('Prayer'));
    await tester.pumpAndSettle();
    expect(find.byType(PrayerScreen), findsOneWidget);
  });

  testWidgets('Ask about this notebook opens Study scoped to it', (tester) async {
    final id = state.notebooks.createNotebook('Romans with the youth');
    await pumpShell(tester, _phone);
    state.askAboutNotebook(id);
    await tester.pump();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(state.studyScope.value, id);
    state.studyScope.value = null;
    state.notebooks.deleteNotebook(id);
  });
}
