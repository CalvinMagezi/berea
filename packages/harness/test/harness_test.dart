import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

BibleDb _db() {
  final raw = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT);
      CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id');
      CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT, translit TEXT, gloss TEXT, strongs TEXT, morph TEXT);
      CREATE TABLE lexicon(key TEXT, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT, definition TEXT);
      CREATE TABLE xrefs(from_book INTEGER, from_chapter INTEGER, from_verse INTEGER, to_book INTEGER, to_chapter INTEGER, to_verse_start INTEGER, to_verse_end INTEGER, votes INTEGER);
      INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', 43, 3, 16, 'For God so loved the world.');
      INSERT INTO verses_fts(verses_fts) VALUES('rebuild');
    ''');
  return BibleDb(raw);
}

void main() {
  test('study page sections parse and never touch chat history', () async {
    final engine = _Scripted(
      '## Observation\nGod loved.\n## Interpretation\nHe gave.\n'
      '## Application\nBelieve.',
    );
    final h = Harness(db: _db(), engine: engine, systemPrompt: 'SYS');
    final page = await h.studyPage(RefParser.parse('John 3:16').first);
    expect(page.observation, 'God loved.');
    expect(page.interpretation, 'He gave.');
    expect(page.application, 'Believe.');
    expect(h.history, isEmpty);
  });

  test('a stateless engine gets history in the prompt', () async {
    final engine = _Stateless();
    final h = Harness(db: _db(), engine: engine, systemPrompt: 'SYS');
    await h.ask('What does John 3:16 teach?');
    await h.ask('And what follows?');
    expect(engine.calls[1].map((m) => m.role), ['system', 'user', 'assistant', 'user']);
  });

  test('a brief answer adds the length rule and caps what the model may write', () async {
    final engine = _Stateless();
    final h = Harness(db: _db(), engine: engine, systemPrompt: 'SYS');
    await h.ask('What does John 3:16 teach?');
    await h.ask('What does John 3:16 teach?', style: AnswerStyle.brief);
    expect(engine.calls[0].first.content, isNot(contains(briefRule)));
    expect(engine.calls[1].first.content, contains(briefRule));
    expect(engine.limits, [h.tier.maxOutput, briefMaxOutput]);
  });

  test('a replacing answer takes the place of the last one in the history', () async {
    final engine = _Stateless();
    final h = Harness(db: _db(), engine: engine, systemPrompt: 'SYS');
    await h.ask('What does John 3:16 teach?', style: AnswerStyle.brief);
    await h.ask('What does John 3:16 teach?', replacePrevious: true);
    expect(h.history.map((m) => m.role), ['user', 'assistant']);
    expect(engine.calls[1].map((m) => m.role), ['system', 'user']);
  });

  group('an answer that is cut off', () {
    Harness harness(LlmEngine engine) => Harness(db: _db(), engine: engine, systemPrompt: 'SYS');

    test('a stopped answer keeps its finished sentences and no unclosed quotation', () async {
      final engine = _Pieces(['For God so loved the world. ', 'He said "For God so', ' loved']);
      final h = harness(engine);
      final result = await h.ask('What does John 3:16 teach?', onToken: (_) => h.stop());
      expect(engine.stops, 1);
      expect(result.text, 'For God so loved the world.');
      expect(h.history.last.content, 'For God so loved the world.');
    });

    test('an answer that hit the length cap is cut back to a finished sentence', () async {
      final h = harness(_Pieces(['Done. ', ...List.filled(248, 'x '), 'y']));
      final result = await h.ask('What does John 3:16 teach?', style: AnswerStyle.brief);
      expect(result.text, 'Done.');
    });

    test('an answer that ends of its own accord is left as it is', () async {
      final h = harness(_Pieces(['Done. ', 'And more']));
      final result = await h.ask('What does John 3:16 teach?');
      expect(result.text, 'Done. And more');
    });

    test('stopping before anything is written adds nothing to the history', () async {
      final h = harness(_Pieces(const []));
      await h.ask('What does John 3:16 teach?', onToken: (_) {});
      expect(h.history, isEmpty);
    });

    test('a failed replacing answer puts the earlier one back', () async {
      final engine = _Pieces(['Brief answer.']);
      final h = harness(engine);
      await h.ask('What does John 3:16 teach?', style: AnswerStyle.brief);
      engine.failWith = StateError('model gone');
      await expectLater(
        h.ask('What does John 3:16 teach?', replacePrevious: true),
        throwsStateError,
      );
      expect(h.history.map((m) => m.content), ['What does John 3:16 teach?', 'Brief answer.']);
    });

    test('a replacing answer that is stopped at once keeps the earlier one', () async {
      final engine = _Pieces(['Brief answer.']);
      final h = harness(engine);
      await h.ask('What does John 3:16 teach?', style: AnswerStyle.brief);
      engine.pieces = const [];
      await h.ask('What does John 3:16 teach?', replacePrevious: true);
      expect(h.history.map((m) => m.content), ['What does John 3:16 teach?', 'Brief answer.']);
    });
  });
}

class _Stateless implements LlmEngine {
  final calls = <List<ChatMessage>>[];
  final limits = <int>[];

  @override
  String get name => 'stateless';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    calls.add(messages);
    limits.add(maxTokens);
    yield 'An answer.';
  }
}

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

/// Writes [pieces] one at a time, and can be told to stop or to fail.
class _Pieces implements LlmEngine, StoppableEngine {
  List<String> pieces;
  Object? failWith;
  var stops = 0;
  var _stopped = false;
  _Pieces(this.pieces);

  @override
  String get name => 'pieces';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    _stopped = false;
    final failure = failWith;
    if (failure != null) throw failure;
    for (final piece in pieces) {
      if (_stopped) return;
      yield piece;
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    _stopped = true;
  }
}
