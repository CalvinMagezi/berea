import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/search_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

const _phone = Size(600, 1000);
const _afterDelay = Duration(milliseconds: 400);
const _searchWait = Duration(seconds: 3);

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
    final dir = Directory.systemTemp.createTempSync('berea-search');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name, 'tipT14Done': true});
    return AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      prayerContent: PrayerContent.empty,
    );
  }

  Future<void> search(WidgetTester tester, AppState state, String query) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: bereaTheme(Brightness.light), home: SearchScreen(state: state)),
    );
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(_afterDelay);
    // The search runs on another isolate, which only real time advances.
    await tester.runAsync(() => Future<void>.delayed(_searchWait));
    await tester.pumpAndSettle();
  }

  testWidgets('"Jesus" finds verses, under a header that names how they were found', (
    tester,
  ) async {
    final state = (await tester.runAsync(open))!;
    await search(tester, state, 'Jesus');
    expect(find.textContaining('Exact words ·'), findsOneWidget);
    expect(find.text('No verse in the BSB has those words.'), findsNothing);
    expect(find.textContaining('Matthew 1:1'), findsWidgets);
  });

  testWidgets('a word in no verse says so', (tester) async {
    final state = (await tester.runAsync(open))!;
    await search(tester, state, 'zzzqqq');
    expect(find.text('No verse in the ${state.settings.translation} has those words.'), findsOneWidget);
  });

  testWidgets('a lone function word says it is in too many verses', (tester) async {
    final state = (await tester.runAsync(open))!;
    await search(tester, state, 'the');
    expect(find.text('"the" is in too many verses to list. Add another word.'), findsOneWidget);
  });

  testWidgets('a misspelt word offers the words one letter away, and a tap searches the word', (
    tester,
  ) async {
    final state = (await tester.runAsync(open))!;
    await search(tester, state, 'Jeus');
    expect(find.text('No verses have "jeus". Words one letter away that verses do have:'), findsOneWidget);
    await tester.tap(find.text('jesus'));
    await tester.pump(_afterDelay);
    await tester.runAsync(() => Future<void>.delayed(_searchWait));
    await tester.pumpAndSettle();
    expect(find.textContaining('Exact words ·'), findsOneWidget);
  });
}
