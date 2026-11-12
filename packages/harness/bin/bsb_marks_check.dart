// Measures the BSB publisher's marks against bsb.txt from the cached, pinned files.
// Usage: dart run bin/bsb_marks_check.dart [--cache .cache]
import 'dart:io';

import 'package:berea_harness/src/bsb_marks.dart';
import 'package:berea_harness/src/importers.dart';

void main(List<String> args) {
  final cache = args.length > 1 && args[0] == '--cache' ? args[1] : '.cache';
  final bsb = parseBsbText(File('$cache/bsb.txt').readAsStringSync());
  final r = parseBsbMarks(
    File('$cache/bsb_tables.tsv').readAsStringSync(),
    bsb,
  );
  var red = 0, sup = 0, notes = 0, noteVerses = 0, redVerses = 0;
  for (final v in r.verses) {
    final reds = v.spans.where((s) => s.kind == MarkKind.red).length;
    red += reds;
    if (reds > 0) redVerses++;
    sup += v.spans.where((s) => s.kind == MarkKind.supplied).length;
    notes += v.footnotes.length;
    if (v.footnotes.isNotEmpty) noteVerses++;
  }
  stdout.writeln('verses read: ${bsb.length}');
  stdout.writeln(
    'reconciled: ${r.verses.length}; unreconciled: ${r.unreconciled.map((e) => e.label).join(', ')}',
  );
  stdout.writeln(
    'red spans: $red in $redVerses verses; supplied spans: $sup; footnotes: $notes in $noteVerses verses',
  );
}
