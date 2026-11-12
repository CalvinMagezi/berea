import 'package:berea/keep_sheet.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/study_store.dart';
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
  verse(43, 21, 15, 'Jesus replied, “Feed My lambs.”', [
    ['λέγει', 'legei', 'He says', 'G3004', 'V-PAI-3S'],
    ['βόσκε', 'boske', 'Feed', 'G1006', 'V-PAM-2S'],
    ['ἀρνία', 'arnia', 'lambs', 'G0721', 'N-APN'],
  ]);
  for (final l in [
    ['G3004', 'G3004', 'λέγω', 'legō', 'G:V', 'to say', 'to speak'],
    ['G1006', 'G1006', 'βόσκω', 'boskō', 'G:V', 'to feed', 'to graze'],
    ['G2424G', 'G2424', 'Ἰησοῦς', 'Iēsous', 'N:N-M-P', 'Jesus', 'Jesus, the Lord'],
    ['G5046', 'G5046', 'τέλειος', 'teleios', 'G:A', 'perfect', 'having reached its end, mature'],
    ['G5048', 'G5048', 'τελειόω', 'teleioō', 'G:V', 'to perfect', 'to bring to an end'],
    ['G3962', 'G3962', 'πατήρ', 'patēr', 'G:N-M', 'father', 'a father'],
    [
      'H8535',
      'H8535',
      'תָּם',
      'tam',
      'H:A',
      'complete',
      '1) perfect, complete 1a) (Qal) whole 2) peaceable, upright Mat.5:48',
    ],
    ['H3477G', 'H3477', 'יָשָׁר', 'ya.shar', 'H:A', 'upright', 'straight, upright'],
  ]) {
    raw.execute('INSERT INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?)', l);
  }
  // The BSB translation tables for two verses: every word of Matthew 5:48 has its number; in
  // Job 1:1 "And this" has none.
  final tables = <Ref, List<BsbRow>>{
    RefParser.parse('Matthew 5:48').first: const [
      BsbRow('Be', 'G1510'),
      BsbRow('perfect', 'G5046'),
      BsbRow(', therefore,', 'G3767'),
      BsbRow('as', 'G5613'),
      BsbRow('your', 'G4771'),
      BsbRow('heavenly', 'G3770'),
      BsbRow('Father', 'G3962'),
      BsbRow('is', 'G1510'),
      BsbRow('perfect', 'G5046', 1),
    ],
    RefParser.parse('Job 1:1').first: const [
      BsbRow('And this', ''),
      BsbRow('man', 'H0376'),
      BsbRow('was', 'H1961'),
      BsbRow('blameless', 'H8535'),
      BsbRow('and upright', 'H3477'),
      BsbRow('fearing', 'H3373'),
      BsbRow('God', 'H0430'),
    ],
    RefParser.parse('John 21:15').first: const [
      BsbRow('Jesus replied', 'G3004'),
      BsbRow('Feed', 'G1006'),
      BsbRow('My lambs', 'G0721'),
    ],
  };
  return BibleDb(raw)
    ..importBsbAlignment(tables)
    ..importRenderings(tables);
}

