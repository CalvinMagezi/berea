import 'dart:async';
import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/chat_screen.dart';
import 'package:berea/notebook_chat.dart';
import 'package:berea/notebook_chat_screen.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/study_page_screen.dart';
import 'package:berea/study_store.dart';
import 'package:berea/voice.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/bible.dart';

/// Writes [tokens] one at a time, as a model streams an answer.
class _Tokens implements LlmEngine {
  final Stream<String> tokens;
  _Tokens(this.tokens);

  @override
  String get name => 'tokens';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) => tokens;
}

/// The chat screen needs a voice session; these tests never record.
class _NoRecorder implements AudioRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _tokenCount = 40;
const _frame = Duration(milliseconds: 16);
const _settleFrames = 60;
final _manyTokens = [for (var i = 0; i < _tokenCount; i++) 'word$i '];

ScrollPosition _position(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!.position;

/// The send button spins while the model works, so frames never settle; this gives a scroll
/// that overshot an estimated end time to spring back.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < _settleFrames; i++) {
    await tester.pump(_frame);
  }
}

/// Streams [text] and lets the refresh and the scroll that follows it land.
Future<void> _stream(WidgetTester tester, StreamController<String> tokens, String text) async {
  tokens.add(text);
  await tester.pump(streamRefresh);
  await _frames(tester);
}

final _earlierAnswer = List.filled(4, john316).join(' ');

