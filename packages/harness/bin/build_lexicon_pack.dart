// Builds the optional full Greek lexicon pack (LSJ via STEPBible TFLSJ, CC BY 4.0).
// It is not bundled; the app downloads it only when the user asks.
// Usage: dart run bin/build_lexicon_pack.dart [--out ../../build/lexicon-lsj.sqlite]
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

const _base = 'https://raw.githubusercontent.com/STEPBible/STEPBible-Data/master/Lexicons';
const _files = [
  'TFLSJ%20%200-5624%20-%20Translators%20Formatted%20full%20LSJ%20Bible%20lexicon%20-%20STEPBible.org%20CC%20BY.txt',
  'TFLSJ%20extra%20-%20Translators%20Formatted%20full%20LSJ%20Bible%20lexicon%20-%20STEPBible.org%20CC%20BY.txt',
];

final _row = RegExp(r'^G\d{4}[a-z]?\t');
final _citationLinks = RegExp(r'<a [^>]*>.*?</a>', dotAll: true);
final _breaks = RegExp(r'<br\s*/?>', caseSensitive: false);
final _tags = RegExp(r'<[^>]+>');
final _emptyBrackets = RegExp(r'\[\s*\]');
final _blankRuns = RegExp(r'[ \t]+');
final _blankLines = RegExp(r'\n\s*\n+');

String _plain(String html) => html
    .replaceAll(_citationLinks, '')
    .replaceAll(_breaks, '\n')
    .replaceAll(_tags, '')
    .replaceAll(_emptyBrackets, '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(_blankRuns, ' ')
    .replaceAll(_blankLines, '\n')
    .trim();

Future<void> main(List<String> args) async {
  final i = args.indexOf('--out');
  final out = i >= 0 && i + 1 < args.length ? args[i + 1] : '../../build/lexicon-lsj.sqlite';
  Directory(File(out).parent.path).createSync(recursive: true);
  if (File(out).existsSync()) File(out).deleteSync();
  final db = sqlite3.open(out);
  db.execute('''
    CREATE TABLE lexicon_full(key TEXT PRIMARY KEY, base TEXT, definition TEXT);
    CREATE INDEX lexicon_full_base ON lexicon_full(base);
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  ''');
  final stmt = db.prepare('INSERT OR IGNORE INTO lexicon_full VALUES (?, ?, ?)');
  db.execute('BEGIN');
  var n = 0;
  for (final f in _files) {
    final cache = File('.cache/${Uri.decodeComponent(f)}');
    if (!cache.existsSync()) {
      stdout.writeln('downloading $f');
      final r = await http.get(Uri.parse('$_base/$f'));
      if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} for $f');
      cache.writeAsBytesSync(r.bodyBytes);
    }
    for (final line in cache.readAsLinesSync()) {
      if (!_row.hasMatch(line)) continue;
      final c = line.split('\t');
      if (c.length < 8) continue;
      final base = c[0].trim().toUpperCase().replaceAll(RegExp(r'[A-Z]$'), '');
      stmt.execute([c[1].trim().split(' ').first, base, _plain(c[7])]);
      n++;
    }
  }
  db.execute('COMMIT');
  stmt.dispose();
  db.execute(
    "INSERT INTO meta VALUES('source', 'STEPBible TFLSJ, CC BY 4.0, https://www.STEPBible.org')",
  );
  db.execute('VACUUM');
  db.dispose();
  stdout.writeln(
    'lexicon_full: $n entries, ${(File(out).lengthSync() / 1048576).toStringAsFixed(1)} MB at $out',
  );
}
