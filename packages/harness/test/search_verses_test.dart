import 'package:berea_harness/berea_harness.dart';
import 'package:berea_harness/src/search_text.dart';
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
      expect(containsPhrase(searchTokens(v.text), ['jesus', 'wept']), isTrue, reason: v.label);
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
}
