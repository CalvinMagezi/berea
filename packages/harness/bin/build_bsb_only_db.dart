// Builds a BSB-only Bible database from the committed JSON in site/data/bible.
// Usage: dart run bin/build_bsb_only_db.dart [--out ../../assets/berea.sqlite] [--data ../../site/data/bible]
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:berea_harness/src/source_checks.dart';
import 'package:sqlite3/sqlite3.dart';

const defaultOut = '../../assets/berea.sqlite';
const bytesPerMb = 1024 * 1024;

String _opt(List<String> args, String name, String fallback) {
  final i = args.indexOf('--$name');
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

String _findBibleDir(String explicit) {
  if (explicit.isNotEmpty) return explicit;
  if (Directory('site/data/bible').existsSync()) return 'site/data/bible';
  if (Directory('../../site/data/bible').existsSync()) return '../../site/data/bible';
  throw StateError('Cannot find site/data/bible');
}

/// Reads the 66 book JSON files in [dir] into verse rows.
List<VerseRow> loadBsbJsonVerses(Directory dir) {
  final rows = <VerseRow>[];
  for (final b in books) {
    final file = File('${dir.path}/${b.id}.json');
    if (!file.existsSync()) {
      throw StateError('Missing JSON for ${b.name}: ${file.path}');
    }
    final chapters = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    for (var c = 1; c <= chapters.length; c++) {
      final verses = chapters[c - 1] as List<dynamic>;
      for (var v = 1; v <= verses.length; v++) {
        final text = verses[v - 1] as String?;
        if (text != null) {
          rows.add((book: b, chapter: c, verse: v, text: text));
        }
      }
    }
  }
  return rows;
}

void main(List<String> args) {
  final out = _opt(args, 'out', defaultOut);
  final dataDir = Directory(_findBibleDir(_opt(args, 'data', '')));

  final bsb = loadBsbJsonVerses(dataDir);
  checkVerseCount(bsb, source: 'site/data/bible');

  Directory(File(out).parent.path).createSync(recursive: true);
  // Built aside and renamed at the end, so any failure leaves the last good database in place.
  final tmp = File('$out.tmp');
  if (tmp.existsSync()) tmp.deleteSync();
  try {
    final db = sqlite3.open(tmp.path);
    final String built;
    try {
      createBibleSchema(db);
      loadVerseRows(db, 'BSB', bsb);
      rebuildVersesFts(db);
      BibleDb(db).recordBibleOrder();
      built = DateTime.now().toUtc().toIso8601String();
      final meta = db.prepare('INSERT INTO meta VALUES (?, ?)');
      meta
        ..execute(['built', built])
        ..execute(['translations', 'BSB'])
        ..dispose();
      db.execute('VACUUM');
    } finally {
      db.dispose();
    }
    tmp.renameSync(out);
    // Written last so the app can detect recopy needs without opening the full file.
    File('$out.version').writeAsStringSync(built);
    stdout.writeln('wrote $out (${(File(out).lengthSync() / bytesPerMb).toStringAsFixed(1)} MB)');
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}
