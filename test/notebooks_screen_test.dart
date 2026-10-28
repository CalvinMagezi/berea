import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/keep_sheet.dart';
import 'package:berea/note_dialog.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/notebooks_screen.dart';
import 'package:berea/notes_screen.dart';
import 'package:berea/study_store.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(600, 1000);

void main() {
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
    for (final n in s.notebooks.notebooks()) {
      s.notebooks.deleteNotebook(n.id);
    }
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = _phone;
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
}
