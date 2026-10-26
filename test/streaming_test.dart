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
import 'package:shared_preferences/shared_preferences.dart';
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

/// Answers every question with one sentence and records what it was asked. With [hold] the
/// answer stays open until [stop], like a model still writing.
class _Recording implements LlmEngine, StoppableEngine {
  final calls = <List<ChatMessage>>[];
  final limits = <int>[];
  final bool hold;
  var stops = 0;
  StreamController<String>? _open;

  /// Makes the next answer fail, as a model that stopped responding would.
  Object? failNext;

  /// Writes nothing, as when a stop comes before the first word.
  bool silent = false;
  _Recording({this.hold = false});

  @override
  String get name => 'recording';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) {
    calls.add(messages);
    limits.add(maxTokens);
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      return Stream.error(failure);
    }
    final answer = _open = StreamController<String>();
    if (!silent) answer.add('Grace is a gift (John 3:16, BSB).');
    if (!hold) answer.close();
    return answer.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    await _open?.close();
  }
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

  test('a Study turn shows the verses it was given before the model writes a word', () async {
    final tokens = StreamController<String>();
    final s = app(_Tokens(tokens.stream));
    final sent = s.send('What does John 3:16 mean?');
    await pumpEventQueue();
    final turn = s.turns.single;
    expect(turn.answer, isEmpty);
    expect(turn.reading.map((v) => v.label), contains('John 3:16'));
    expect(turn.reading.length, lessThanOrEqualTo(readingVerseLimit));
    await tokens.close();
    await sent;
  });

  group('brief answers and stopping', () {
    const question = 'What does John 3:16 mean?';

    test('a brief answer offers Go deeper, and the full study replaces it in the history', () async {
      final engine = _Recording();
      final s = app(engine)..settings = Settings(engine: EngineKind.device, briefFirst: true);
      await s.send(question);
      final brief = s.turns.single;
      expect(brief.canGoDeeper, isTrue);

      await s.goDeeper(brief);
      final deeper = s.turns.last;
      expect(s.turns, hasLength(2));
      expect(deeper.deeper, isTrue);
      expect(deeper.shownQuestion, goDeeperLabel);
      expect(brief.canGoDeeper, isFalse);
      expect(engine.calls[0].first.content, contains(briefRule));
      expect(engine.calls[1].first.content, isNot(contains(briefRule)));
      expect(engine.limits, [briefMaxOutput, s.harness!.tier.maxOutput]);
      expect(s.harness!.history.map((m) => m.role), ['user', 'assistant']);
      expect(study.messages(s.conversationId!).map((m) => m.text), [
        question,
        brief.answer,
        goDeeperLabel,
        deeper.answer,
      ]);
    });

    test('a full answer offers nothing deeper', () async {
      final s = app(_Recording())..settings = Settings(engine: EngineKind.device, briefFirst: false);
      await s.send(question);
      expect(s.turns.single.canGoDeeper, isFalse);
    });

    test('stopping ends an answer early and keeps what was written', () async {
      final engine = _Recording(hold: true);
      final s = app(engine);
      final sent = s.send(question);
      await pumpEventQueue();
      expect(s.answering, isTrue);

      await s.stopAnswer();
      await sent;
      final turn = s.turns.single;
      expect(engine.stops, 1);
      expect(turn.stopped, isTrue);
      expect(turn.done, isTrue);
      expect(turn.answer, contains('Grace is a gift'));
      expect(s.answering, isFalse);
    });

    test('stopping with nothing being answered does nothing', () async {
      final engine = _Recording();
      final s = app(engine);
      await s.stopAnswer();
      expect(engine.stops, 0);
    });

    test('Go deeper is offered only under the newest answer', () async {
      final engine = _Recording();
      final s = app(engine)..settings = Settings(engine: EngineKind.device, briefFirst: true);
      await s.send(question);
      await s.send('And what about Romans 8:1?');
      final older = s.turns.first;
      expect(s.canGoDeeperFrom(older), isFalse);
      expect(s.canGoDeeperFrom(s.turns.last), isTrue);

      await s.goDeeper(older);
      expect(s.turns, hasLength(2));
      expect(engine.calls, hasLength(2));
      expect(s.harness!.history.map((m) => m.role), ['user', 'assistant', 'user', 'assistant']);
    });

    test('a full study that fails can be tried again and costs the brief answer nothing', () async {
      final engine = _Recording();
      final s = app(engine)..settings = Settings(engine: EngineKind.device, briefFirst: true);
      await s.send(question);
      final brief = s.turns.single;
      engine.failNext = StateError('model gone');

      await s.goDeeper(brief);
      expect(s.turns.last.error, isNotNull);
      expect(brief.canGoDeeper, isTrue);
      expect(s.canGoDeeperFrom(brief), isTrue);
      expect(s.harness!.history.map((m) => m.content), [question, brief.answer]);

      await s.goDeeper(brief);
      expect(s.turns, hasLength(2));
      expect(s.turns.last.error, isNull);
      expect(s.turns.last.deeper, isTrue);
    });

    test('stopping tells the app at once, and a second tap has nothing to stop', () async {
      final engine = _Recording(hold: true);
      final s = app(engine);
      final sent = s.send(question);
      await pumpEventQueue();
      expect(s.canStopAnswer, isTrue);
      var heard = 0;
      s.addListener(() => heard++);

      await s.stopAnswer();
      expect(heard, greaterThan(0));
      expect(s.canStopAnswer, isFalse);
      await s.stopAnswer();
      await sent;
      expect(engine.stops, 1);
    });

    test('the answer that began a question is the one that stops, after a settings change', () async {
      final engine = _Recording(hold: true);
      final s = app(engine);
      final sent = s.send(question);
      await pumpEventQueue();
      s.harness = null;

      await s.stopAnswer();
      await sent;
      expect(engine.stops, 1);
      expect(s.turns.single.stopped, isTrue);
    });

    test('an answer stopped before a word leaves no empty message in the saved study', () async {
      final engine = _Recording(hold: true)..silent = true;
      final s = app(engine);
      final sent = s.send(question);
      await pumpEventQueue();
      await s.stopAnswer();
      await sent;

      expect(s.turns.single.done, isTrue);
      expect(s.turns.single.answer, isEmpty);
      expect(s.conversationId, isNull);
      expect(s.harness!.history, isEmpty);
    });

    test('a second download request while one is under way does nothing', () async {
      final s = app(_Recording());
      final before = s.settings;
      s.deviceState = DeviceModelState.downloading;
      await s.downloadModelFor(Settings(engine: EngineKind.device, tier: Tier.high));
      expect(identical(s.settings, before), isTrue);
    });

    test('brief answers are on by default at the low tier and keep a saved choice', () async {
      expect(Settings(tier: Tier.low).briefFirst, isTrue);
      expect(Settings(tier: Tier.mid).briefFirst, isFalse);
      expect(Settings(tier: Tier.low, briefFirst: false).briefFirst, isFalse);

      // A first run loads the default tier, then moves to the low tier its memory suggests.
      expect(Settings().copyWith(tier: Tier.low).briefFirst, isTrue);
      expect(Settings().copyWith(briefFirst: true).copyWith(tier: Tier.mid).briefFirst, isTrue);

      SharedPreferences.setMockInitialValues({'tier': 'low'});
      final prefs = await SharedPreferences.getInstance();
      expect(Settings.load(prefs).briefFirst, isTrue);
      await Settings.load(prefs).copyWith(briefFirst: false).save(prefs);
      expect(Settings.load(prefs).briefFirst, isFalse);
    });
  });

  testWidgets('an answer stopped before any text says so and stops saying it is working', (
    tester,
  ) async {
    final turn = ChatTurn('What does John 3:16 mean?', style: AnswerStyle.brief)
      ..stopped = true
      ..done = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TurnView(turn: turn, db: bible, translation: 'BSB')),
      ),
    );
    expect(find.text('Stopped before an answer was written.'), findsOneWidget);
    expect(find.text('Examining the Scriptures…'), findsNothing);
  });

  testWidgets('a stop that has not taken effect yet says Stopping', (tester) async {
    final turn = ChatTurn('What does John 3:16 mean?')..stopped = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TurnView(turn: turn, db: bible, translation: 'BSB')),
      ),
    );
    expect(find.text('Stopping…'), findsOneWidget);
    expect(find.text('Examining the Scriptures…'), findsNothing);

    turn.answer = 'Grace is a gift.';
    turn.markStopped();
    await tester.pump();
    expect(find.text('Stopping…'), findsOneWidget);
  });

  testWidgets('Stop shows while an answer is written and Go deeper after a brief one', (
    tester,
  ) async {
    final engine = _Recording(hold: true);
    SharedPreferences.setMockInitialValues({});
    final s = app(engine)
      ..settings = Settings(engine: EngineKind.device, briefFirst: true)
      ..prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(state: s)));
    await tester.enterText(find.byType(TextField), 'What does John 3:16 mean?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _frames(tester);
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Stopped. Finished sentences are kept.'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    final deeper = find.widgetWithText(OutlinedButton, goDeeperLabel);
    expect(deeper, findsOneWidget);

    await tester.tap(deeper);
    await _frames(tester);
    expect(s.turns, hasLength(2));
    expect(deeper, findsNothing);
    expect(find.byTooltip('Stop'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(s.answering, isFalse);
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