void main() {
  late Directory dir;
  late BibleDb bible;
  late StudyStore study;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('berea-streaming-test');
    bible = testBible();
    study = StudyStore(sqlite3.openInMemory());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppState app(LlmEngine engine) => AppState()
    ..db = bible
    ..study = study
    ..settings = Settings(engine: EngineKind.device)
    ..voice = VoiceInput(
      transcribe: (_) async => '',
      recorder: _NoRecorder(),
      cacheDir: () async => dir,
    )
    ..harness = Harness(db: bible, engine: engine, systemPrompt: 'SYS');

  group('a streaming turn', () {
    test('tells its listeners at most once per refresh, with every token kept', () {
      fakeAsync((async) {
        final turn = ChatTurn('Q');
        var heard = 0;
        turn.addListener(() => heard++);
        for (final t in ['For ', 'God ', 'so ', 'loved']) {
          turn.append(t);
        }
        expect(turn.answer, 'For God so loved');
        expect(heard, 0);
        async.elapse(streamRefresh);
        expect(heard, 1);
        turn.append(' the world');
        async.elapse(streamRefresh * 3);
        expect(heard, 2);
      });
    });

    test('the checked answer replaces a pending refresh', () {
      fakeAsync((async) {
        final turn = ChatTurn('Q');
        var heard = 0;
        turn.addListener(() => heard++);
        turn.append('John 3:16');
        const nothingShown = StudyContext(
          refs: [],
          passages: [],
          words: [],
          lexicon: {},
          xrefVerses: [],
          searchHits: [],
        );
        turn.take(CitationGuard(bible).apply('John 3:16', nothingShown));
        expect(heard, 1);
        expect(turn.done, isTrue);
        async.elapse(streamRefresh * 3);
        expect(heard, 1);
      });
    });
  });

  test('a Study answer tells the app twice however many tokens it has', () async {
    final s = app(_Tokens(Stream.fromIterable(_manyTokens)));
    var changes = 0;
    s.addListener(() => changes++);
    await s.send('What does John 3:16 mean?');
    expect(changes, 2);
    expect(s.turns.single.answer, _manyTokens.join());
    expect(study.messages(s.conversationId!).last.text, _manyTokens.join());
  });

  test('a notebook answer tells its chat twice however many tokens it has', () async {
    final store = NotebookStore(study.db);
    final harness = Harness(
      db: bible,
      engine: _Tokens(Stream.fromIterable(_manyTokens)),
      systemPrompt: 'SYS',
      notebook: true,
    );
    final chat = NotebookChat(
      store: store,
      notebookId: store.createNotebook('Grace'),
      ready: () => true,
      answer: (q, history, onToken) => harness.ask(q, onToken: onToken),
    );
    var changes = 0;
    chat.addListener(() => changes++);
    await chat.send('What is grace?');
    expect(changes, 2);
    expect(chat.turns.single.answer, _manyTokens.join());
  });

  testWidgets('a streaming answer shows as it grows and stays in view unless scrolled away', (
    tester,
  ) async {
    final tokens = StreamController<String>();
    final s = app(_Tokens(tokens.stream));
    for (var i = 0; i < 8; i++) {
      s.turns.add(
        ChatTurn('Earlier question $i')
          ..answer = _earlierAnswer
          ..done = true,
      );
    }
    await tester.pumpWidget(MaterialApp(home: ChatScreen(state: s)));
    ScrollPosition position() => _position(tester);
    Future<void> frames() => _frames(tester);

    await tester.enterText(find.byType(TextField), 'What is grace?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await frames();
    expect(position().pixels, position().maxScrollExtent);

    var appChanges = 0;
    s.addListener(() => appChanges++);
    Future<void> stream(String text) => _stream(tester, tokens, text);

    await stream('Grace is the gift of God.\n\n');
    expect(find.textContaining('Grace is the gift of God.'), findsOneWidget);
    expect(s.turns.last.done, isFalse);
    await stream('It is not earned.\n\nIt is received by faith.\n\n');
    expect(position().pixels, position().maxScrollExtent);

    position().jumpTo(0);
    await stream('It changes how we live.\n\nIt makes us thankful.\n\n');
    expect(position().pixels, 0);
    expect(appChanges, 0);

    // Finishing the answer, or another change such as a saved note, leaves a scrolled-up reader be.
    await tokens.close();
    await tester.pumpAndSettle();
    expect(s.turns.last.done, isTrue);
    expect(s.busy, isFalse);
    expect(position().pixels, 0);
    s.touch();
    await tester.pumpAndSettle();
    expect(position().pixels, 0);

    position().jumpTo(position().maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.textContaining('It makes us thankful.'), findsOneWidget);
  });

  testWidgets('a notebook chat opened while its answer streams follows it', (tester) async {
    final store = NotebookStore(study.db);
    final nb = store.createNotebook('Grace');
    for (var i = 0; i < 8; i++) {
      store.addExchange(nb, 'Earlier question $i', _earlierAnswer, const [], const []);
    }
    final tokens = StreamController<String>();
    final harness = Harness(
      db: bible,
      engine: _Tokens(tokens.stream),
      systemPrompt: 'SYS',
      notebook: true,
    );
    final chat = NotebookChat(
      store: store,
      notebookId: nb,
      ready: () => true,
      answer: (q, history, onToken) => harness.ask(q, onToken: onToken),
    );
    unawaited(chat.send('What is grace?'));
    tokens.add('Grace is the gift of God.\n\n');
    await tester.pump(streamRefresh);

    await tester.pumpWidget(
      MaterialApp(
        home: NotebookChatScreen(
          store: store,
          notebookId: nb,
          chat: chat,
          db: bible,
          translation: () => 'BSB',
          commentary: CommentaryLibrary(),
        ),
      ),
    );
    await _frames(tester);
    expect(find.textContaining('Grace is the gift of God.'), findsOneWidget);
    expect(_position(tester).pixels, _position(tester).maxScrollExtent);

    await _stream(tester, tokens, 'It is not earned.\n\nIt is received by faith.\n\n');
    expect(find.textContaining('It is received by faith.'), findsOneWidget);
    expect(_position(tester).pixels, _position(tester).maxScrollExtent);

    _position(tester).jumpTo(0);
    await _stream(tester, tokens, 'It makes us thankful.\n\n');
    await tokens.close();
    await tester.pumpAndSettle();
    expect(chat.answering, isFalse);
    expect(_position(tester).pixels, 0);
  });

  testWidgets('a study page draft streams in, and closing the page mid-draft leaves it be', (
    tester,
  ) async {
    final tokens = StreamController<String>();
    final s = app(_Tokens(tokens.stream));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => StudyPageScreen(state: s, ref: RefParser.parse('John 3:16').first),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft with Berea'));
    await tester.pump();
    tokens.add('## Observation\n\nGod loved the world.');
    await tester.pump();
    expect(find.textContaining('God loved the world.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    tokens.add(' He gave His Son.');
    await tester.pump();
    // A token that threw on the closed page would have ended the draft's stream early.
    expect(tokens.hasListener, isTrue);
    await tokens.close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(s.busy, isFalse);
  });
}
