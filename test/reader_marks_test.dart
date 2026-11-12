import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/reader_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

const _matthew = 40;
const _redEnd = 6, _suppliedEnd = 10;

/// Matthew 3:1, the first verse on the screen, so it is built.
var text = '';

void main() {
  if (needsBibleText case final why?) {
    test('these tests read the BSB', () {}, skip: why);
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

  /// Matthew 3 with the start of verse 1 red and the next word supplied, whatever marks the
  /// database already holds.
  Future<AppState> open(Map<String, Object> prefs) async {
    final dir = Directory.systemTemp.createTempSync('berea-reader-marks');
    dirs.add(dir);
    SharedPreferences.setMockInitialValues({
      'readerBook': _matthew,
      'readerChapter': 3,
      'tipT14Done': true,
      ...prefs,
    });
    final state = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
    );
    final ref = Ref(bookFor('Matthew')!, 3, 1);
    text = state.db.passage(ref).single.text;
    state.db.importMarks(
      MarksResult([
        VerseMarks(ref, [
          (kind: MarkKind.red, start: 0, end: _redEnd),
          (kind: MarkKind.supplied, start: _redEnd + 1, end: _suppliedEnd),
        ], const []),
      ], const []),
      'BSB',
    );
    return state;
  }

  Future<void> pump(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(600, 900);
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

  Iterable<TextSpan> spans(WidgetTester tester) sync* {
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      final out = <TextSpan>[];
      w.text.visitChildren((s) {
        if (s is TextSpan) out.add(s);
        return true;
      });
      yield* out;
    }
  }

  testWidgets(
    'words of Jesus are red and supplied words italic, with a legend, by default',
    (tester) async {
      final state = (await tester.runAsync(() => open({})))!;
      await pump(tester, state);
      final scheme = Theme.of(tester.element(find.byType(ReaderScreen)))
          .colorScheme;
      expect(
        spans(tester).where(
          (s) =>
              s.style?.color == scheme.error &&
              s.text == text.substring(0, _redEnd),
        ),
        isNotEmpty,
      );
      expect(
        spans(tester).where(
          (s) =>
              s.style?.fontStyle == FontStyle.italic &&
              s.text == text.substring(_redEnd + 1, _suppliedEnd),
        ),
        isNotEmpty,
      );
      expect(
        find.textContaining(
          'words of Jesus, as the BSB publisher marks them',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'words the BSB translators supplied',
          findRichText: true,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('switched off, the text is plain and the legend is gone', (
    tester,
  ) async {
    final state = (await tester.runAsync(
      () => open({'redLetters': false, 'suppliedWords': false}),
    ))!;
    await pump(tester, state);
    final scheme = Theme.of(tester.element(find.byType(ReaderScreen)))
        .colorScheme;
    expect(
      spans(tester).where(
        (s) =>
            s.style?.color == scheme.error &&
            s.text == text.substring(0, _redEnd),
      ),
      isEmpty,
    );
    expect(
      find.textContaining('publisher marks them', findRichText: true),
      findsNothing,
    );
  });
}
