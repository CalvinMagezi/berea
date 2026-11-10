import 'dart:io';

import 'package:berea/app_state.dart';
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
    final dir = Directory.systemTemp.createTempSync('berea-step-through');
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

  testWidgets('one whole verse per screen, "1 of N" then "2 of N", and Done pops', (tester) async {
    final state = (await tester.runAsync(open))!;
    final refs = RefParser.parse('John 3:16-17').toList();

    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => StepThroughScreen(
                  state: state,
                  title: 'Step through test',
                  refs: refs,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    // Open the step through screen.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(StepThroughScreen), findsOneWidget);
    expect(find.text('Step through test'), findsOneWidget);

    // First verse: John 3:16.
    expect(find.text('John 3:16'), findsOneWidget);
    expect(find.text('BSB'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Previous verse'), findsNothing);
    expect(find.text('Next verse'), findsOneWidget);

    // Move to next verse: John 3:17.
    await tester.tap(find.text('Next verse'));
    await tester.pumpAndSettle();

    expect(find.text('John 3:17'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('Previous verse'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Next verse'), findsNothing);

    // Test moving backwards.
    await tester.tap(find.text('Previous verse'));
    await tester.pumpAndSettle();

    expect(find.text('John 3:16'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    // Advance to end and finish.
    await tester.tap(find.text('Next verse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Verifies the screen was popped.
    expect(find.byType(StepThroughScreen), findsNothing);
  });

  testWidgets('missing-translation message is shown when a reference has no verses', (tester) async {
    final state = (await tester.runAsync(open))!;
    // Chapter 999 does not exist in Genesis.
    final emptyRef = Ref(bookById(1), 999);

    await pump(
      tester,
      StepThroughScreen(
        state: state,
        title: 'Empty test',
        refs: [emptyRef],
      ),
    );

    expect(find.text('No verses to show in BSB.'), findsOneWidget);
    expect(find.text('Next verse'), findsNothing);
    expect(find.text('Done'), findsNothing);
  });
}
