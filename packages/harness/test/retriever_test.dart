import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _colossians = 51;
const _romans = 45;
const _job = 18;

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

  test('a passage question gets no related verses', () {
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

  test('an everyday word in lower case is not taken for a book', () {
    final ctx = retriever.retrieve('How should I work hard at my job?', Tier.low);
    expect(ctx.searchHits, isNotEmpty);
    expect(ctx.searchHits.every((v) => v.book.id == _job), isFalse);
  });

  test('a topical question still searches the whole Bible', () {
    final ctx = retriever.retrieve('What does the Bible say about forgiveness?', Tier.low);
    expect(ctx.searchHits, isNotEmpty);
  });
}
