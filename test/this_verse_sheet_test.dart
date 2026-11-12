import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/theme.dart';
import 'package:berea/this_verse_sheet.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

void main() {
  if (needsFullDatabase case final why?) {
    test('these tests read the built Bible', () {}, skip: why);
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

  final matthew = bookFor('Matthew')!;

  Future<AppState> open() async {
    final dir = Directory.systemTemp.createTempSync('berea-this-verse');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      prayerContent: PrayerContent.empty,
    );
    // Matthew 17:20 carries the footnote that prints 17:21, as in the publisher's tables.
    state.db.importMarks(
      MarksResult([
        VerseMarks(Ref(matthew, 17, 20), const [], const [
          (
            at: 5,
            text: 'BYZ and TR include 21But this kind does not come out except by prayer',
          ),
        ]),
      ], const []),
      'BSB',
    );
    return state;
  }

  Future<void> pump(
    WidgetTester tester,
    AppState state,
    Ref ref,
    void Function(Ref) onOpen,
  ) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.light),
        home: Scaffold(
          body: ThisVerse(
            state: state,
            verse: ref,
            onOpen: onOpen,
            onCommentary: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a verse the BSB leaves empty says where the BSB prints it, with the footnote',
    (tester) async {
      final state = (await tester.runAsync(open))!;
      await pump(tester, state, Ref(matthew, 17, 21, 21), (_) {});
      expect(
        find.text('The BSB prints this verse in a footnote at Matthew 17:20.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('BYZ and TR include 21But this kind'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'a verse lists its parts folded under counts, and a cross reference opens its passage',
    (tester) async {
      final state = (await tester.runAsync(open))!;
      Ref? opened;
      await pump(
        tester,
        state,
        Ref(bookFor('John')!, 3, 16, 16),
        (r) => opened = r,
      );
      expect(
        find.textContaining('In each translation on this phone · '),
        findsOneWidget,
      );
      expect(find.textContaining('Cross references · '), findsOneWidget);
      expect(
        find.textContaining('List published by OpenBible.info'),
        findsOneWidget,
      );
      expect(find.text('Your notes · 0'), findsOneWidget);
      await tester.tap(find.textContaining('Cross references · '));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('votes by site visitors').first);
      expect(opened, isNotNull);
    },
  );

  testWidgets(
    'a cross reference to a passage the reader has a note on says so, with the date',
    (tester) async {
      final state = (await tester.runAsync(open))!;
      final john = Ref(bookFor('John')!, 3, 16, 16);
      final target = state.db.xrefs(john, k: 1).single.to;
      state.study.addNote(target, 'mine');
      await pump(tester, state, john, (_) {});
      await tester.tap(find.textContaining('Cross references · '));
      await tester.pumpAndSettle();
      expect(find.textContaining('You wrote a note here on '), findsOneWidget);
    },
  );
}
