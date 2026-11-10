
import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/bible.dart';

void main() {
  if (needsFullDatabase case final why?) {
    test('this test opens the built Bible', () {}, skip: why);
    return;
  }
  test('every lexicon entry cleans without throwing and without script or references', () {
    final db = sqlite3.open(bibleDbFile().path, mode: OpenMode.readOnly);
    addTearDown(db.dispose);
    var empty = 0;
    final rows = db.select('SELECT definition FROM lexicon');
    for (final r in rows) {
      final senses = plainSenses(r['definition'] as String? ?? '');
      if (senses.isEmpty) empty++;
      for (final s in senses) {
        expect(s.length, lessThanOrEqualTo(141), reason: s);
        expect(RegExp(r'[Ͱ-Ͽ֐-׿]').hasMatch(s), isFalse, reason: s);
      }
    }
    // Measured 276 of 21,232 on 2026-10-30; those fall back to the gloss alone.
    expect(empty, lessThan(rows.length ~/ 20));
  });
}
