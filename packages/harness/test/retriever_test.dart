import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _colossians = 51;
const _romans = 45;
const _job = 18;
const _james = 59;

void main() {
  final bible = File('../../assets/berea.sqlite');
  if (!bible.existsSync() || bible.lengthSync() == 0) {
    test('these tests open the built Bible', () {}, skip: 'needs assets/berea.sqlite');
    return;
  }
  late Retriever retriever;
  setUpAll(() {
    retriever = Retriever(BibleDb(sqlite3.open(bible.path, mode: OpenMode.readOnly)));
  });

  test('John 3:16 lexicon keeps content words and drops function words', () {
    final ctx = retriever.retrieve('What does John 3:16 teach about the love of God?', Tier.low);
    expect(ctx.lexicon.keys, contains('G0025'));
    expect(ctx.lexicon.keys, isNot(contains('G3588')));
    expect(ctx.lexicon.keys, isNot(contains('G1063')));
  });

  test('a passage question on the mid tier searches its words beside the reference', () {
    final ctx = retriever.retrieve(
      'Exegete Luke 12:16-21, the parable of the rich fool.',
      Tier.mid,
    );
    expect(ctx.searchHits, isNotEmpty);
    expect(ctx.allVerses.where((v) => v.book.id == _colossians), isEmpty, reason: 'not "Luke"');
  });

  test('a passage question gets no related verses on the low tier', () {
    final ctx = retriever.retrieve(
      'Exegete Luke 12:16-21, the parable of the rich fool.',
      Tier.low,
    );
    expect(ctx.searchHits, isEmpty);
    expect(ctx.allVerses.where((v) => v.book.id == _colossians), isEmpty);
  });

  test('a bare book name scopes the search to that book', () {
    final ctx = retriever.retrieve('What does Romans teach about grace?', Tier.low);
    expect(ctx.searchHits, isNotEmpty);
    expect(ctx.searchHits.every((v) => v.book.id == _romans), isTrue);
  });

  test('the cue that scopes a search is not searched for', () {
    // Romans uses "letter" itself (2:29, 7:6), so a kept cue would pull those verses in.
    final ctx = retriever.retrieve(
      'What does the letter to the Romans tell about faith?',
      Tier.low,
    );
    final plain = retriever.db.search('faith', k: Tier.low.searchK, book: bookById(_romans));
    expect(ctx.searchHits.map((v) => v.label), plain.map((v) => v.label));
  });

  test('an everyday word in lower case is not taken for a book', () {
    final ctx = retriever.retrieve('How should I work hard at my job?', Tier.low);
    expect(ctx.searchHits, isNotEmpty);
    expect(ctx.searchHits.every((v) => v.book.id == _job), isFalse);
  });

  test('a book name that names a person does not scope the search', () {
    final daniel = retriever.retrieve('Who was Daniel?', Tier.low);
    expect(daniel.searchHits, isNotEmpty);
    final apostles = retriever.retrieve('What did James and John ask Jesus for?', Tier.low);
    expect(apostles.searchHits.every((v) => v.book.id == _james), isFalse);
  });

  test('a reference with no passage still searches', () {
    final ctx = retriever.retrieve('What does Romans 99:1 say about grace?', Tier.low);
    expect(ctx.passages, isEmpty);
    expect(ctx.searchHits, isNotEmpty);
  });

  test('a short passage brings the verses around it, inside its section', () {
    // BSB starts a section at Philippians 4:10, so verses 8 and 9 belong to another paragraph.
    final ctx = retriever.retrieve('What does Philippians 4:10 mean?', Tier.low);
    expect(ctx.surrounding.map((v) => v.label), ['Philippians 4:11', 'Philippians 4:12']);
  });

  test('a full answer reads the surrounding verses and a brief one does not', () {
    const q = 'What does Philippians 4:10 mean?';
    final ctx = retriever.retrieve(q, Tier.low);
    final builder = PromptBuilder('SYS');
    final full = builder.build(ctx, const [], q, Tier.low);
    final brief = builder.build(ctx, const [], q, Tier.low, style: AnswerStyle.brief);
    expect(full.shown.surrounding, isNotEmpty);
    expect(full.messages.last.content, contains('SURROUNDING VERSES'));
    expect(brief.shown.surrounding, isEmpty);
    expect(brief.messages.last.content, isNot(contains('SURROUNDING VERSES')));
  });

  test('a brief answer to a question naming two passages is told to cite both', () {
    const two = 'Explain Luke 15:11-32 in light of Luke 15:1-2.';
    final builder = PromptBuilder('SYS');
    String question(String q, AnswerStyle style) => builder
        .build(retriever.retrieve(q, Tier.low), const [], q, Tier.low, style: style)
        .messages
        .last
        .content;
    expect(
      question(two, AnswerStyle.brief),
      endsWith(
        'Your answer must cite both, written as (Luke 15:11-32, BSB) and (Luke 15:1-2, BSB).',
      ),
    );
    expect(question(two, AnswerStyle.full), isNot(contains('must cite')));
    expect(question('What does John 3:16 mean?', AnswerStyle.brief), isNot(contains('must cite')));
  });

  test('a long passage carries its own context', () {
    final ctx = retriever.retrieve('Explain Philippians 4:4-9.', Tier.low);
    expect(ctx.surrounding, isEmpty);
  });

  test('a search finds the other English form of a word', () {
    // Porter stems "angry" to "angri" and leaves "anger", so the forms never met before.
    expect(retriever.db.wordForms('angry'), ['anger']);
    expect(retriever.db.wordForms('fear'), isEmpty, reason: 'fearless is not a form of fear');
    final ctx = retriever.retrieve('Is it wrong to be angry?', Tier.mid);
    expect(ctx.searchHits.map((v) => v.label), contains('Ephesians 4:26'));
  });

  test('a topical question still searches the whole Bible', () {
    final ctx = retriever.retrieve('What does the Bible say about forgiveness?', Tier.low);
    expect(ctx.searchHits, isNotEmpty);
  });
}
