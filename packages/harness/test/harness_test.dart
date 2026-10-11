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
}

class _Stateless implements LlmEngine {
  final calls = <List<ChatMessage>>[];

  @override
  String get name => 'stateless';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    calls.add(messages);
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
