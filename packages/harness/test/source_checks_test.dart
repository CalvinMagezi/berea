import 'package:berea_harness/berea_harness.dart';
import 'package:berea_harness/src/source_checks.dart';
import 'package:test/test.dart';

VerseRow _row(String book, int chapter, int verse, String text) =>
    (book: bookFor(book)!, chapter: chapter, verse: verse, text: text);

void main() {
  test('pin check accepts the pinned hash and names the source on a mismatch', () {
    const abcSha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    checkPin('abc'.codeUnits, abcSha256, source: 'test.txt');
    expect(
      () => checkPin('abd'.codeUnits, abcSha256, source: 'test.txt'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('test.txt'), contains(abcSha256)),
        ),
      ),
    );
  });

  test('verse count rejects short and duplicated texts', () {
    final rows = [_row('John', 1, 1, 'a'), _row('John', 1, 2, 'b')];
    checkVerseCount(rows, expected: 2);
    expect(() => checkVerseCount(rows.take(1).toList(), expected: 2), throwsStateError);
    expect(
      () => checkVerseCount([rows.first, rows.first], expected: 2),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('1 distinct'))),
    );
  });

  test('diff report counts per book, lists added and removed verses, and samples', () {
    final old = [
      _row('Genesis', 1, 1, 'same'),
      _row('Genesis', 1, 2, 'old two'),
      _row('Romans', 8, 15, 'Spirit of sonship'),
      _row('Jude', 1, 26, 'only old'),
    ];
    final fresh = [
      _row('Genesis', 1, 1, 'same'),
      _row('Genesis', 1, 2, 'new two'),
      _row('Romans', 8, 15, 'Spirit of adoption to sonship'),
      _row('Psalm', 3, 1, 'only new'),
    ];
    final report = verseDiffReport(old, fresh, title: 'T', watched: ['Exodus 1:1'], samples: 1);
    expect(report, startsWith('# T\n'));
    expect(report, contains('2 of 4 verses changed.'));
    expect(report, contains('only in the new text: Psalms 3:1. Only in the old: Jude 1:26.'));
    expect(report, contains('| Genesis | 1 |\n| Romans | 1 |'));
    expect(report, contains('**Genesis 1:2**\n\n- old: old two\n- new: new two'));
    expect(report, isNot(contains('**Romans 8:15**')));
    expect(report, contains('**Exodus 1:1**\n\n- old: (absent)\n- new: (absent)'));
  });
}
