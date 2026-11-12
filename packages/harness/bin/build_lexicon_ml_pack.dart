// Builds the optional Middle Liddell definitions pack for Greek entries STEPBible cites to it.
// Middle Liddell comes from the Perseus Digital Library under a share-alike licence, so it is kept
// in its own file with its credit and licence and never merged into the app's database.
// It is not bundled. The app downloads it from a release only when the user asks.
// Usage: dart run bin/build_lexicon_ml_pack.dart [--out ../../build/lexicon-ml.sqlite]
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const _greekLexiconFile =
    'TBESG - Translators Brief lexicon of Extended Strongs for Greek - STEPBible.org CC BY.txt';

final _tag = RegExp(r'<[^>]+>');
final _ws = RegExp(r'\s+');
final _source = RegExp(r'\(ML\)\s*$');

Future<void> main(List<String> args) async {
  final i = args.indexOf('--out');
  final out = i >= 0 && i + 1 < args.length ? args[i + 1] : '../../build/lexicon-ml.sqlite';
  Directory(File(out).parent.path).createSync(recursive: true);
  if (File(out).existsSync()) File(out).deleteSync();
  final db = sqlite3.open(out);
  db.execute('''
    CREATE TABLE lexicon_ml(key TEXT PRIMARY KEY, base TEXT, definition TEXT);
    CREATE INDEX lexicon_ml_base ON lexicon_ml(base);
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  ''');
  final stmt = db.prepare('INSERT OR IGNORE INTO lexicon_ml VALUES (?, ?, ?)');
  final text = File('.cache/$_greekLexiconFile').readAsStringSync();
  var n = 0;
  db.execute('BEGIN');
  for (final line in text.split('\n')) {
    if (!RegExp(r'^G\d{4,5}[a-z]?\t').hasMatch(line)) continue;
    final c = line.split('\t');
    if (c.length < 8) continue;
    var def = c[7].replaceAll(_tag, ' ').replaceAll(_ws, ' ').trim();
    if (!_source.hasMatch(def)) continue;
    def = def.replaceFirst(_source, '').replaceAll(RegExp(r'†\s*$'), '').trim();
    final summary = def.indexOf('§');
    if (summary >= 0) def = def.substring(0, summary).trim();
    final number = c[0].trim().toUpperCase();
    stmt.execute([c[1].trim().split(' ').first, number.replaceAll(RegExp(r'[A-Z]$'), ''), def]);
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  final meta = {
    'source': 'Middle Liddell (An Intermediate Greek-English Lexicon), Perseus Digital Library, '
        'through the STEPBible Brief lexicon (Tyndale House, Cambridge)',
    'licence': 'Creative Commons Attribution-ShareAlike (Perseus Digital Library, Tufts University; '
        'version 4.0 as stated by the Perseus lexica repository)',
    'changes': 'Tags removed and text flattened to plain lines by Berea; wording otherwise as '
        'STEPBible prints it',
  };
  for (final e in meta.entries) {
    db.execute('INSERT INTO meta VALUES (?, ?)', [e.key, e.value]);
  }
  db.execute('VACUUM');
  db.dispose();
  stdout.writeln('lexicon_ml: $n entries, ${(File(out).lengthSync() / 1024).round()} KB at $out');
}
