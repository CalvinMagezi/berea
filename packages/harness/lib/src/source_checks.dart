import 'package:crypto/crypto.dart';

import 'importers.dart';

/// Verses in the BSB's 66 books, counting the 16 it leaves empty (Matthew 17:21).
const bsbVerseCount = 31102;
const defaultDiffSamples = 20;

/// Throws unless [bytes] hash to [pinned]; [source] names the file in the message.
void checkPin(List<int> bytes, String pinned, {required String source}) {
  final actual = sha256.convert(bytes).toString();
  if (actual == pinned) return;
  throw StateError(
    'SHA-256 mismatch for $source\n'
    '  pinned: $pinned\n'
    '  actual: $actual\n'
    'If the upstream file changed, review it, then update its pin in the build script.',
  );
}

String verseLabel(VerseRow r) => '${r.book.name} ${r.chapter}:${r.verse}';

/// Throws unless [rows] of the text named [source] hold exactly [expected] verses, each once.
void checkVerseCount(List<VerseRow> rows, {required String source, int expected = bsbVerseCount}) {
  final distinct = {for (final r in rows) verseLabel(r)}.length;
  if (rows.length == expected && distinct == expected) return;
  throw StateError(
    '$source has ${rows.length} verse lines and $distinct distinct verses, expected $expected of each',
  );
}

String _listOrNone(List<String> labels) => labels.isEmpty ? 'none' : labels.join(', ');

/// Markdown report of how [fresh] differs from [old]: counts per book, then samples.
String verseDiffReport(
  List<VerseRow> old,
  List<VerseRow> fresh, {
  required String title,
  List<String> watched = const [],
  int samples = defaultDiffSamples,
}) {
  final before = {for (final r in old) verseLabel(r): r.text};
  final after = {for (final r in fresh) verseLabel(r): r.text};
  final changed = [
    for (final r in fresh)
      if (before.containsKey(verseLabel(r)) && before[verseLabel(r)] != r.text) r,
  ];
  final perBook = <String, int>{};
  for (final r in changed) {
    perBook.update(r.book.name, (n) => n + 1, ifAbsent: () => 1);
  }
  final added = after.keys.where((k) => !before.containsKey(k)).toList();
  final removed = before.keys.where((k) => !after.containsKey(k)).toList();
  final out = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln(
      '${changed.length} of ${fresh.length} verses changed. '
      'Verses only in the new text: ${_listOrNone(added)}. Only in the old: ${_listOrNone(removed)}.',
    )
    ..writeln()
    ..writeln('| Book | Changed |')
    ..writeln('|------|---------|');
  perBook.forEach((book, n) => out.writeln('| $book | $n |'));
  out
    ..writeln()
    ..writeln('## Samples');
  for (final label in {...watched, ...changed.take(samples).map(verseLabel)}) {
    out
      ..writeln()
      ..writeln('**$label**')
      ..writeln()
      ..writeln('- old: ${before[label] ?? '(absent)'}')
      ..writeln('- new: ${after[label] ?? '(absent)'}');
  }
  return out.toString();
}
