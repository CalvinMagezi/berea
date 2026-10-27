import 'package:berea/word_study_screen.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Matthew 5:48 and James 1:4 with τέλειος, Hebrews 2:10 with τελειόω (also glossed "perfect"),
/// and Job 1:1, as the built database has them.
BibleDb wordBible() {
  final raw = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER,
        verse INTEGER, text TEXT);
      CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT,
        translit TEXT, gloss TEXT, strongs TEXT, morph TEXT);
      CREATE TABLE lexicon(key TEXT, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT,
        definition TEXT);
    ''');
  void verse(int b, int c, int v, String text, List<List<String>> words) {
    raw.execute(
      "INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', ?, ?, ?, ?)",
      [b, c, v, text],
    );
    for (var i = 0; i < words.length; i++) {
      raw.execute('INSERT INTO words VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
        b,
        c,
        v,
        i + 1,
        ...words[i],
      ]);
    }
  }

  verse(40, 5, 48, 'Be perfect, therefore, as your heavenly Father is perfect.', [
    ['ἔσεσθε', 'esesthe', 'Will be', 'G1510', 'V-FDI-2P'],
    ['τέλειοι', 'teleioi', 'perfect', 'G5046', 'A-NPM'],
    ['πατὴρ', 'patēr', 'Father', 'G3962', 'N-NSM-T'],
    ['τέλειός', 'teleios', 'perfect', 'G5046', 'A-NSM'],
  ]);
  verse(58, 2, 10, 'to make the author of their salvation perfect through suffering.', [
    ['τελειῶσαι', 'teleiōsai', 'to perfect', 'G5048', 'V-AAN'],
  ]);
  verse(59, 1, 4, 'so that you may be mature and complete, not lacking anything.', [
    ['τέλειοι', 'teleioi', 'mature', 'G5046', 'A-NPM'],
    ['ὁλόκληροι', 'holoklēroi', 'complete', 'G3648', 'A-NPM'],
  ]);
  verse(18, 1, 1, 'And this man was blameless and upright, fearing God and shunning evil.', [
    ['תָּ֧ם', 'tam', 'blameless', 'H8535', 'HAamsa'],
    ['וְ/יָשָׁ֛ר', 've./ya.Shar', 'and/ upright', 'H9002 H3477G', 'HC/Aamsa'],
  ]);
  for (final l in [
    ['G5046', 'G5046', 'τέλειος', 'teleios', 'G:A', 'perfect', 'having reached its end, mature'],
    ['G5048', 'G5048', 'τελειόω', 'teleioō', 'G:V', 'to perfect', 'to bring to an end'],
    ['G3962', 'G3962', 'πατήρ', 'patēr', 'G:N-M', 'father', 'a father'],
    ['H8535', 'H8535', 'תָּם', 'tam', 'H:A', 'complete', '1) perfect, complete'],
    ['H3477G', 'H3477', 'יָשָׁר', 'ya.shar', 'H:A', 'upright', 'straight, upright'],
  ]) {
    raw.execute('INSERT INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?)', l);
  }
  // The BSB translation tables for two verses: every word of Matthew 5:48 has its number; in
  // Job 1:1 "And this" has none.
  return BibleDb(raw)..importBsbAlignment({
    RefParser.parse('Matthew 5:48').first: const [
      ('Be', 'G1510'),
      ('perfect', 'G5046'),
      (', therefore,', 'G3767'),
      ('as', 'G5613'),
      ('your', 'G4771'),
      ('heavenly', 'G3770'),
      ('Father', 'G3962'),
      ('is', 'G1510'),
      ('perfect', 'G5046'),
    ],
    RefParser.parse('Job 1:1').first: const [
      ('And this', ''),
      ('man', 'H376'),
      ('was', 'H1961'),
      ('blameless', 'H8535'),
      ('and upright', 'H3477'),
      ('fearing', 'H3373'),
      ('God', 'H430'),
    ],
  });
}

void main() {
  late BibleDb db;
  // The page, not the row of the verse's words that also scrolls.
  final page = find.byType(Scrollable).first;
  final asked = <String>[];
  final opened = <Ref>[];
  setUp(() {
    db = wordBible();
    asked.clear();
    opened.clear();
  });

  Future<void> open(
    WidgetTester tester,
    String ref, {
    String? english,
    int? pos,
    int occurrence = 0,
    int? wordIndex,
    String translation = defaultTranslation,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: WordStudyScreen(
          db: db,
          ref: RefParser.parse(ref).first,
          english: english,
          pos: pos,
          occurrence: occurrence,
          wordIndex: wordIndex,
          translation: translation,
          onAsk: asked.add,
          onOpen: opened.add,
        ),
      ),
    );
  }

  testWidgets('a pressed word opens its original, its use and every verse', (tester) async {
    await open(tester, 'Matthew 5:48', english: 'perfect');
    expect(find.text('τέλειος'), findsOneWidget);
    expect(find.text('teleios · G5046 · Greek · adjective'), findsOneWidget);
    expect(find.textContaining('Chosen by meaning'), findsOneWidget);
    expect(find.text('Used 3 times in 2 verses across 2 books.'), findsOneWidget);
    expect(find.text('perfect · 2'), findsOneWidget);
    expect(find.text('mature · 1'), findsOneWidget);
    // Another word glossed "perfect" is offered, with how often.
    await tester.scrollUntilVisible(find.text('τελειόω  teleioō'), 200, scrollable: page);
    expect(find.textContaining('glossed "perfect" once of 1'), findsOneWidget);

    await tester.scrollUntilVisible(find.textContaining('James 1:4 ·'), 200, scrollable: page);
    expect(find.textContaining('Matthew 5:48 · τέλειοι, τέλειός'), findsOneWidget);

    // A book filter keeps only that book's verses.
    await tester.scrollUntilVisible(find.text('James 1'), -200, scrollable: page);
    await tester.tap(find.text('James 1'));
    await tester.pump();
    expect(find.text('IN JAMES'), findsOneWidget);
    expect(find.textContaining('Matthew 5:48 ·'), findsNothing);
    await tester.tap(find.textContaining('James 1:4 ·'));
    expect(opened.single.label, 'James 1:4');
  });

  testWidgets('asking sends a question that names the word and the verse', (tester) async {
    await open(tester, 'Matthew 5:48', english: 'perfect');
    await tester.tap(find.text('Ask Berea about τέλειος'));
    expect(asked.single, contains('"perfect" in Matthew 5:48 is the Greek word τέλειος'));
    expect(strongsIn(asked.single), 'G5046');
  });

  testWidgets('another word glossed the same opens without the verse', (tester) async {
    await open(tester, 'Matthew 5:48', english: 'perfect');
    await tester.scrollUntilVisible(find.text('τελειόω  teleioō'), 200, scrollable: page);
    await tester.tap(find.text('τελειόω  teleioō'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('teleioō · G5048 · Greek · verb'),
      -200,
      scrollable: page,
    );
    expect(find.text('Used once in 1 verse across 1 book.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ask Berea about τελειόω'), -200, scrollable: page);
    await tester.tap(find.text('Ask Berea about τελειόω'));
    expect(asked.single, startsWith('Word study: the Greek word τελειόω'));
  });

  testWidgets('a word with no match asks the reader to choose one', (tester) async {
    await open(tester, 'Job 1:1', english: 'shunning');
    expect(find.textContaining('could not tell which Hebrew word is behind "shunning"'), findsOne);
    expect(find.text('MEANING'), findsNothing);
    await tester.tap(find.text('upright'));
    await tester.pump();
    expect(find.text('יָשָׁר'), findsOneWidget);
    expect(find.text('ya.shar · H3477 · Hebrew · adjective'), findsOneWidget);
    expect(find.textContaining('Chosen by meaning'), findsNothing);
  });

  testWidgets('the KJV word behind a different BSB word is found', (tester) async {
    await open(tester, 'Job 1:1', english: 'perfect');
    // Found through its lexicon definition, though this verse glosses it "blameless".
    expect(find.text('tam · H8535 · Hebrew · adjective'), findsOneWidget);
    expect(find.text('complete'), findsWidgets);
    // The form in the verse, without its accent, is the lemma, so no second line repeats it.
    expect(find.textContaining('In Job 1:1:'), findsNothing);
  });

  testWidgets('a word chosen in the interlinear opens by position', (tester) async {
    await open(tester, 'Matthew 5:48', pos: 3);
    expect(find.text('πατήρ'), findsOneWidget);
    expect(find.textContaining('Chosen by meaning'), findsNothing);
    expect(find.textContaining('OTHER WORDS GLOSSED'), findsNothing);
  });

  testWidgets('a press finds the word under the finger in the laid-out verse', (tester) async {
    const text = 'Be perfect, therefore, as your heavenly Father is perfect.';
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: Text.rich(
              key: key,
              const TextSpan(
                style: TextStyle(fontSize: 18),
                children: [
                  TextSpan(text: '48 ', style: TextStyle(fontSize: 11)),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.byKey(key));
    Offset at(int index) {
      final caret = paragraph.getOffsetForCaret(TextPosition(offset: index), Rect.zero);
      return paragraph.localToGlobal(caret + const Offset(3, 9));
    }

    final ctx = key.currentContext!;
    final second = 3 + text.lastIndexOf('perfect');
    expect(pressedWord(ctx, at(second), text, 3), (word: 'perfect', index: 8, occurrence: 1));
    expect(pressedWord(ctx, at(3 + text.indexOf('perfect')), text, 3)?.occurrence, 0);
    expect(pressedWord(ctx, at(3 + text.indexOf('Father')), text, 3)?.word, 'Father');
    // On the verse number, or outside the text, there is no word.
    expect(pressedWord(ctx, at(0), text, 3), isNull);
    expect(pressedWord(ctx, paragraph.localToGlobal(const Offset(400, 4)), text, 3), isNull);
  });

  testWidgets('in the BSB the translation tables give the exact word', (tester) async {
    await open(tester, 'Matthew 5:48', english: 'perfect', occurrence: 1, wordIndex: 8);
    expect(find.text('τέλειος'), findsOneWidget);
    expect(find.textContaining('Chosen by meaning'), findsNothing);
    expect(find.text('Words in Matthew 5:48'), findsOneWidget);
    // The second "perfect" is the second τέλειος, the nominative singular.
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('τέλειός'), matching: find.byType(ChoiceChip)),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('a word the BSB translators supplied says so', (tester) async {
    await open(tester, 'Job 1:1', english: 'this', wordIndex: 1);
    expect(find.textContaining('The translators supplied "this" here'), findsOneWidget);
    expect(find.textContaining('no Hebrew word stands behind it'), findsOneWidget);
    expect(find.text('MEANING'), findsNothing);
  });

  testWidgets('a word the tables number but STEP does not tag is still studied', (tester) async {
    // "fearing" is H3373 in the tables; this fixture's Job 1:1 has no STEP word for it.
    await open(tester, 'Job 1:1', english: 'fearing', wordIndex: 7);
    expect(find.text('H3373 · Hebrew'), findsOneWidget);
    expect(find.text('No lexicon entry for H3373.'), findsOneWidget);
    expect(find.textContaining('Chosen by meaning'), findsNothing);
    expect(find.text('Words in Job 1:1'), findsOneWidget);
  });

  testWidgets('other translations keep the guess by meaning', (tester) async {
    await open(tester, 'Job 1:1', english: 'perfect', wordIndex: 7, translation: 'KJV');
    expect(find.text('tam · H8535 · Hebrew · adjective'), findsOneWidget);
    expect(find.textContaining('Chosen by meaning'), findsOneWidget);
  });
}