void main() {
  late BibleDb db;
  // The page, not the row of the verse's words that also scrolls.
  final page = find.byType(Scrollable).first;
  final opened = <Ref>[];
  setUp(() {
    db = wordBible();
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
          onOpen: opened.add,
        ),
      ),
    );
  }

  testWidgets('a pressed word opens its original, its use and every verse', (tester) async {
    await open(tester, 'Matthew 5:48', english: 'perfect', wordIndex: 1);
    expect(find.text('τέλειος'), findsOneWidget);
    expect(find.text('teleios · Greek · adjective'), findsOneWidget);
    expect(find.textContaining('Choose another from'), findsNothing, reason: 'the BSB tables name it');
    expect(find.text('You will find it 3 times in 2 verses across 2 books.'), findsOneWidget);
    // Once among STEPBible's glosses and once among the BSB's own renderings.
    expect(find.text('perfect · 2'), findsNWidgets(2));
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

  testWidgets('another word glossed the same opens without the verse', (tester) async {
    await open(tester, 'Matthew 5:48', english: 'perfect');
    await tester.scrollUntilVisible(find.text('τελειόω  teleioō'), 200, scrollable: page);
    await tester.tap(find.text('τελειόω  teleioō'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('teleioō · Greek · verb'), -200, scrollable: page);
    expect(find.text('You will find it once in 1 verse across 1 book.'), findsOneWidget);
  });

  testWidgets('a word with no match asks the reader to choose one', (tester) async {
    await open(tester, 'Job 1:1', english: 'shunning');
    expect(find.textContaining('could not tell which Hebrew word is behind "shunning"'), findsOne);
    expect(find.text('What it means'), findsNothing);
    await tester.tap(find.text('upright'));
    await tester.pump();
    expect(find.text('יָשָׁר'), findsOneWidget);
    expect(find.text('ya.shar · Hebrew · adjective'), findsOneWidget);
    expect(find.textContaining('Chosen by meaning'), findsNothing);
  });

  testWidgets('a word pressed without its place in the BSB is not guessed', (tester) async {
    await open(tester, 'Job 1:1', english: 'perfect');
    expect(find.text('tam · Hebrew · adjective'), findsNothing);
    expect(find.textContaining('Only the BSB says which Hebrew word stands behind'), findsOneWidget);
    expect(find.text('Words in Job 1:1'), findsOneWidget);
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
    expect(find.text('What it means'), findsNothing);
  });

  testWidgets('a name the BSB wrote onto a verb asks which word instead of opening the verb', (
    tester,
  ) async {
    // "Jesus replied" is one Greek verb in the tables; there is no Greek word for the name here.
    await open(tester, 'John 21:15', english: 'Jesus', wordIndex: 0);
    expect(find.textContaining('Jesus, John 21:15', findRichText: true), findsOneWidget);
    expect(find.textContaining('The BSB writes "Jesus" here'), findsOneWidget);
    expect(find.textContaining('stands on λέγω ("to say")'), findsOneWidget);
    expect(find.text('What it means'), findsNothing);
    expect(find.text('Words in John 21:15'), findsOneWidget);
  });

  testWidgets('the other word of that phrase still opens the verb', (tester) async {
    await open(tester, 'John 21:15', english: 'replied', wordIndex: 1);
    expect(find.text('λέγω'), findsOneWidget);
    expect(find.textContaining('Jesus, John 21:15', findRichText: true), findsNothing);
    expect(find.textContaining('replied, John 21:15', findRichText: true), findsOneWidget);
  });

  testWidgets('a word the tables number but STEP does not tag is still studied', (tester) async {
    // "fearing" is H3373 in the tables; this fixture's Job 1:1 has no STEP word for it.
    await open(tester, 'Job 1:1', english: 'fearing', wordIndex: 7);
    expect(find.text('Hebrew · H3373'), findsOneWidget);
    expect(find.textContaining('Chosen by meaning'), findsNothing);
    expect(find.text('Words in Job 1:1'), findsOneWidget);
  });

  testWidgets('other translations open with the verse\'s words and none chosen', (tester) async {
    await open(tester, 'Job 1:1', english: 'perfect', wordIndex: 7, translation: 'KJV');
    expect(find.text('tam · Hebrew · adjective'), findsNothing);
    expect(
      find.text('Only the BSB says which Hebrew word stands behind each of its words. Choose the word you pressed "perfect" for from Job 1:1:'),
      findsOneWidget,
    );
    expect(find.text('Words in Job 1:1'), findsOneWidget);
  });

  testWidgets('Save word keeps the word in a notebook through the Keep sheet', (tester) async {
    final study = StudyStore(sqlite3.openInMemory());
    final notebooks = NotebookStore(study.db);
    final youth = notebooks.createNotebook('Romans with the youth');
    final nav = GlobalKey<NavigatorState>();
    int? kept;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: WordStudyScreen(
          db: db,
          ref: RefParser.parse('Matthew 5:48').first,
          english: 'perfect',
          wordIndex: 1,
          onOpen: opened.add,
          onKeep: ({required title, required body, required subtitle, verse}) async {
            kept = await showModalBottomSheet<int>(
              context: nav.currentContext!,
              isScrollControlled: true,
              builder: (_) => KeepSheet(
                study: study,
                notebooks: notebooks,
                title: title,
                body: body,
                subtitle: subtitle,
                verse: verse,
                kind: keptWordKind,
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Save word'));
    await tester.pumpAndSettle();
    expect(find.text('Keep τέλειος'), findsOneWidget, reason: 'the gloss is said once, below');
    expect(find.text('perfect · G5046 · from Matthew 5:48, BSB'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep'));
    await tester.pumpAndSettle();

    final note = study.note(kept!)!;
    expect(note.notebookId, youth);
    expect(note.title, 'τέλειος, perfect');
    expect(note.verse!.label, 'Matthew 5:48');
    expect(isKeptWord(note), isTrue);
    expect(note.text, contains("Strong's G5046 · teleios · Greek"));
    expect(note.text, contains('From Matthew 5:48, BSB'));
  });

  testWidgets('without a way to keep, Save word is not offered', (tester) async {
    await open(tester, 'Matthew 5:48', english: 'perfect', wordIndex: 1);
    expect(find.text('Save word'), findsNothing);
  });

  testWidgets('at phone width the meaning leads in plain words and the lexicon entry is closed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: WordStudyScreen(
          db: db,
          ref: RefParser.parse('Matthew 5:48').first,
          english: 'perfect',
          wordIndex: 1,
          onOpen: opened.add,
          onKeep: ({required title, required body, required subtitle, verse}) {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('What it means'), findsNothing);
    expect(find.text('How the BSB translates it'), findsOneWidget);
    expect(find.text('perfect · 2'), findsOneWidget, reason: 'the tables print "perfect" twice for it');
    expect(find.text('In this verse'), findsOneWidget);
    expect(find.text("Scholar's lexicon entry"), findsOneWidget);
    // Closed: the raw definition is not on screen until the tile is opened.
    expect(find.text('having reached its end, mature'), findsNothing);
    await tester.scrollUntilVisible(find.text("Scholar's lexicon entry"), 200, scrollable: page);
    await tester.tap(find.text("Scholar's lexicon entry"));
    await tester.pumpAndSettle();
    expect(find.text('having reached its end, mature'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a definition with several senses lists them in plain words', (tester) async {
    await open(tester, 'Job 1:1', english: 'blameless', wordIndex: 4);
    expect(find.text('Its senses'), findsNothing, reason: 'senses in plain words left the screen');
    expect(find.text('Perfect, complete'), findsNothing);
  });

  testWidgets('a number opened alone offers every entry STEPBible keeps under it and shows the first', (
    tester,
  ) async {
    final db = wordBible();
    for (final l in [
      ['H7307G', 'H7307', 'רוּחַ', 'ru.ach', 'H:N', 'spirit', 'spirit, wind'],
      ['H7307H', 'H7307', 'רוּחַ', 'ru.ach', 'H:N', 'spirit: breath', 'breath'],
    ]) {
      db.db.execute('INSERT INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?)', l);
    }
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: WordStudyScreen(db: db, code: 'H7307', onOpen: (_) {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('STEPBible lists 2 entries under H7307. The first is shown; choose another to see it:'), findsOneWidget);
    expect(find.text('H · spirit: breath'), findsOneWidget);
    await tester.tap(find.text('H · spirit: breath'));
    await tester.pumpAndSettle();
    expect(find.text('STEPBible lists 2 entries under H7307. The first is shown; choose another to see it:'), findsOneWidget);
    await tester.tap(find.text("Scholar's lexicon entry"));
    await tester.pumpAndSettle();
    expect(find.text('STEPBible lists it as: spirit: breath'), findsOneWidget, reason: 'the chosen entry is the study');
  });

  testWidgets('a number with one entry offers no choice', (tester) async {
    final db = wordBible();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: WordStudyScreen(db: db, code: 'G5046', onOpen: (_) {})),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('STEPBible lists'), findsNothing);
  });

  testWidgets('a Greek entry says whose definition it shows, or why it shows none', (tester) async {
    final db = wordBible();
    db.db.execute('CREATE TABLE lexicon_source(key TEXT PRIMARY KEY, source TEXT)');
    for (final (key, source, definition) in [
      ('G5046', 'AS', 'having reached its end, mature'),
      ('G5048', 'ML', ''),
      ('G3962', '', ''),
    ]) {
      db.db.execute('INSERT INTO lexicon_source VALUES (?, ?)', [key, source]);
      db.db.execute('UPDATE lexicon SET definition = ? WHERE key = ?', [definition, key]);
    }
    expect(db.lexicon('G5046')!.source, 'AS');
    expect(db.lexicon('G5048')!.source, 'ML');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    for (final (code, line) in [
      ('G5046', 'Abbott-Smith (1922), corrected and adapted by Tyndale House scholars (STEPBible).'),
      ('G5048', "This entry's definition is Middle Liddell's, from Perseus, under a share-alike licence, and is not in this download; only its gloss is shown."),
      ('G3962', "STEPBible gives no source for this entry's definition; only its gloss is shown."),
    ]) {
      await tester.pumpWidget(MaterialApp(home: WordStudyScreen(key: ValueKey(code), db: db, code: code, onOpen: (_) {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Scholar's lexicon entry"));
      await tester.pumpAndSettle();
      expect(find.text(line), findsOneWidget, reason: code);
    }
  });
}
