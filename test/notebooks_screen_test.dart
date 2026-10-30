import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/brand/lamp_mark.dart';
import 'package:berea/keep_sheet.dart';
import 'package:berea/note_dialog.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/notebook_ask_panel.dart';
import 'package:berea/notebooks_screen.dart';
import 'package:berea/study_packet_screen.dart';
import 'package:berea/notes_screen.dart';
import 'package:berea/voice_composer.dart';
import 'package:berea/study_store.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'commentary_test.dart' show writePack;
import 'support/bible.dart';

const _phone = Size(600, 1000);
const _mac = Size(1280, 800);

void main() {
  if (needsBuiltBible case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppState s;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('berea-notes-test');
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
    s = await AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  /// Every test starts with no notebooks, notes or study pages.
  setUp(() {
    s.study.db.execute('DELETE FROM notes');
    s.study.db.execute('DELETE FROM study_pages');
    s.prefs.remove(lastKeptNotebookKey);
    for (final n in s.notebooks.notebooks()) {
      s.notebooks.deleteNotebook(n.id);
    }
  });

  Future<void> pump(WidgetTester tester, Widget home, {Size size = _phone}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: bereaTheme(Brightness.light), home: home));
  }

  Ref ref(String r) => RefParser.parse(r).single;

  testWidgets('Notes shows the notebooks row with New, and Recent labelled by notebook', (
    tester,
  ) async {
    final sermons = s.notebooks.createNotebook('Sunday sermons');
    s.study.addNotebookNote(sermons, 'Romans 8:18 and Romans 8:28.', title: 'Pastor on Romans 8');
    s.study.addNote(ref('John 3:16'), 'He gave, not only felt.');
    s.study.addNotebookNote(
      sermons,
      keptWordBody(code: 'G25', meaning: 'to love', from: ref('John 3:16')),
      title: 'ἀγαπάω, to love',
      kind: keptWordKind,
    );
    s.study.saveStudyPage(ref('Romans 8:28-30'), 'Paul moves', '', '', notebookId: sermons);
    await tester.runAsync(
      () => s.notebooks.addSource(
        sermons,
        const SourceRequest(SourceKind.text, 'Outline', text: 'What we suffer.'),
      ),
    );
    s.touch();
    await pump(tester, NotesScreen(state: s));

    expect(find.text('NOTEBOOKS'), findsOneWidget);
    expect(find.text('Sunday sermons'), findsOneWidget);
    expect(find.text(notesOnVersesTitle), findsOneWidget);
    expect(find.text('New notebook'), findsOneWidget);
    expect(find.text('3 notes · 1 reading'), findsOneWidget);

    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('NOTE · SUNDAY SERMONS'), findsOneWidget);
    expect(find.textContaining('Romans 8:18 · Romans 8:28 ·'), findsOneWidget);
    expect(find.text('NOTE ON A VERSE · NOTES ON VERSES'), findsOneWidget);
    expect(find.text('KEPT WORD · SUNDAY SERMONS'), findsOneWidget);
    expect(find.text('STUDY PAGE · SUNDAY SERMONS'), findsOneWidget);
    expect(find.text('READING · SUNDAY SERMONS'), findsOneWidget);
    expect(find.text('Write'), findsOneWidget);

    // A card opens its notebook.
    await tester.tap(find.text('Sunday sermons'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookScreen), findsOneWidget);
  });

  testWidgets('a notebook shows Everything, Notes and Readings, with Add and Ask', (
    tester,
  ) async {
    final nb = s.notebooks.createNotebook('Romans with the youth');
    s.study.addNotebookNote(nb, 'What we suffer.', title: 'Outline for Thursday');
    await tester.runAsync(
      () => s.notebooks.addSource(
        nb,
        const SourceRequest(SourceKind.text, 'Romans study notes', text: 'Notes on chapter 8.'),
      ),
    );
    await pump(tester, NotebookScreen(state: s, notebookId: nb));

    expect(find.text('1 note · 1 reading'), findsOneWidget);
    expect(find.text('Everything'), findsOneWidget);
    expect(find.text('Notes 1'), findsOneWidget);
    expect(find.text('Readings 1'), findsOneWidget);
    expect(find.text('Outline for Thursday'), findsOneWidget);
    expect(find.text('Romans study notes'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    await tester.tap(find.text('Notes 1'));
    await tester.pumpAndSettle();
    expect(find.text('Outline for Thursday'), findsOneWidget);
    expect(find.text('Romans study notes'), findsNothing);

    await tester.tap(find.text('Readings 1'));
    await tester.pumpAndSettle();
    expect(find.text('Outline for Thursday'), findsNothing);
    expect(find.text('Romans study notes'), findsOneWidget);

    // Pins still steer scoped answers: a reading is pinned and shown as always included.
    await tester.tap(find.byTooltip('Include in every answer'));
    await tester.pumpAndSettle();
    expect(s.notebooks.pinnedSources(nb), hasLength(1));
    expect(find.textContaining('Always included'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.push_pin));
    await tester.pumpAndSettle();
    expect(s.notebooks.pinnedSources(nb), isEmpty);

    // Add offers writing a note beside the kinds of reading.
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Write a note'), findsOneWidget);
    expect(find.text('Bible passage'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    final asked = s.openStudyRequest.value;
    await tester.tap(find.text('Ask about this notebook'));
    expect(s.studyScope.value, nb);
    expect(s.openStudyRequest.value, asked + 1);
    s.studyScope.value = null;
  });

  testWidgets('a source being read shows progress until it is saved', (tester) async {
    final id = s.notebooks.createNotebook('Pending');
    s.notebooks.pending.add(PendingSource(0, SourceKind.pdf, 'other notebook'));
    s.notebooks.pending.add(PendingSource(id, SourceKind.pdf, 'Big book.pdf'));
    addTearDown(s.notebooks.pending.clear);
    await pump(tester, NotebookScreen(state: s, notebookId: id));
    expect(find.text('Big book.pdf'), findsOneWidget);
    expect(find.text('other notebook'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('the editor saves a note with no verse into the chosen notebook', (tester) async {
    s.notebooks.createNotebook('Romans with the youth');
    final sermons = s.notebooks.createNotebook('Sunday sermons');
    await pump(tester, NotesScreen(state: s));
    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditor), findsOneWidget);

    await tester.tap(find.byTooltip('Choose a notebook'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunday sermons').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Pastor on Romans 8');
    await tester.enterText(find.byType(TextField).last, 'Read Romans 8:18 again.');
    await tester.pump();
    // The typed reference shows its verse, a tap from the reader.
    expect(find.text('tap to open'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final note = s.study.notebookNotes(sermons).single;
    expect(note.title, 'Pastor on Romans 8');
    expect(note.text, 'Read Romans 8:18 again.');
    expect(note.verse, isNull);
    expect(find.text('NOTE · SUNDAY SERMONS'), findsOneWidget);
  });

  testWidgets('opening the verse preview asks before it drops what was written', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showNoteEditor(context, s),
          child: const Text('Write'),
        ),
      ),
    );
    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Read Romans 8:18 again.');
    await tester.pump();

    await tester.tap(find.text('tap to open'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this note?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditor), findsOneWidget);
    expect(find.text('Read Romans 8:18 again.'), findsOneWidget);

    await tester.tap(find.text('tap to open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditor), findsNothing);
    expect(s.study.notes(), isEmpty);
  });

  testWidgets('the editor saves a note on a verse, and edits keep it', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showNoteDialog(context, s, ref: ref('John 3:16')),
          child: const Text('Note'),
        ),
      ),
    );
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    expect(find.text('On John 3:16'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Love measured by a gift.');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final note = s.study.notes().single;
    expect(note.verse!.label, 'John 3:16');
    expect(s.notebooks.notebook(note.notebookId!)!.title, notesOnVersesTitle);

    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showNoteEditor(context, s, note: note),
          child: const Text('Edit'),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Love given.');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(s.study.note(note.id)!.text, 'Love given.');
    expect(s.study.note(note.id)!.verse!.label, 'John 3:16');
  });

  testWidgets('typed references are styled as links', (tester) async {
    late TextSpan span;
    await pump(
      tester,
      Builder(
        builder: (context) {
          span = RefLinkController(text: 'See Romans 8:28 and 2 Cor 4:16-18 today.')
              .buildTextSpan(context: context, withComposing: false);
          return const SizedBox();
        },
      ),
    );
    final links = [
      for (final c in span.children!.cast<TextSpan>())
        if (c.style?.decoration == TextDecoration.underline) c.text,
    ];
    expect(links, ['Romans 8:28', '2 Cor 4:16-18']);
  });

  testWidgets('Keep in a notebook files an answer as a note in the chosen notebook', (
    tester,
  ) async {
    final youth = s.notebooks.createNotebook('Romans with the youth');
    s.notebooks.createNotebook('Sunday sermons');
    int? kept;
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => kept = await showKeepSheet(
            context,
            s,
            title: 'How does Romans 8:28 fit 8:18?',
            body: 'Paul does not call suffering good.',
            verse: ref('Romans 8:28'),
          ),
          child: const Text('Keep'),
        ),
      ),
    );
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('IN A NOTEBOOK'), findsOneWidget);
    expect(find.text(notesOnVersesTitle), findsOneWidget);
    expect(find.text('New notebook'), findsOneWidget);
    expect(find.text('Show it beside Romans 8:28'), findsOneWidget);
    await tester.tap(find.text('Romans with the youth'));
    await tester.tap(find.text('Show it beside Romans 8:28'));
    await tester.tap(find.widgetWithText(FilledButton, 'Keep'));
    await tester.pumpAndSettle();

    final note = s.study.note(kept!)!;
    expect(note.notebookId, youth);
    expect(note.title, 'How does Romans 8:28 fit 8:18?');
    expect(note.verse, isNull);
  });

  Future<void> openKeep(WidgetTester tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showKeepSheet(context, s, title: 'agapao', body: 'to love'),
          child: const Text('Keep'),
        ),
      ),
    );
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
  }

  testWidgets('Keep in a notebook offers the notebook last kept in first', (tester) async {
    final sermons = s.notebooks.createNotebook('Sunday sermons');
    s.notebooks.createNotebook('Romans with the youth');
    await openKeep(tester);
    expect(find.textContaining('Last used'), findsNothing);
    await tester.tap(find.text('Sunday sermons'));
    await tester.tap(find.widgetWithText(FilledButton, 'Keep'));
    await tester.pumpAndSettle();
    expect(s.prefs.getInt(lastKeptNotebookKey), sermons);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('Last used · 1 note'), findsOneWidget);
    final tiles = find.byType(RadioListTile<int>);
    expect(find.descendant(of: tiles.first, matching: find.text('Sunday sermons')), findsOneWidget);
    final first = tester.widget<RadioListTile<int>>(tiles.first);
    expect(first.value, sermons);
    expect(tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue, sermons);
  });

  testWidgets('a deleted last used notebook is not offered', (tester) async {
    final gone = s.notebooks.createNotebook('Gone');
    s.notebooks.createNotebook('Sunday sermons');
    await s.prefs.setInt(lastKeptNotebookKey, gone);
    s.notebooks.deleteNotebook(gone);
    await openKeep(tester);
    expect(find.textContaining('Last used'), findsNothing);
    expect(find.text('Gone'), findsNothing);
  });

  Future<void> openEditor(WidgetTester tester, {Ref? verse, Note? note}) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showNoteEditor(context, s, verse: verse, note: note),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Pray this opens the new prayer sheet with the note verse', (tester) async {
    await openEditor(tester, verse: ref('John 3:16'));
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Love that gives');
    await tester.tap(find.text('Pray this'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'John 3:16'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Love that gives'), findsNWidgets(2));
  });

  testWidgets('Pray this leaves out a verse that is a whole chapter', (tester) async {
    await openEditor(tester, verse: ref('Romans 8'));
    await tester.enterText(find.byType(TextField).last, 'For those who suffer this week.');
    await tester.tap(find.text('Pray this'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Romans 8'), findsNothing);
    // With no title, the note's first words are what is prayed for.
    expect(find.widgetWithText(TextField, 'For those who suffer this week.'), findsNWidgets(2));
  });

  testWidgets('the editor microphone shows only when the device model can hear', (tester) async {
    await openEditor(tester);
    expect(canDictate(s), isFalse, reason: 'tests run on Ollama, which cannot transcribe');
    expect(find.byType(VoiceMicButton), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, NoteEditor(state: s, dictates: (_) => true));
    expect(find.byType(VoiceMicButton), findsOneWidget);
  });

  test('dictation goes in at the cursor, or at the end', () {
    const typed = TextEditingValue(
      text: 'Read again.',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(withDictation(typed, 'Romans 8').text, 'Read Romans 8 again.');
    expect(withDictation(const TextEditingValue(text: 'Read'), 'it').text, 'Read it');
    expect(withDictation(TextEditingValue.empty, 'Hope').text, 'Hope');
  });

  testWidgets('wide Notes shows the chosen entry beside the list', (tester) async {
    final sermons = s.notebooks.createNotebook('Sunday sermons');
    s.study.addNotebookNote(
      sermons,
      'Suffering is not the last word.',
      title: 'Pastor on Romans 8',
    );
    s.study.saveStudyPage(
      ref('Romans 8:28-30'),
      'Paul moves',
      'God works',
      '',
      notebookId: sermons,
    );
    await tester.runAsync(
      () => s.notebooks.addSource(
        sermons,
        const SourceRequest(SourceKind.text, 'Outline', text: 'What we suffer.'),
      ),
    );
    await pump(tester, NotesScreen(state: s), size: _mac);
    expect(find.byType(ListAndDetail), findsOneWidget);
    expect(find.text('Choose a note to read it here.'), findsOneWidget);

    await tester.tap(find.text('Pastor on Romans 8'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditor), findsNothing);
    expect(find.widgetWithText(SelectableText, 'Suffering is not the last word.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);

    await tester.tap(find.text('Romans 8:28-30'));
    await tester.pumpAndSettle();
    expect(find.text('Interpretation'), findsOneWidget);
    expect(find.text('Open Romans 8:28-30 in the Bible'), findsOneWidget);

    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('What we suffer.'), findsOneWidget);

    // Edit opens the editor, and the panel shows what was saved.
    await tester.tap(find.text('Pastor on Romans 8'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Hope is.');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, 'Hope is.'), findsOneWidget);
  });

  testWidgets('a wide notebook shows its views beside the chosen entry', (tester) async {
    final nb = s.notebooks.createNotebook('Romans with the youth');
    s.study.addNotebookNote(nb, 'What we suffer.', title: 'Outline for Thursday');
    await pump(tester, NotebookScreen(state: s, notebookId: nb), size: _mac);
    expect(find.byType(ListAndDetail), findsOneWidget);
    expect(find.text('Everything'), findsOneWidget);
    expect(find.byType(NotebookAskPanel), findsOneWidget);

    await tester.tap(find.text('Outline for Thursday'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditor), findsNothing);
    expect(find.widgetWithText(SelectableText, 'What we suffer.'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Outline for Thursday')).selected,
      isTrue,
    );

    await tester.tap(find.text('Readings 0'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookAskPanel), findsOneWidget);
    await tester.tap(find.text('Everything'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, 'What we suffer.'), findsOneWidget);

    // A deleted entry leaves the panel.
    s.study.deleteNote(s.study.notebookNotes(nb).single.id);
    s.notebooks.renameNotebook(nb, 'Romans 8');
    await tester.pumpAndSettle();
    expect(find.byType(NotebookAskPanel), findsOneWidget);
  });

  testWidgets('on a wide screen Ask about this notebook brings its conversation back beside it', (
    tester,
  ) async {
    final nb = s.notebooks.createNotebook('Romans with the youth');
    s.study.addNotebookNote(nb, 'What we suffer.', title: 'Outline for Thursday');
    await pump(tester, NotebookScreen(state: s, notebookId: nb), size: _mac);
    await tester.tap(find.text('Outline for Thursday'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookAskPanel), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Ask about this notebook'));
    await tester.pumpAndSettle();
    expect(find.byType(NotebookAskPanel), findsOneWidget);
    final box = find.descendant(
      of: find.byType(NotebookAskPanel),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(box).focusNode!.hasFocus, isTrue);
    expect(s.studyScope.value, isNot(nb), reason: 'Study is scoped only once a question is asked');
  });

  testWidgets('on a phone Ask about this notebook scopes Study to it', (tester) async {
    final nb = s.notebooks.createNotebook('Romans with the youth');
    await pump(tester, NotebookScreen(state: s, notebookId: nb));
    await tester.tap(find.widgetWithText(FilledButton, 'Ask about this notebook'));
    await tester.pump();
    expect(s.studyScope.value, nb);
    s.setStudyScope(null);
  });

  testWidgets('the phone layout keeps opening entries on their own', (tester) async {
    final nb = s.notebooks.createNotebook('Romans with the youth');
    s.study.addNotebookNote(nb, 'What we suffer.', title: 'Outline for Thursday');
    await pump(tester, NotebookScreen(state: s, notebookId: nb));
    expect(find.byType(ListAndDetail), findsNothing);
    await tester.tap(find.text('Outline for Thursday'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditor), findsOneWidget);
  });

  testWidgets('a passage reading shows its translation and verses, and Ask shows the mark', (
    tester,
  ) async {
    final nb = s.notebooks.createNotebook('Romans with the youth');
    final translation = s.settings.translation;
    final passage = passageSource(s.db, 'Romans 8:18-20', translation)!;
    await tester.runAsync(() => s.notebooks.addSource(nb, passage));
    await pump(tester, NotebookScreen(state: s, notebookId: nb));
    expect(find.text('Romans 8:18-20'), findsOneWidget);
    expect(find.text('$translation · 3 verses'), findsOneWidget);
    final ask = find.widgetWithText(FilledButton, 'Ask about this notebook');
    expect(find.descendant(of: ask, matching: find.byType(LampMark)), findsOneWidget);
  });

  testWidgets('the Keep sheet counts only what a notebook holds', (tester) async {
    final youth = s.notebooks.createNotebook('Romans with the youth');
    s.notebooks.createNotebook('Empty one');
    s.study.addNotebookNote(youth, 'What we suffer.');
    await tester.runAsync(
      () => s.notebooks.addSource(
        youth,
        const SourceRequest(SourceKind.text, 'Outline', text: 'Notes on chapter 8.'),
      ),
    );
    await openKeep(tester);
    expect(find.text('1 note, 1 reading'), findsOneWidget);
    expect(find.text('Nothing in it yet'), findsOneWidget);
  });

  testWidgets('a long passage is kept whole, past the prompt cap', (tester) async {
    final nb = s.notebooks.createNotebook('Long chapters');
    final translation = s.settings.translation;
    await tester.runAsync(
      () => s.notebooks.addSource(nb, passageSource(s.db, 'Genesis 24', translation)!),
    );
    await pump(tester, NotebookScreen(state: s, notebookId: nb));
    expect(find.text('$translation · 67 verses'), findsOneWidget);
  });

  testWidgets('Synthesize gathers the sections, words and witnesses of the readings', (
    tester,
  ) async {
    final nb = s.notebooks.createNotebook('Nicodemus');
    await tester.runAsync(
      () => s.notebooks.addSource(nb, passageSource(s.db, 'John 3:1-21', 'BSB')!),
    );
    s.study.addNotebookNote(nb, 'Light and darkness.', title: 'On light');
    await pump(tester, NotebookScreen(state: s, notebookId: nb));
    await tester.tap(find.byTooltip('Synthesize'));
    await tester.pumpAndSettle();
    expect(find.text('Jesus and Nicodemus'), findsOneWidget);
    expect(find.text('John 3:1-21 · 21 verses'), findsOneWidget);
    expect(find.textContaining('No commentaries are downloaded yet'), findsOneWidget);
    expect(find.text('Download in Settings'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Key words'), 200);
    expect(find.textContaining('"to beget"'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Witnesses from the other testament'), 200);
  });

  testWidgets('Synthesize on a notebook with no passages says what to add', (tester) async {
    final nb = s.notebooks.createNotebook('Sermon notes');
    s.study.addNotebookNote(nb, 'No verse here.', title: 'Thoughts');
    await pump(tester, NotebookScreen(state: s, notebookId: nb));
    await tester.tap(find.byTooltip('Synthesize'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing to synthesize yet'), findsOneWidget);
  });

  testWidgets('Synthesize on a phone groups commentary by work and reads cleanly at 360', (
    tester,
  ) async {
    final pack = writePack(dir, 'core', [
      ['MHCC', 43, 3, 1, 1, 'Nicodemus was a Pharisee.'],
      ['MHCC', 43, 3, 3, 3, 'Born again means born from above.'],
    ]);
    s.commentary.library.open('core', pack);
    addTearDown(() => s.commentary.library.closeAll());
    final nb = s.notebooks.createNotebook('Nicodemus');
    await tester.runAsync(
      () => s.notebooks.addSource(nb, passageSource(s.db, 'John 3:1-21', 'BSB')!),
    );
    await pump(tester, StudyPacketScreen(state: s, notebookId: nb), size: const Size(360, 800));
    expect(tester.takeException(), isNull, reason: 'no overflow on a narrow phone');
    final work = commentaryModuleById('MHCC')!.title;
    expect(find.text(work), findsOneWidget, reason: 'one row for the work, not one per verse');
    expect(find.text('2 comments'), findsOneWidget);
    await tester.ensureVisible(find.text(work));
    await tester.pumpAndSettle();
    await tester.tap(find.text(work));
    await tester.pumpAndSettle();
    expect(find.textContaining('born from above'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Listen'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ask about this notebook'), findsOneWidget);
  });
}
