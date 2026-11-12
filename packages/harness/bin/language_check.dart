// Measures a USFM Bible zip against the BSB's verse numbering, so a language is offered only once
// its completeness is known. Usage: dart run bin/language_check.dart <zip> [--db ../../assets/berea.sqlite]
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final zip = args.first;
  final dbPath = args.contains('--db') ? args[args.indexOf('--db') + 1] : '../../assets/berea.sqlite';
  final rows = parseBibleFile(zip.split('/').last, File(zip).readAsBytesSync());
  final have = {for (final r in rows) '${r.book.id}:${r.chapter}:${r.verse}': r.text};
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  final bsb = {
    for (final r in db.select("SELECT book, chapter, verse FROM verses WHERE translation = 'BSB'"))
      '${r['book']}:${r['chapter']}:${r['verse']}',
  };
  final missing = bsb.where((k) => !have.containsKey(k)).toList();
  final extra = have.keys.where((k) => !bsb.contains(k)).toList();
  final empty = have.entries.where((e) => e.value.trim().isEmpty).length;
  final books = rows.map((r) => r.book.id).toSet();
  stdout.writeln(zip);
  stdout.writeln('  verses read: ${rows.length}; books: ${books.length}; empty: $empty');
  stdout.writeln('  BSB verses with no text here: ${missing.length}; verses here the BSB has no number for: ${extra.length}');
  final missingBooks = [for (final b in List.generate(66, (i) => i + 1)) if (!books.contains(b)) bookById(b).name];
  stdout.writeln('  books missing: ${missingBooks.isEmpty ? 'none' : missingBooks.join(', ')}');
  String label(String k) {
    final p = k.split(':');
    return '${bookById(int.parse(p[0])).name} ${p[1]}:${p[2]}';
  }

  stdout.writeln('  first missing: ${missing.take(8).map(label).join('; ')}');
  stdout.writeln('  first extra: ${extra.take(8).map(label).join('; ')}');
  final byBook = <int, int>{};
  for (final k in missing) {
    byBook.update(int.parse(k.split(':').first), (n) => n + 1, ifAbsent: () => 1);
  }
  final worst = byBook.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('  most missing by book: ${worst.take(6).map((e) => '${bookById(e.key).name} ${e.value}').join(', ')}');
}
