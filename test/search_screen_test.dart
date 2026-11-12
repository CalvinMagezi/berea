import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/commentary_packs.dart';
import 'package:berea/commentary_sheet.dart';
import 'package:berea/search_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea/word_study_screen.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/bible.dart';

const _phone = Size(600, 1000);
const _afterDelay = Duration(milliseconds: 400);
const _searchWait = Duration(seconds: 3);

void main() {
  verifyCommentaryPacks = false;
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
    SharedPreferences.setMockInitialValues({'tipT14Done': true});
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
  /// How STEPBible tags "holy", for the BSB-only test database that has no original words: hagios
  /// in two New Testament verses, qadosh in one Old Testament verse.
  void addHolyWords(AppState state) {
    final raw = state.db.db;
    // The full database tags thousands of words; the counts asserted here assume only these three.
    raw.execute('DELETE FROM words');
    raw.execute('DELETE FROM lexicon');
    // The BSB's renderings of these numbers would push the lines under test off screen.
    if (raw.select("SELECT 1 FROM sqlite_master WHERE name = 'bsb_renderings'").isNotEmpty) {
      raw.execute('DELETE FROM bsb_renderings');
    }
    void word(int book, int chapter, int verse, String original, String translit, String strongs) =>
        raw.execute('INSERT OR IGNORE INTO words VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?)', [
          book,
          chapter,
          verse,
          original,
          translit,
          'holy',
          strongs,
          strongs.startsWith('G') ? 'A-NSM' : 'HAamsa',
        ]);
    word(43, 14, 26, 'ἅγιον', 'hagion', 'G0040');
    word(46, 3, 17, 'ἅγιος', 'hagios', 'G0040');
    word(3, 19, 2, 'קָדוֹשׁ', 'qa.dosh', 'H6918');
    for (final l in [
      ['G0040G', 'G0040', 'ἅγιος', 'hagios', 'G:A', 'holy', 'set apart for God'],
      ['H6918G', 'H6918', 'קָדוֹשׁ', 'qa.dosh', 'H:A', 'holy', 'sacred, holy'],
    ]) {
      raw.execute('INSERT OR IGNORE INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?)', l);
    }
    state.db.buildWordIndex();
  }

  /// A commentary pack with two comments on holiness, installed the way a downloaded one is.
  Future<void> installHolyCommentary(AppState state) async {
    final dir = Directory.systemTemp.createTempSync('berea-search-pack');
    dirs.add(dir);
    final path = '${dir.path}/commentary-core.sqlite';
    final db = sqlite3.open(path)..execute(commentaryPackSchema);
    db
      ..execute("INSERT INTO meta VALUES ('format', '$commentaryPackFormat')")
      ..execute("INSERT INTO meta VALUES ('pack', 'core')")
      ..execute(
        "INSERT INTO modules VALUES ('MHCC', 'Matthew Henry''s Concise Commentary', "
        "'Matthew Henry', 'Public domain', 'test', 0)",
      );
    for (final e in [
      [3, 19, 2, 2, 'Be ye holy, for the LORD your God is holy. Holiness is the aim of every law.'],
      [46, 3, 16, 17, 'The church of God is holy ground, and he who defiles it will be destroyed.'],
    ]) {
      db.execute(
        "INSERT INTO entries(module, book, chapter, verse_start, verse_end, html_or_text) "
        "VALUES ('MHCC', ?, ?, ?, ?, ?)",
        e,
      );
    }
    db.execute("INSERT INTO entries_fts(entries_fts) VALUES('rebuild')");
    db.dispose();
    await state.commentary.installFromFile(path);
  }

  testWidgets('"Holy" puts the words behind it first, each saying why, then the verses', (
    tester,
  ) async {
    final state = (await tester.runAsync(open))!;
    addHolyWords(state);
    await search(tester, state, 'Holy');
    expect(find.textContaining('Word studies · 2 Hebrew and Greek words'), findsOneWidget);
    expect(find.textContaining('ἅγιος'), findsOneWidget);
    expect(find.textContaining('hagios'), findsOneWidget);
    expect(find.textContaining('STEPBible glosses it "holy" twice'), findsOneWidget);
    expect(find.textContaining('Greek · G0040 · used 2 times in 2 verses'), findsOneWidget);
    expect(find.textContaining('Hebrew · H6918 · used 1 time in 1 verse'), findsOneWidget);
    expect(find.textContaining('Exact words ·'), findsOneWidget);
    final words = tester.getTopLeft(find.textContaining('Word studies ·')).dy;
    final verses = tester.getTopLeft(find.textContaining('Exact words ·')).dy;
    expect(words, lessThan(verses), reason: 'a single word is looked into before it is listed');
  });

  testWidgets('a long query, most likely a verse being recalled, lists verses before words', (
    tester,
  ) async {
    final state = (await tester.runAsync(open))!;
    addHolyWords(state);
    await search(tester, state, 'love your enemies');
    expect(find.textContaining('Exact words ·'), findsOneWidget);
    expect(find.textContaining('Matthew 5:44'), findsWidgets);
    expect(find.textContaining('No commentaries are downloaded'), findsNothing);
  });

  testWidgets('a word study opens from its row, on the word and not on a verse', (tester) async {
    final state = (await tester.runAsync(open))!;
    addHolyWords(state);
    await search(tester, state, 'Holy');
    await tester.tap(find.textContaining('hagios'));
    await tester.pumpAndSettle();
    expect(find.byType(WordStudyScreen), findsOneWidget);
    expect(find.text('Word study'), findsOneWidget);
    expect(find.text('ἅγιος'), findsOneWidget);
    expect(find.text("Scholar's lexicon entry"), findsOneWidget);
    expect(find.textContaining('used 2 times'), findsNothing, reason: 'the study has its own words');
    expect(find.textContaining('You will find it twice in 2 verses'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('OTHER WORDS GLOSSED'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('OTHER WORDS GLOSSED'), findsOneWidget, reason: 'qadosh is one tap away');
  });

  testWidgets('the chips show one kind at a time, with how many there are', (tester) async {
    final state = (await tester.runAsync(open))!;
    addHolyWords(state);
    await tester.runAsync(() => installHolyCommentary(state));
    await search(tester, state, 'Holy');
    expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Word studies 2'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Commentary 2'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is ChoiceChip && w.label is Text && (w.label as Text).data!.startsWith('Verses '),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Word studies 2'));
    await tester.pump();
    expect(find.textContaining('Word studies ·'), findsOneWidget);
    expect(find.textContaining('Exact words ·'), findsNothing);
    expect(find.textContaining('Commentary · 2 comments in 1 work'), findsNothing);
    expect(find.text('Show all 2 word studies'), findsNothing, reason: 'it is all of them now');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Commentary 2'));
    await tester.pump();
    expect(find.textContaining('Commentary · 2 comments in 1 work'), findsOneWidget);
    expect(find.textContaining('Word studies ·'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pump();
    expect(find.textContaining('Word studies ·'), findsOneWidget);
    expect(find.textContaining('Commentary · 2 comments in 1 work'), findsOneWidget);
    expect(find.textContaining('Exact words ·'), findsOneWidget);
  });

  testWidgets('commentary on the word is listed by work, with the words marked', (tester) async {
    final state = (await tester.runAsync(open))!;
    addHolyWords(state);
    await tester.runAsync(() => installHolyCommentary(state));
    await search(tester, state, 'Holy');
    expect(
      find.textContaining('Commentary · 2 comments in 1 work, best matches first'),
      findsOneWidget,
    );
    expect(find.textContaining("Matthew Henry's Concise Commentary · 2 comments"), findsOneWidget);
    expect(find.textContaining('Leviticus 19:2'), findsOneWidget);
    expect(find.textContaining('Be ye holy'), findsOneWidget);
    final snippet = tester.widget<Text>(find.textContaining('Be ye holy'));
    final bold = <String>[];
    snippet.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.style?.fontWeight == FontWeight.w700) bold.add(span.text!);
      return true;
    });
    expect(bold, containsAll(['holy', 'Holiness']));
  });

  testWidgets('a commentary row opens the commentary on its passage', (tester) async {
    final state = (await tester.runAsync(open))!;
    await tester.runAsync(() => installHolyCommentary(state));
    await search(tester, state, 'Holy');
    await tester.tap(find.textContaining('Leviticus 19:2'));
    await tester.pumpAndSettle();
    expect(find.byType(CommentaryPanel), findsOneWidget);
    expect(find.textContaining('Be ye holy, for the LORD'), findsWidgets);
  });

  testWidgets('with no commentary downloaded, a word search offers the download', (tester) async {
    final state = (await tester.runAsync(open))!;
    await search(tester, state, 'Holy');
    expect(
      find.textContaining('No commentaries are downloaded yet, so none were searched.'),
      findsOneWidget,
    );
    expect(find.text('Download in Settings'), findsOneWidget);
  });

  testWidgets('a Strong\'s number lists that word, and clearing the box clears the results', (
    tester,
  ) async {
    final state = (await tester.runAsync(open))!;
    addHolyWords(state);
    await search(tester, state, 'g40');
    expect(find.textContaining('Word studies · 1 Hebrew and Greek word'), findsOneWidget);
    expect(find.textContaining("the Strong's number you typed"), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Word studies'), findsNothing);
    expect(find.byTooltip('Clear'), findsNothing);
  });
  testWidgets('an empty box says what Search does, and an example runs when tapped', (tester) async {
    final state = (await tester.runAsync(open))!;
    addHolyWords(state);
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: bereaTheme(Brightness.light), home: SearchScreen(state: state)),
    );
    expect(find.textContaining('Look a word up in the verses'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'G26'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'G26');
    await tester.runAsync(() => Future<void>.delayed(_searchWait));
    await tester.pumpAndSettle();
    expect(find.textContaining('Look a word up in the verses'), findsNothing);
    expect(find.textContaining('Word studies ·'), findsNothing, reason: 'G26 is not in the fixture');
    expect(find.text('No verse in the BSB has those words.'), findsOneWidget);
  });
}
