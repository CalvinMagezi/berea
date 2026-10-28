import 'package:berea/word_press.dart';
import 'package:berea/word_study_screen.dart';
import 'package:berea_harness/berea_harness.dart' show verseWordPattern;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verses as the reader sets them: a verse number, then the text, with a note mark after some.
const _verses = [
  'In the beginning God created the heavens and the earth.',
  'Jesus wept.',
  'He said, “Do not fear; I am with you,” and the king’s house stood.',
  'Be perfect, therefore, as your heavenly Father is perfect, and love your neighbour as yourself '
      'because the LORD your God is holy and merciful to all who call on His name in truth.',
];

typedef _Hit = ({String word, int index, int occurrence});

void main() {
  const prefix = '1 ';
  const text = 'In the beginning God created the heavens and the earth.';
  final textKey = GlobalKey();
  final words = <_Hit>[];
  var verses = 0, taps = 0;

  setUp(() {
    words.clear();
    verses = taps = 0;
  });

  Widget app({bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion, size: const Size(400, 800)),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 200, left: 16, right: 16),
          child: WordPressRegion(
            text: text,
            prefixLength: prefix.length,
            textKey: textKey,
            labelFor: (hit) => hit == null ? wholeVerseLabel : 'label ${hit.word}',
            onWord: words.add,
            onVerse: () => verses++,
            onTap: () => taps++,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text.rich(
                key: textKey,
                const TextSpan(
                  style: TextStyle(fontSize: 18),
                  children: [
                    TextSpan(text: prefix, style: TextStyle(fontSize: 11)),
                    TextSpan(text: text),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Offset centerOf(String word) {
    final i = text.indexOf(word);
    final boxes = verseBoxes(textKey.currentContext!, i, i + word.length, prefix.length);
    return boxes.single.center;
  }

  WordPressRegionState region(WidgetTester tester) => tester.state(find.byType(WordPressRegion));

  const preview = Duration(milliseconds: 130);

  testWidgets('a rested finger marks its word, names it, fills, and opens the word', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final g = await tester.startGesture(centerOf('God'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(region(tester).target, isNull);
    await tester.pump(const Duration(milliseconds: 30));
    expect(region(tester).target?.hit?.word, 'God');
    expect(find.text('label God'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 190));
    expect(region(tester).fillValue, inExclusiveRange(0.2, 0.8));
    await tester.pump(const Duration(milliseconds: 200));
    expect(words.map((w) => (w.word, w.index)), [('God', 3)]);
    expect(region(tester).target, isNull);
    expect(find.text('label God'), findsNothing);
    await g.up();
    await tester.pump();
    expect(taps, 0, reason: 'the tap that follows a long press does not select the verse');
    expect(verses, 0);
  });

  testWidgets('lifting before the fill is full opens nothing', (tester) async {
    await tester.pumpWidget(app());
    final g = await tester.startGesture(centerOf('heavens'));
    await tester.pump(preview);
    expect(region(tester).target?.hit?.word, 'heavens');
    await tester.pump(const Duration(milliseconds: 200));
    await g.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(words, isEmpty);
    expect(verses, 0);
    expect(region(tester).target, isNull);
    expect(find.text('label heavens'), findsNothing);
  });

  testWidgets('a quick tap still selects the verse', (tester) async {
    await tester.pumpWidget(app());
    await tester.tapAt(centerOf('God'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(taps, 1);
    expect(words, isEmpty);
  });

  testWidgets('moving onto another word moves the mark and starts the fill again', (tester) async {
    await tester.pumpWidget(app());
    final g = await tester.startGesture(centerOf('beginning'), kind: PointerDeviceKind.mouse);
    await tester.pump(preview);
    expect(region(tester).target?.hit?.word, 'beginning');
    await tester.pump(const Duration(milliseconds: 80));
    await g.moveTo(centerOf('created'));
    await tester.pump();
    expect(region(tester).target?.hit?.word, 'created');
    expect(find.text('label created'), findsOneWidget);
    expect(find.text('label beginning'), findsNothing);
    // The first word's fill would have been full at 500 ms; the second has had 300 ms.
    await tester.pump(const Duration(milliseconds: 300));
    expect(words, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(words.single.word, 'created');
    await g.up();
  });

  testWidgets('a finger that moves past the touch slop is scrolling, not pressing', (tester) async {
    await tester.pumpWidget(app());
    final g = await tester.startGesture(centerOf('God'));
    await tester.pump(preview);
    expect(region(tester).target, isNotNull);
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(region(tester).target, isNull);
    await tester.pump(const Duration(milliseconds: 600));
    expect(words, isEmpty);
    await g.up();
  });

  testWidgets('a second finger does not end the first press', (tester) async {
    await tester.pumpWidget(app());
    final first = await tester.startGesture(centerOf('God'));
    await tester.pump(preview);
    final second = await tester.startGesture(centerOf('earth'));
    await tester.pump(preview);
    expect(region(tester).target?.hit?.word, 'God');
    await second.moveBy(const Offset(2, 0));
    await second.up();
    await tester.pump();
    expect(region(tester).target?.hit?.word, 'God');
    await tester.pump(const Duration(milliseconds: 400));
    expect(words.single.word, 'God');
    await first.up();
  });

  testWidgets('moving off the verse cancels the press', (tester) async {
    await tester.pumpWidget(app());
    final g = await tester.startGesture(centerOf('God'), kind: PointerDeviceKind.mouse);
    await tester.pump(preview);
    await g.moveTo(const Offset(200, 20));
    await tester.pump(const Duration(milliseconds: 600));
    expect(words, isEmpty);
    expect(verses, 0);
    await g.up();
  });

  testWidgets('scrolling drops a press in progress', (tester) async {
    await tester.pumpWidget(app());
    final g = await tester.startGesture(centerOf('God'));
    await tester.pump(preview);
    WordPressRegion.cancelActive();
    await tester.pump(const Duration(milliseconds: 600));
    expect(words, isEmpty);
    await g.up();
  });

  testWidgets('a press on the verse number marks the whole verse and opens the interlinear', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final g = await tester.startGesture(tester.getTopLeft(find.byKey(textKey)) + const Offset(3, 9));
    await tester.pump(preview);
    expect(region(tester).target?.hit, isNull);
    expect(find.text(wholeVerseLabel), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(verses, 1);
    expect(words, isEmpty);
    await g.up();
  });

  testWidgets('with reduced motion the mark shows at once without a sweep', (tester) async {
    await tester.pumpWidget(app(reduceMotion: true));
    final g = await tester.startGesture(centerOf('earth'));
    await tester.pump(preview);
    expect(region(tester).target?.hit?.word, 'earth');
    expect(region(tester).fillValue, 1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(words.single.word, 'earth');
    await g.up();
  });

  testWidgets('a right click offers the word and the whole verse', (tester) async {
    await tester.pumpWidget(app());
    final g = await tester.startGesture(
      centerOf('God'),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Study the word God'), findsOneWidget);
    expect(find.text(wholeVerseLabel), findsOneWidget);
    await tester.tap(find.text('Study the word God'));
    await tester.pumpAndSettle();
    expect(words.single.word, 'God');
  });

  group('the word under the centre of every word is the word pressed', () {
    for (final width in [360.0, 1280.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('width $width, text scale $scale', (tester) async {
          tester.view.physicalSize = Size(width, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          for (final verse in _verses) {
            final key = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale), size: Size(width, 2400)),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                      // As the reader sets a verse: its number, the text, and a note mark.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text.rich(
                              key: key,
                              TextSpan(
                                style: const TextStyle(fontSize: 18, height: 1.6),
                                children: [
                                  const TextSpan(text: '16 ', style: TextStyle(fontSize: 11)),
                                  TextSpan(text: verse),
                                  const WidgetSpan(child: Icon(Icons.sticky_note_2_outlined, size: 14)),
                                ],
                              ),
                            ),
                          ),
                          const Expanded(child: Text('A parallel translation of the same verse.')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            final ctx = key.currentContext!;
            final starts = verseWordPattern.allMatches(verse).toList();
            for (var i = 0; i < starts.length; i++) {
              final m = starts[i];
              final boxes = verseBoxes(ctx, m.start, m.end, 3);
              expect(boxes, isNotEmpty, reason: '${m[0]} in "$verse"');
              final got = pressedWord(ctx, boxes.first.center, verse, 3);
              expect(got?.word, m[0], reason: '${m[0]} at $width x $scale');
              expect(got?.index, i, reason: '${m[0]} at $width x $scale');
            }
            // The parallel column is not the verse.
            expect(pressedWord(ctx, Offset(width - 20, 20), verse, 3), isNull);
          }
        });
      }
    }
  });
}
