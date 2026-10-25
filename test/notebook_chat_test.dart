import 'dart:async';
import 'dart:io';

import 'package:berea/backup.dart';
import 'package:berea/notebook_chat.dart';
import 'package:berea/notebook_chat_screen.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/bible.dart';

/// Writes the same answer every time, as a model told to cite the guide would.
class _Scripted implements LlmEngine {
  final String text;
  _Scripted(this.text);

  @override
  String get name => 'scripted';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    yield text;
  }
}

const _pages = [
  'Week one. The group meets on Thursday evenings.',
  'Week two. The guide names three habits of a Berean.',
];

/// PDFs are made of [_pages] here, so no PDFium is needed.
Future<ChunkedText> _ingest(SourceRequest r) async =>
    r.kind == SourceKind.pdf ? chunkSections(_pages, paged: true) : ingestSource(r);

void main() {
  late StudyStore study;
  late NotebookStore store;

  setUp(() {
    study = StudyStore(sqlite3.openInMemory());
    store = NotebookStore(study.db, ingest: _ingest);
  });

  group('conversation store', () {
    test('a conversation is saved per notebook, with what each answer cited', () async {
      final a = store.createNotebook('A');
      final b = store.createNotebook('B');
      final cited = ShownSource(
        'S7 p.2',
        const SourceChunk(
          sourceId: 7,
          title: 'Guide.pdf',
          kind: SourceKind.pdf,
          ordinal: 1,
          page: 2,
          text: '',
        ),
      );
      store.addMessage(a, 'user', 'What habits?');
      store.addMessage(
        a,
        'assistant',
        'Three [S7 p.2].',
        refs: RefParser.parse('John 3:16'),
        sources: [cited],
      );
      store.addMessage(b, 'user', 'Other notebook');
      final saved = store.messages(a);
      expect(saved.map((m) => m.role), ['user', 'assistant']);
      expect(saved.last.refs.single.label, 'John 3:16');
      expect(saved.last.sources.single.tag, 'S7 p.2');
      expect(saved.last.sources.single.chunk.page, 2);

      store.clearMessages(a);
      expect(store.messages(a), isEmpty);
      expect(store.messages(b), hasLength(1));
      store.deleteNotebook(b);
      expect(study.db.select('SELECT * FROM notebook_messages'), isEmpty);
      expect(store.addMessage(b, 'user', 'Too late'), isFalse);
    });

    test('pins are kept per source', () async {
      final nb = store.createNotebook('N');
      final id = (await store.addSource(
        nb,
        const SourceRequest(SourceKind.text, 'T', text: 'Grace.'),
      ))!;
      expect(store.sources(nb).single.pinned, isFalse);
      store.setPinned(id, true);
      expect(store.sources(nb).single.pinned, isTrue);
      expect(store.pinnedSources(nb), [id]);
      expect(store.source(id)!.pinned, isTrue);
      expect(store.source(id + 1), isNull);
    });

    test('a study.sqlite with notebooks but no conversations gains them and keeps its sources', () {
      final dir = Directory.systemTemp.createTempSync('berea_chat_migrate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/study.sqlite';
      final old = sqlite3.open(path)
        ..execute(notebookSchema)
        ..execute('PRAGMA user_version = 1')
        ..execute("INSERT INTO notebooks(title, created, updated) VALUES ('Kept', 0, 0)")
        ..execute(
          'INSERT INTO notebook_sources(notebook_id, kind, title, origin, text, created) '
          "VALUES (1, 'text', 'T', '', 'Grace.', 0)",
        );
      old.dispose();
      final upgraded = StudyStore.open(path);
      addTearDown(upgraded.close);
      expect(upgraded.db.select('PRAGMA user_version').first.values.first, 2);
      final books = NotebookStore(upgraded.db);
      expect(books.sources(1).single.pinned, isFalse);
      expect(books.messages(1), isEmpty);
    });
  });

  group('backup', () {
    Future<Map<String, List<Map<String, Object?>>>> backedUp() async {
      final bytes = await createBackup(study, const {}, 'correct horse');
      return (await readBackup(bytes, 'correct horse')).tables;
    }

    test('conversations and pins round trip in a version 2 backup', () async {
      final nb = store.createNotebook('N');
      final id = (await store.addSource(
        nb,
        const SourceRequest(SourceKind.text, 'T', text: 'Grace.'),
      ))!;
      store.setPinned(id, true);
      store.addMessage(nb, 'user', 'Q');
      store.addMessage(
        nb,
        'assistant',
        'A [S1 §1].',
        sources: [
          ShownSource(
            'S$id §1',
            SourceChunk(sourceId: id, title: 'T', kind: SourceKind.text, ordinal: 0, text: ''),
          ),
        ],
      );
      final tables = await backedUp();
      final target = StudyStore(sqlite3.openInMemory());
      final books = NotebookStore(target.db);
      target.importTables(tables);
      expect(books.messages(nb).last.sources.single.chunk.sourceId, id);
      expect(books.sources(nb).single.pinned, isTrue);
    });

    test(
      'a backup with notebooks but no conversations clears them; one without notebooks keeps them',
      () async {
        final nb = store.createNotebook('N');
        final tables = await backedUp();
        final target = StudyStore(sqlite3.openInMemory());
        final books = NotebookStore(target.db);
        final mine = books.createNotebook('Mine');
        books.addMessage(mine, 'user', 'Kept?');

        target.importTables({
          for (final e in tables.entries)
            if (![
              'notebooks',
              'notebook_sources',
              'notebook_chunks',
              'notebook_messages',
            ].contains(e.key))
              e.key: e.value,
        });
        expect(books.messages(mine), hasLength(1));

        target.importTables({...tables}..remove('notebook_messages'));
        expect(target.db.select('SELECT * FROM notebook_messages'), isEmpty);
        expect(books.notebooks().single.id, nb);
      },
    );

    test('conversation rows that do not fit are rejected before anything changes', () async {
      final nb = store.createNotebook('N');
      await store.addSource(nb, const SourceRequest(SourceKind.text, 'T', text: 'Grace.'));
      store.addMessage(nb, 'user', 'Q');
      final good = await backedUp();
      Map<String, List<Map<String, Object?>>> edited(String table, Map<String, Object?> change) => {
        ...good,
        table: [
          for (final r in good[table]!) {...r, ...change},
        ],
      };
      for (final bad in [
        edited('notebook_messages', {'notebook_id': 42}),
        edited('notebook_messages', {'sources': '{}'}),
        edited('notebook_messages', {'refs': 'nope'}),
        edited('notebook_messages', {'text': null}),
        edited('notebook_sources', {'pinned': 7}),
        edited('notebook_sources', {'pinned': null}),
        edited('notebook_messages', {'role': 'system'}),
        {'notebook_messages': good['notebook_messages']!},
      ]) {
        expect(() => study.importTables(bad), throwsFormatException, reason: '$bad');
      }
      expect(store.messages(nb).single.text, 'Q');
    });
  });

  group('chat screen', () {
    late BibleDb bible;
    late int nb;
    setUp(() => bible = testBible());

    NotebookChat chatWith(String answer) {
      final harness = Harness(
        db: bible,
        engine: _Scripted(answer),
        systemPrompt: 'SYS',
        notebook: true,
      );
      return NotebookChat(
        store: store,
        notebookId: nb,
        ready: () => true,
        answer: (q, history, onToken) {
          harness.history
            ..clear()
            ..addAll(history);
          final sources = notebookSources(
            index: NotebookIndex(store.db, nb),
            question: q,
            tier: Tier.mid,
          );
          return harness.ask(q, sources: sources, onToken: onToken);
        },
      );
    }

    Widget screen(NotebookChat chat, {String? Function()? privacy}) => MaterialApp(
      home: NotebookChatScreen(
        store: store,
        notebookId: nb,
        chat: chat,
        db: bible,
        translation: () => 'BSB',
        commentary: CommentaryLibrary(),
        privacyNotice: privacy,
      ),
    );

    Future<void> ask(WidgetTester tester, String question) async {
      await tester.enterText(find.byType(TextField), question);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    testWidgets('source citations are chips that open the source at the cited page', (
      tester,
    ) async {
      late int guide;
      await tester.runAsync(() async {
        nb = store.createNotebook('Bereans');
        await store.addSource(nb, const SourceRequest(SourceKind.text, 'Notes', text: 'Test it.'));
        guide = (await store.addSource(
          nb,
          const SourceRequest(SourceKind.pdf, 'Guide.pdf', path: 'x'),
        ))!;
      });
      await tester.pumpWidget(
        screen(
          chatWith(
            'The guide names three habits [S$guide p.2]. John 3:16 shows the love of God. '
            'Page 9 says more [S$guide p.9].',
          ),
        ),
      );
      expect(find.text('Ask about your sources'), findsOneWidget);
      await ask(tester, 'What habits does the guide name?');

      expect(find.textContaining('S$guide p.2 · Guide.pdf'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'John 3:16'), findsOneWidget);
      expect(find.textContaining('Not among the sources shown: S$guide p.9'), findsOneWidget);
      expect(find.textContaining('[unverified source: S$guide p.9]'), findsOneWidget);

      await tester.tap(find.textContaining('S$guide p.2 · Guide.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE 2'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cited-section')),
          matching: find.text(_pages[1]),
        ),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Verse chips still open the passage.
      await tester.tap(find.widgetWithText(ActionChip, 'John 3:16'));
      await tester.pumpAndSettle();
      expect(find.textContaining('For God so loved the world'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // The conversation and its chips come back when the notebook's chat is opened again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(chatWith('unused')));
      await tester.pumpAndSettle();
      expect(find.text('What habits does the guide name?'), findsOneWidget);
      expect(find.textContaining('S$guide p.2 · Guide.pdf'), findsOneWidget);

      // A chip whose source was removed says so instead of opening nothing.
      store.removeSource(guide);
      await tester.tap(find.textContaining('S$guide p.2 · Guide.pdf'));
      await tester.pump();
      expect(find.text('That source has been removed from the notebook.'), findsOneWidget);
    });

    testWidgets('a chip whose source id now names another source does not open it', (tester) async {
      late int notes;
      await tester.runAsync(() async {
        nb = store.createNotebook('Restored');
        notes = (await store.addSource(
          nb,
          const SourceRequest(SourceKind.text, 'Notes', text: 'Test it.'),
        ))!;
      });
      await tester.pumpWidget(screen(chatWith('Test everything [S$notes §1].')));
      await ask(tester, 'What do my notes say?');
      study.db.execute("UPDATE notebook_sources SET title = 'Someone else' WHERE id = ?", [notes]);
      await tester.tap(find.textContaining('S$notes §1 · Notes'));
      await tester.pump();
      expect(find.text('That source is no longer in this notebook.'), findsOneWidget);
    });

    testWidgets('an answer that finishes after the screen closed is there when it opens again', (
      tester,
    ) async {
      nb = store.createNotebook('Late');
      final gate = Completer<void>();
      final harness = Harness(db: bible, engine: _Scripted('Late answer.'), systemPrompt: 'SYS');
      final chat = NotebookChat(
        store: store,
        notebookId: nb,
        ready: () => true,
        answer: (q, history, onToken) async {
          await gate.future;
          return harness.ask(q);
        },
      );
      await tester.pumpWidget(
        screen(chat, privacy: () => 'Questions here go to the Ollama server at example.org.'),
      );
      expect(find.textContaining('Ollama server at example.org'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Slow question');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(store.messages(nb).map((m) => m.text), ['Slow question', 'Late answer.']);
      await tester.pumpWidget(screen(chat));
      await tester.pumpAndSettle();
      expect(find.text('Late answer.'), findsOneWidget);
    });

    testWidgets('a busy engine leaves the question unanswered and says why', (tester) async {
      nb = store.createNotebook('Busy');
      await tester.pumpWidget(
        MaterialApp(
          home: NotebookChatScreen(
            store: store,
            notebookId: nb,
            chat: NotebookChat(
              store: store,
              notebookId: nb,
              ready: () => true,
              answer: (q, history, onToken) async => null,
            ),
            db: bible,
            translation: () => 'BSB',
            commentary: CommentaryLibrary(),
          ),
        ),
      );
      await ask(tester, 'Anything?');
      expect(find.text(engineBusyMessage), findsOneWidget);
      expect(store.messages(nb), isEmpty);
    });
  });
}
