import 'package:berea/notebook_store.dart';
import 'package:berea/notebooks_screen.dart';
import 'package:berea/study_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late ValueNotifier<int> changes;
  late NotebookStore store;
  final lookup = SourceLookup(
    notes: () => const [],
    passage: (_) => null,
    commentary: (_) => const [],
    hasCommentary: () => false,
  );

  setUp(() {
    changes = ValueNotifier(0);
    store = NotebookStore(StudyStore(sqlite3.openInMemory()).db, () => changes.value++);
  });

  Widget app() => MaterialApp(
    home: NotebooksScreen(store: store, changes: changes, lookup: lookup),
  );

  testWidgets('with no notebooks the screen says what they are and how to start', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('No notebooks yet'), findsOneWidget);
    expect(find.textContaining('Everything stays on this device'), findsOneWidget);

    await tester.tap(find.text('Create a notebook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Romans 8');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The new notebook opens on its own empty state, with the next step offered.
    expect(find.text('Romans 8'), findsOneWidget);
    expect(find.text('Add your first source'), findsOneWidget);
    expect(find.text('Add a source'), findsOneWidget);
    expect(store.notebooks().single.title, 'Romans 8');
  });

  testWidgets('the list shows each notebook with its source count and opens it', (tester) async {
    final psalms = store.createNotebook('Psalms of ascent');
    store.createNotebook('Grace');
    // Ingestion runs on a real isolate, outside the test's fake clock.
    await tester.runAsync(
      () => store.addSource(
        psalms,
        const SourceRequest(SourceKind.text, 'Psalm 121', text: 'I lift up my eyes to the hills.'),
      ),
    );
    await tester.pumpWidget(app());
    expect(find.text('No notebooks yet'), findsNothing);
    expect(find.text('Psalms of ascent'), findsOneWidget);
    expect(find.textContaining('1 source ·'), findsOneWidget);
    expect(find.textContaining('0 sources ·'), findsOneWidget);

    await tester.tap(find.text('Psalms of ascent'));
    await tester.pumpAndSettle();
    expect(find.text('Psalm 121'), findsOneWidget);
    expect(find.text('Pasted text · 1 section'), findsOneWidget);
    expect(find.text('Add source'), findsOneWidget);
  });

  testWidgets('a source being read shows progress until it is saved', (tester) async {
    final id = store.createNotebook('Pending');
    store.pending.add(const PendingSource(0, SourceKind.pdf, 'other notebook'));
    store.pending.add(PendingSource(id, SourceKind.pdf, 'Big book.pdf'));
    await tester.pumpWidget(
      MaterialApp(
        home: NotebookScreen(store: store, changes: changes, lookup: lookup, notebookId: id),
      ),
    );
    expect(find.text('Big book.pdf'), findsOneWidget);
    expect(find.text('other notebook'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
