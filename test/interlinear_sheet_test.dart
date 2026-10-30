import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/interlinear_sheet.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

void main() {
  if (needsBuiltBible case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppState s;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('berea-words');
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
    s = await AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('a word in the Words sheet says what it means plainly; the lexicon waits a tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInterlinear(context, s, Ref(bookById(59), 3, 1)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final word = find.textContaining('krima').first;
    await tester.ensureVisible(word);
    await tester.pumpAndSettle();
    await tester.tap(word);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Means "judgment"'), findsOneWidget);
    expect(find.textContaining('decision passed on the faults of others'), findsOneWidget);
    expect(find.text("Scholar's lexicon entry"), findsOneWidget);
    expect(find.textContaining('LXX'), findsNothing, reason: 'the scholar\'s entry starts folded');
  });
}
