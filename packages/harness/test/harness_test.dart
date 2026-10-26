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
