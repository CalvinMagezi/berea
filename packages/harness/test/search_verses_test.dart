import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/bible.dart';

void main() {
  if (needsBibleText case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  late BibleDb db;
  setUpAll(() => db = BibleDb(sqlite3.open(bibleDbFile().path, mode: OpenMode.readOnly)));

  SearchGroup group(List<SearchGroup> gs, String label) => gs.firstWhere((g) => g.label == label);

  test('a name the old stoplist dropped finds its verses', () {
    for (final name in ['Jesus', 'God', 'Lord', 'Christ', 'help']) {
      final groups = db.searchVerses(name);
      expect(groups, isNotEmpty, reason: name);
      expect(group(groups, 'Exact words').total, greaterThan(0), reason: name);
    }
  });

  test('an exact phrase lists only verses that contain those words in that order', () {
    final exact = group(db.searchVerses('Jesus wept'), 'Exact words');
    expect(exact.verses.map((v) => v.label), contains('John 11:35'));
    for (final v in exact.verses) {
      expect(phrasePattern(['jesus', 'wept']).hasMatch(v.text), isTrue, reason: v.label);
    }
  });

  test('a query of only function words runs as a phrase', () {
    final groups = db.searchVerses('in the beginning');
    expect(group(groups, 'Exact words').verses.first.label, 'Genesis 1:1');
    expect(groups.map((g) => g.label), isNot(contains('All your words')));
  });

  test('every group is in Bible order and no verse is in two groups', () {
    final groups = db.searchVerses('faith hope love', perGroup: 5000);
    final seen = <String>{};
    for (final g in groups) {
      final keys = [for (final v in g.verses) (v.book.id * 1000 + v.chapter) * 1000 + v.verse];
      expect(keys, orderedEquals([...keys]..sort()), reason: g.label);
      for (final v in g.verses) {
        expect(seen.add(v.label), isTrue, reason: '${v.label} repeated');
      }
    }
    expect(groups.map((g) => g.label), contains('All your words'));
    expect(group(groups, 'All your words').verses.map((v) => v.label), contains('1 Corinthians 13:13'));
  });

  test('a single word also lists its other forms, apart from the exact word', () {
    final groups = db.searchVerses('love', perGroup: 5000);
    final exact = group(groups, 'Exact words').verses.map((v) => v.label).toSet();
    final other = group(groups, 'Other forms of the word').verses;
    expect(other, isNotEmpty);
    expect(other.where((v) => exact.contains(v.label)), isEmpty);
  });

  test('nothing to search for returns nothing, and a word in no verse returns no group', () {
    expect(db.searchVerses('   '), isEmpty);
    expect(db.searchVerses('zzzqqq'), isEmpty);
  });

  test('one content word among function words is not called a form of the word', () {
    final labels = db.searchVerses('the Lord').map((g) => g.label);
    expect(labels, contains('Exact words'));
    expect(labels, isNot(contains('Other forms of the word')));
    expect(labels, contains('Has "lord", without the other words'));
  });

  test('a lone function word lists nothing, and a phrase pattern matches whole words only', () {
    expect(searchIsTooCommon('The'), isTrue);
    expect(searchIsTooCommon('the lord'), isFalse);
    expect(db.searchVerses('the'), isEmpty);
    final pattern = phrasePattern(['god', 's', 'love']);
    expect(pattern.hasMatch("For GOD'S love is"), isTrue);
    expect(phrasePattern(['wept']).hasMatch('He swept the floor'), isFalse);
    expect(phrasePattern(['jesus', 'wept']).hasMatch('Jesus, wept.'), isTrue);
  });

  test('a database held in memory has no file path, and a built one does', () {
    expect(BibleDb(sqlite3.openInMemory()).filePath, isNull);
    expect(db.filePath, endsWith('.sqlite'));
  });

  test('a translation not recorded as ordered is searched through the verse table, same answers', () {
    final raw = sqlite3.openInMemory();
    createBibleSchema(raw);
    final rows = [
      (book: bookById(43), chapter: 11, verse: 35, text: 'Jesus wept.'),
      (book: bookById(1), chapter: 1, verse: 1, text: 'In the beginning God created.'),
    ];
    loadVerseRows(raw, 'TEST', rows);
    rebuildVersesFts(raw);
    final plain = BibleDb(raw);
    expect(plain.searchVerses('jesus wept', translation: 'TEST').first.verses.single.label, 'John 11:35');
    final all = plain.searchVerses('beginning created', translation: 'TEST');
    expect(all.single.label, 'All your words');
    expect(all.single.verses.single.label, 'Genesis 1:1');
    plain.recordBibleOrder();
    expect(raw.select("SELECT value FROM meta WHERE key = 'bible_order'").single['value'], '');
  });

  test('a word no verse has comes back with the words one letter away and their verse counts', () {
    final result = db.searchResult('jeus wept');
    expect(result.groups, isEmpty);
    expect(result.spelling!.word, 'jeus');
    expect(result.spelling!.near.map((w) => w.$1), contains('jesus'));
    expect(result.spelling!.near.firstWhere((w) => w.$1 == 'jesus').$2, greaterThan(500));
    expect(db.searchResult('Jesus').spelling, isNull);
    expect(db.searchResult('zzzqqq').spelling, isNull);
  });

  test('a word STEPBible tags, and an archaic form only the KJV has', () {
    final love = db.searchVerses('love').map((g) => g.label);
    expect(love.where((l) => l.contains('(G0025)') && l.contains('glosses "love"')), hasLength(1));
    final thee = db.searchVerses('thee');
    expect(thee.map((g) => g.label), ['Exact words in KJV']);
  }, skip: needsFullDatabase);

  test('a printed section heading is found, listed last under the publisher\'s name', () {
    final groups = db.searchVerses('the creation');
    final last = groups.last;
    expect(last.label, 'Section headings, printed by the BSB publisher');
    expect(last.verses.map((v) => v.label), contains('Genesis 1:1'));
    expect(last.verses.firstWhere((v) => v.label == 'Genesis 1:1').text, 'The Creation');
    expect(db.searchVerses('zzzqqq'), isEmpty);
  }, skip: needsFullDatabase);

  test('a spelling line is found even when an earlier unknown word has no near words', () {
    final result = db.searchResult('xqzv jeus');
    expect(result.spelling?.word, 'jeus');
  });
}
