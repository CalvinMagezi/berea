// Builds assets/berea.sqlite from public domain and CC BY datasets.
// Usage: dart run bin/build_db.dart [--out ../../assets/berea.sqlite] [--cache .cache]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea_harness/src/bible_db.dart';
import 'package:berea_harness/src/books.dart';
import 'package:berea_harness/src/bsb_marks.dart';
import 'package:berea_harness/src/csv.dart';
import 'package:berea_harness/src/importers.dart';
import 'package:berea_harness/src/ref_parser.dart';
import 'package:berea_harness/src/source_checks.dart';
import 'package:berea_harness/src/word_study.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

// Third-party repositories are fetched at a commit, never a branch, and every file is checked
// against a SHA-256, so a moved upstream cannot change the shipped database unseen.
const _scrollmapperCommit = '59b18c5af5845728c275d5b7178ad0d024172b1f';
const _scrollmapper =
    'https://raw.githubusercontent.com/scrollmapper/bible_databases/$_scrollmapperCommit/formats/csv';
const _kjvSha256 = 'a1051b4395bee78d01e239984425f3919563db5caee6fc162d4ddc7faff7eaa8';
const _bsb = 'https://bereanbible.com/bsb.txt';
// Bump only after reading the diff report for the new text; the narrated audio follows it.
const _bsbSha256 = '2ac3af1de52d4e68261cba91d85c320b7eadc6560e830d99e591767b8ff5ca96';
// The BSB translation tables: each English phrase of the BSB with its Strong's number, in English
// order. Public domain with the BSB text (bereanbible.com, "Free Downloads"). Bump with the text.
/// Measured on the pinned files: Exodus 38:28 and Judges 16:14 differ between bsb.txt and the tables.
const _maxUnreconciledMarks = 2;
const _bsbTables = 'https://bereanbible.com/bsb_tables.tsv';
const _bsbTablesSha256 = 'aa2a9a0f004d015738cd1839c7c56c3be2549e0d4f4537090c2017268c223c60';
// The scrollmapper revision Berea shipped before the official text, kept for the diff report.
const _oldBsbCommit = 'e1b254cef86d0e65b1a5d1a94b8b112d0f296a2c';
const _oldBsb =
    'https://raw.githubusercontent.com/scrollmapper/bible_databases/$_oldBsbCommit/formats/csv/BSB.csv';
const _oldBsbSha256 = 'bdedd6c2de31b1c729a5952a2cdc383b1f1396d1e9941d0b2cda2b997e22a8fb';
// Differences reported upstream before this import; always listed so a reviewer can check them.
const _watchedVerses = [
  'Genesis 1:21',
  'Genesis 2:11',
  'Genesis 2:13',
  'Psalms 119:70',
  'Isaiah 53:4',
  'Romans 8:15',
  'Revelation 22:8',
];
const _stepCommit = '5de0a47f35f0fc13dfe1430d104e5db8a4285f9c';
const _step = 'https://raw.githubusercontent.com/STEPBible/STEPBible-Data/$_stepCommit';
const _stepText = '$_step/Translators%20Amalgamated%20OT%2BNT';
const _stepLex = '$_step/Lexicons';
const _xrefs = 'https://a.openbible.info/data/cross-references.zip';
const _xrefsSha256 = '19aafdf923275142d0849fb02c7d9965a8d1a9dafc691e9abbe146fa31895c73';
const _web = 'https://ebible.org/Scriptures/engwebp_usfm.zip';
const _webSha256 = '674fb7eeffa9d64b90c4565a3678ffed61a1ddba47dff9b6a618528e2aaa8c67';
// The BSB in USFM, public domain like bsb.txt, read only for its section headings and parallel
// passage lines; the verse text still comes from bsb.txt.
const _bsbUsfm = 'https://ebible.org/Scriptures/engbsb_usfm.zip';
const _bsbUsfmSha256 = '75ca91d5a5c69ca4cbdeabdb03ea1a458db20cf3966abe15d86df086acf7fbc4';

const scrollmapperTranslations = ['KJV'];
const stepTextFiles = <String, String>{
  'TAHOT%20Gen-Deu%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt':
      '7763ef367bb0e6e1c1a95fb9b652e1d611b2481827611433e82abbf229216d70',
  'TAHOT%20Jos-Est%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt':
      'b79add01a8c95673e31ec3ab8ad86183d2312cd96421ddf21f3d1f74377526a7',
  'TAHOT%20Job-Sng%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt':
      'e0416880bb78f46715bb17ce526b623c3051da0ef83f7bf83beaad350e6272e8',
  'TAHOT%20Isa-Mal%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt':
      'd5a609f5a4b9f7757a2615e55877b07f9f6931a8afccef012c0b4bf662caf540',
  'TAGNT%20Mat-Jhn%20-%20Translators%20Amalgamated%20Greek%20NT%20-%20STEPBible.org%20CC-BY.txt':
      'd4c0c820fdf9f2b450c9f96ce6103d6875028affd2e44094d753f1329ca1fd85',
  'TAGNT%20Act-Rev%20-%20Translators%20Amalgamated%20Greek%20NT%20-%20STEPBible.org%20CC-BY.txt':
      '122040eeeaeba50d6abbf67b39cacaff687211bda69b080e5d53927c830d9968',
};
const stepLexFiles = <String, String>{
  'TBESH%20-%20Translators%20Brief%20lexicon%20of%20Extended%20Strongs%20for%20Hebrew%20-%20STEPBible.org%20CC%20BY.txt':
      '848eef2ac16753a43694897dbb9e8f266725e7cc9da4809f367ee5b990f05dbb',
  'TBESG%20-%20Translators%20Brief%20lexicon%20of%20Extended%20Strongs%20for%20Greek%20-%20STEPBible.org%20CC%20BY.txt':
      '734a5b64a1152f67604bf09d32f15c0ba537151961752fcf168087b41b4d93ea',
};

Future<void> main(List<String> args) async {
  var out = '../../assets/berea.sqlite';
  var cache = '.cache';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--out') out = args[i + 1];
    if (args[i] == '--cache') cache = args[i + 1];
  }
  Directory(cache).createSync(recursive: true);
  final bsb = parseBsbText(await _fetch(_bsb, '$cache/bsb.txt', pin: _bsbSha256));
  checkVerseCount(bsb, source: 'BSB');
  await _writeDiffReport(bsb, cache);
  Directory(File(out).parent.path).createSync(recursive: true);

  // Built aside and renamed at the end, so any failure leaves the last good database in place.
  final tmp = File('$out.tmp');
  if (tmp.existsSync()) tmp.deleteSync();
  try {
    final db = sqlite3.open(tmp.path);
    final String built;
    try {
      _createSchema(db);
      await _loadData(db, bsb, cache);
      BibleDb(db).recordBibleOrder();
      BibleDb(db).buildVocabulary();
      built = _writeMeta(db);
    } finally {
      db.dispose();
    }
    _publish(tmp, out, built);
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

void _createSchema(Database db) => createBibleSchema(db);

Future<void> _loadData(Database db, List<VerseRow> bsb, String cache) async {
  _loadRows(db, 'BSB', bsb);
  for (final t in scrollmapperTranslations) {
    _loadTranslation(db, t, await _fetch('$_scrollmapper/$t.csv', '$cache/$t.csv', pin: _kjvSha256));
  }
  final web = await _fetchBytes(_web, '$cache/engwebp_usfm.zip', pin: _webSha256);
  _loadRows(db, 'WEB', parseBibleFile('engwebp_usfm.zip', web));
  db.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')");
  final bsbUsfm = await _fetchBytes(_bsbUsfm, '$cache/engbsb_usfm.zip', pin: _bsbUsfmSha256);
  _loadHeadings(db, 'BSB', parseUsfmZipHeadings(bsbUsfm));
  _loadHeadings(db, 'WEB', parseUsfmZipHeadings(web));

  final tablesText = await _fetch(_bsbTables, '$cache/bsb_tables.tsv', pin: _bsbTablesSha256);
  final tables = parseBsbTables(tablesText);
  for (final MapEntry(key: f, value: sha) in stepTextFiles.entries) {
    final text = await _fetch('$_stepText/$f', '$cache/${Uri.decodeComponent(f)}', pin: sha);
    f.startsWith('TAHOT') ? _loadHebrew(db, text) : _loadGreek(db, text, tables);
  }
  for (final MapEntry(key: f, value: sha) in stepLexFiles.entries) {
    _loadLexicon(db, await _fetch('$_stepLex/$f', '$cache/${Uri.decodeComponent(f)}', pin: sha));
  }

  final zip = '$cache/cross-references.zip';
  await _fetchBytes(_xrefs, zip, pin: _xrefsSha256);
  final unzip = await Process.run('unzip', ['-o', '-q', zip, '-d', '$cache/xrefs']);
  if (unzip.exitCode != 0) throw StateError('unzip failed: ${unzip.stderr}');
  _loadXrefs(db, File('$cache/xrefs/cross_references.txt').readAsStringSync());
  _buildDailyVerses(db);
  final bible = BibleDb(db)..buildWordIndex();
  stdout.writeln(
    'BSB words aligned to the translation tables: ${bible.importBsbAlignment(tables)} verses',
  );
  final marks = parseBsbMarks(tablesText, bsb);
  if (marks.unreconciled.length > _maxUnreconciledMarks) {
    throw StateError(
      'BSB marks: ${marks.unreconciled.length} verses differ between bsb.txt and the tables '
      '(${marks.unreconciled.map((r) => r.label).join(', ')}); the pinned files expect at most '
      '$_maxUnreconciledMarks',
    );
  }
  stdout.writeln('BSB renderings: ${bible.importRenderings(tables)} number and phrase pairs');
  _requireWordsForEveryVerse(db);
  bible.importMarks(marks, 'BSB');
  stdout.writeln(
    'BSB marks: ${marks.verses.length} verses; left out because the files differ: '
    '${marks.unreconciled.map((r) => r.label).join(', ')}',
  );
}

/// Word rows read from the STEPBible files; every one must end up stored, none dropped by a clash.
var _wordRowsRead = 0;

/// Every BSB verse with text has Hebrew or Greek word rows. A verse without them means a numbering
/// or parsing defect upstream of the reader, so the build stops and names the verses.
void _requireWordsForEveryVerse(Database db) {
  final stored = db.select('SELECT COUNT(*) AS n FROM words').first['n'] as int;
  if (stored != _wordRowsRead) {
    throw StateError('Word rows: read $_wordRowsRead from the STEPBible files but stored $stored');
  }
  final missing = db.select(
    "SELECT book, chapter, verse FROM verses v WHERE translation = 'BSB' AND trim(text) != '' "
    'AND NOT EXISTS (SELECT 1 FROM words w WHERE w.book = v.book AND w.chapter = v.chapter '
    'AND w.verse = v.verse)',
  );
  if (missing.isEmpty) return;
  final names = [
    for (final r in missing) '${bookById(r['book'] as int).name} ${r['chapter']}:${r['verse']}',
  ];
  throw StateError('BSB verses without original-language words: ${names.join(', ')}');
}

/// Writes the meta rows and compacts the database; returns the build stamp.
String _writeMeta(Database db) {
  final built = DateTime.now().toUtc().toIso8601String();
  final translations = ['BSB', ...scrollmapperTranslations, 'WEB'].join(',');
  final meta = db.prepare('INSERT INTO meta VALUES (?, ?)');
  meta
    ..execute(['built', built])
    ..execute(['translations', translations])
    ..execute(['bsb_source', '$_bsb sha256:$_bsbSha256'])
    ..execute(['bsb_tables_source', '$_bsbTables sha256:$_bsbTablesSha256'])
    ..execute(['bsb_headings_source', '$_bsbUsfm sha256:$_bsbUsfmSha256'])
    ..dispose();
  db.execute('VACUUM');
  for (final t in [
    'verses',
    'words',
    'lexicon',
    'xrefs',
    'word_index',
    'gloss_index',
    'bsb_words',
    'headings',
    'bsb_renderings',
  ]) {
    final n = db.select('SELECT COUNT(*) AS n FROM $t').first['n'];
    stdout.writeln('$t: $n rows');
  }
  return built;
}

void _publish(File tmp, String out, String built) {
  tmp.renameSync(out);
  // The app compares this small file to decide whether to recopy the database, so it never has
  // to load the full asset just to check. Written last so it never stamps an unfinished build.
  File('$out.version').writeAsStringSync(built);
  stdout.writeln('wrote $out (${(File(out).lengthSync() / 1048576).toStringAsFixed(1)} MB)');
}

/// The report only helps a reviewer, so a failure to fetch the old text warns instead of failing.
Future<void> _writeDiffReport(List<VerseRow> bsb, String cache) async {
  final report = File('$cache/bsb-diff.md');
  // Removed first so a skipped report never leaves an earlier run's report looking current.
  if (report.existsSync()) report.deleteSync();
  try {
    final oldPath = '$cache/BSB-scrollmapper-${_oldBsbCommit.substring(0, 7)}.csv';
    final old = parseCsvBible(await _fetch(_oldBsb, oldPath, pin: _oldBsbSha256));
    final title = 'BSB: official bsb.txt against scrollmapper ${_oldBsbCommit.substring(0, 7)}';
    report.writeAsStringSync(verseDiffReport(old, bsb, title: title, watched: _watchedVerses));
    stdout.writeln('BSB diff report: ${report.path}');
  } on Object catch (e) {
    stderr.writeln('warning: skipped the BSB diff report: $e');
  }
}

/// Downloads [url] to [path] once, checking the bytes against [pin] on every run.
Future<Uint8List> _fetchBytes(String url, String path, {String? pin}) async {
  final f = File(path);
  if (!f.existsSync()) await _download(url, f, pin);
  final bytes = f.readAsBytesSync();
  if (pin != null) checkPin(bytes, pin, source: '$path (delete it to download $url again)');
  return bytes;
}

Future<String> _fetch(String url, String path, {String? pin}) async {
  var s = utf8.decode(await _fetchBytes(url, path, pin: pin));
  if (s.startsWith('\uFEFF')) s = s.substring(1);
  return s;
}

// Checked before it is written and renamed into place once complete, so a failed, wrong or
// interrupted download is never cached.
Future<void> _download(String url, File dest, String? pin) async {
  stdout.writeln('downloading $url');
  final r = await http.get(Uri.parse(url));
  if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} for $url');
  if (pin != null) checkPin(r.bodyBytes, pin, source: url);
  final part = File('${dest.path}.part')..writeAsBytesSync(r.bodyBytes);
  part.renameSync(dest.path);
}

/// A heading anchored to a verse the translation lacks would never show, so the build fails on
/// one rather than ship it silently.
void _loadHeadings(Database db, String translation, List<HeadingRow> rows) {
  final stray = BibleDb(db).importHeadings(rows, translation);
  if (stray > 0) {
    throw StateError('$translation: $stray headings anchor to verses it does not have');
  }
  stdout.writeln('$translation headings: ${rows.length}');
}

void _loadTranslation(Database db, String translation, String csv) {
  final rows = parseCsv(csv);
  final stmt = db.prepare(
    'INSERT INTO verses(translation, book, chapter, verse, text) VALUES (?, ?, ?, ?, ?)',
  );
  db.execute('BEGIN');
  var n = 0;
  for (final r in rows.skip(1)) {
    if (r.length < 4) continue;
    final book = bookFor(r[0]);
    if (book == null) throw StateError('unknown book "${r[0]}" in $translation');
    stmt.execute([translation, book.id, int.parse(r[1]), int.parse(r[2]), r[3].trim()]);
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  stdout.writeln('$translation: $n verses');
}

void _loadRows(Database db, String translation, List<VerseRow> rows) {
  loadVerseRows(db, translation, rows);
  stdout.writeln('$translation: ${rows.length} verses');
}

/// One verse per day of the year: the single verses Scripture itself points to most, by
/// OpenBible cross-reference votes. Data driven, nothing hand picked.
const daysInLeapYear = 366;

void _buildDailyVerses(Database db) {
  db.execute('''
    CREATE TABLE daily_verses(day INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER, verse INTEGER);
    INSERT INTO daily_verses(day, book, chapter, verse)
      SELECT ROW_NUMBER() OVER (ORDER BY total DESC), to_book, to_chapter, to_verse_start FROM (
        SELECT to_book, to_chapter, to_verse_start, SUM(votes) AS total FROM xrefs
        WHERE to_verse_start = to_verse_end
        GROUP BY to_book, to_chapter, to_verse_start ORDER BY total DESC LIMIT $daysInLeapYear);
  ''');
  stdout.writeln('daily verses: ${db.select('SELECT COUNT(*) AS n FROM daily_verses').first['n']}');
}

/// A STEPBible reference: book, chapter and verse, then optionally the verse number in another
/// tradition's numbering, in square or curly brackets ("Act.2.11[2.10]", "Rom.16.25{14.24}").
final _stepRef = RegExp(
  r'^([1-3]?[A-Za-z]{2,3})\.(\d+)\.(\d+)(?:[\[\{](\d+)\.(\d+)[\]\}])?(?:\((\d+\.\d+)\))?#(\d+)(?:=(\S*))?',
);
/// STEPBible's extended Strong's numbers have five digits (G20447); cut to four they name another word.
final _strongs = RegExp(r'[HG]\d{4,5}(?![0-9])[A-Za-z]?');

typedef _StepRef = ({int book, int chapter, int verse, int pos, (int, int)? other, String? hebrew, String type});

_StepRef? _ref(String col) {
  final m = _stepRef.firstMatch(col);
  if (m == null) return null;
  final book = bookFor(m[1]!);
  if (book == null) throw StateError('unknown STEP book ${m[1]}');
  return (
    book: book.id,
    chapter: int.parse(m[2]!),
    verse: int.parse(m[3]!),
    pos: int.parse(m[7]!),
    other: m[4] == null ? null : (int.parse(m[4]!), int.parse(m[5]!)),
    hebrew: m[6],
    type: m[8] ?? '',
  );
}

/// Hebrew rows. STEPBible's Hebrew references name the verse in English numbering and, in
/// parentheses, the Hebrew verse it came from, so one English verse can hold the words of two
/// Hebrew verses (Num.26.1 holds Num 25:19 and 26:1; a psalm's title at verse 0 holds its first
/// two Hebrew verses). Their positions both start at 1, so a later Hebrew verse is placed after
/// the earlier one's words rather than over them.
void _loadHebrew(Database db, String text) {
  db.execute(
    'CREATE TABLE IF NOT EXISTS word_types(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, '
    'type TEXT, PRIMARY KEY(book, chapter, verse, pos)) WITHOUT ROWID',
  );
  final kinds = db.prepare('INSERT INTO word_types VALUES (?, ?, ?, ?, ?)');
  final stmt = db.prepare('INSERT INTO words VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)');
  db.execute('BEGIN');
  var n = 0, typed = 0;
  final longest = <String, int>{};
  final offsets = <String, int>{};
  for (final line in text.split('\n')) {
    final c = line.split('\t');
    if (c.length < 6) continue;
    final r = _ref(c[0]);
    if (r == null) continue;
    final verse = '${r.book}:${r.chapter}:${r.verse}';
    // Words STEPBible reconstructs (type X) are numbered apart from the Leningrad words, so each
    // kind of numbering starts again at 1 inside the verse.
    final source = '$verse|${r.hebrew}|${r.type == 'X'}';
    final offset = offsets.putIfAbsent(source, () => longest[verse] ?? 0);
    final pos = offset + r.pos;
    if (pos > (longest[verse] ?? 0)) longest[verse] = pos;
    final strongs = _strongs.allMatches(c[4]).map((m) => m[0]!).join(' ');
    stmt.execute([
      r.book,
      r.chapter,
      r.verse,
      pos,
      c[1].trim(),
      c[2].trim(),
      c[3].trim(),
      strongs,
      c[5].trim(),
    ]);
    if (r.type != 'L') {
      kinds.execute([r.book, r.chapter, r.verse, pos, r.type]);
      typed++;
    }
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  kinds.dispose();
  _wordRowsRead += n;
  stdout.writeln('hebrew words: $n ($typed of them not plain Leningrad text, typed in word_types)');
}

/// Greek rows go in under the verse the BSB puts their words in. STEPBible numbers a few dozen
/// verses two ways (Rom.16.25{14.24}: the doxology some texts put after 14:23); for each such
/// verse the numbering whose BSB verse shares more Greek words with the rows wins, and a tie keeps
/// STEPBible's first number. Every choice is printed.
void _loadGreek(Database db, String text, Map<Ref, List<BsbRow>> tables) {
  final rows = <({_StepRef r, List<String> c})>[];
  for (final line in text.split('\n')) {
    final c = line.split('\t');
    if (c.length < 5) continue;
    final r = _ref(c[0]);
    if (r != null) rows.add((r: r, c: c));
  }
  // Ref has no equality, so the tables are looked up by a key of book, chapter and verse.
  final byVerse = {
    for (final e in tables.entries) '${e.key.book.id}:${e.key.chapter}:${e.key.verseStart}': e.value,
  };
  Set<String> bsbCodes(int book, int chapter, int verse) => {
    for (final row in byVerse['$book:$chapter:$verse'] ?? const <BsbRow>[])
      if (row.code.isNotEmpty) row.code,
  };
  final chosen = <String, (int, int)>{};
  final wanted = <String, bool>{};
  final groups = <String, List<({_StepRef r, List<String> c})>>{};
  for (final row in rows) {
    if (row.r.other == null) continue;
    groups.putIfAbsent('${row.r.book}:${row.r.chapter}:${row.r.verse}', () => []).add(row);
  }
  for (final e in groups.entries) {
    final first = e.value.first.r;
    final other = first.other!;
    final mine = {
      for (final row in e.value)
        for (final m in _strongs.allMatches(row.c[3])) _base(m[0]!),
    };
    final here = bsbCodes(first.book, first.chapter, first.verse).intersection(mine).length;
    final there = bsbCodes(first.book, other.$1, other.$2).intersection(mine).length;
    final move = there > here;
    chosen[e.key] = move ? other : (first.chapter, first.verse);
    wanted[e.key] = move;
    stdout.writeln(
      '  greek ${bookById(first.book).name} ${first.chapter}:${first.verse} [${other.$1}:${other.$2}]: '
      '${move ? 'other' : 'first'} ($here vs $there Greek words shared with the BSB)',
    );
  }
  // A group may only move into a verse nobody else writes to: no rows of its own there, and no
  // other group staying or arriving there. Phil 1:16 and 1:17 swap, so each is the other's.
  final ownVerses = {
    for (final row in rows)
      if (row.r.other == null) '${row.r.book}:${row.r.chapter}:${row.r.verse}',
  };
  var changed = true;
  while (changed) {
    changed = false;
    for (final e in groups.entries) {
      if (wanted[e.key] != true) continue;
      final first = e.value.first.r;
      final target = '${first.book}:${chosen[e.key]!.$1}:${chosen[e.key]!.$2}';
      final clash =
          ownVerses.contains(target) ||
          groups.entries.any((o) {
            if (o.key == e.key) return false;
            final f = o.value.first.r;
            final at = chosen[o.key]!;
            return '${f.book}:${at.$1}:${at.$2}' == target;
          });
      if (!clash) continue;
      chosen[e.key] = (first.chapter, first.verse);
      wanted[e.key] = false;
      changed = true;
      stdout.writeln(
        '  greek ${bookById(first.book).name} ${first.chapter}:${first.verse} kept: the other verse already has its own words',
      );
    }
  }
  final stmt = db.prepare('INSERT INTO words VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)');
  db.execute('BEGIN');
  var n = 0;
  for (final row in rows) {
    final r = row.r, c = row.c;
    var chapter = r.chapter, verse = r.verse;
    if (r.other != null) (chapter, verse) = chosen['${r.book}:${r.chapter}:${r.verse}']!;
    final paren = c[1].indexOf(' (');
    final original = paren < 0 ? c[1].trim() : c[1].substring(0, paren).trim();
    final translit = paren < 0 ? '' : c[1].substring(paren + 2).replaceAll(')', '').trim();
    final eq = c[3].indexOf('=');
    final strongs = _strongs.allMatches(c[3]).map((m) => m[0]!).join(' ');
    final morph = eq < 0 ? '' : c[3].substring(eq + 1).trim();
    final gloss = c[2].replaceFirst(_otherNumbering, '').trim();
    stmt.execute([r.book, chapter, verse, r.pos, original, translit, gloss, strongs, morph]);
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  _wordRowsRead += n;
  stdout.writeln('greek words: $n');
}

/// STEPBible prefixes the first English word of such a verse with the other numbering: "{14.24} To Him".
final _otherNumbering = RegExp(r'^[\[\{]\d+\.\d+[\]\}]\s*');

/// The number without its letter suffix, as the BSB tables write it: G1234a is G1234.
String _base(String code) => code.replaceAll(RegExp(r'[A-Za-z]$'), '');

/// The Hebrew entries are Online Bible's abridged Brown-Driver-Briggs, through STEPBible.
const hebrewSource = 'OB';
final _definitionSource = RegExp(r'\((AS|ML)\)\s*$');
final _fiveDigits = RegExp(r'^[HG]\d{5}');
final _lexRow = RegExp(r'^[HG]\d{4,5}[a-z]?\t');
final _tag = RegExp(r'<[^>]+>');
final _ws = RegExp(r'\s+');

/// Loads one lexicon file. A five-digit entry is STEPBible's own extension of Strong's; it is kept
/// only when the text uses its number, so the lexicon holds no entry no verse can open.
void _loadLexicon(Database db, String text) {
  final used = {
    for (final r in db.select('SELECT DISTINCT strongs FROM words'))
      for (final m in _strongs.allMatches(r['strongs'] as String)) _base(m[0]!),
  };
  db.execute('CREATE TABLE IF NOT EXISTS lexicon_source(key TEXT PRIMARY KEY, source TEXT)');
  final stmt = db.prepare('INSERT OR IGNORE INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?)');
  final sources = db.prepare('INSERT OR IGNORE INTO lexicon_source VALUES (?, ?)');
  db.execute('BEGIN');
  var n = 0, withheld = 0;
  for (final line in text.split('\n')) {
    if (!_lexRow.hasMatch(line)) continue;
    final c = line.split('\t');
    if (c.length < 8) continue;
    final number = c[0].trim().toUpperCase();
    if (_fiveDigits.hasMatch(number) && !used.contains(_base(number))) continue;
    var def = c[7].replaceAll(_tag, ' ').replaceAll(_ws, ' ').trim();
    final base = number.replaceAll(RegExp(r'[A-Z]$'), '');
    final key = c[1].trim().split(' ').first;
    // A Greek entry ends with the work its definition comes from: (AS) Abbott-Smith, (ML) Middle
    // Liddell from Perseus, or nothing. Only Abbott-Smith's definitions ship in this database;
    // Middle Liddell is share-alike and has its own file, and an entry with no stated source
    // keeps its gloss alone.
    var source = number.startsWith('H') ? hebrewSource : '';
    if (number.startsWith('G')) {
      final tag = _definitionSource.firstMatch(def);
      source = tag?[1] ?? '';
      if (tag != null) def = def.substring(0, tag.start).replaceAll(RegExp(r'†\s*$'), '').trim();
      if (source != 'AS') {
        def = '';
        withheld++;
      }
    }
    stmt.execute([key, base, c[3].trim(), c[4].trim(), c[5].trim(), c[6].trim(), def]);
    sources.execute([key, source]);
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  sources.dispose();
  stdout.writeln('lexicon entries: $n ($withheld Greek definitions withheld: Middle Liddell or no stated source)');
}

final _xrefRef = RegExp(r'^([1-3]?[A-Za-z]+)\.(\d+)\.(\d+)$');

(int, int, int)? _xref(String s) {
  final m = _xrefRef.firstMatch(s.trim());
  if (m == null) return null;
  final book = bookFor(m[1]!);
  if (book == null) return null;
  return (book.id, int.parse(m[2]!), int.parse(m[3]!));
}

void _loadXrefs(Database db, String text) {
  final stmt = db.prepare('INSERT INTO xrefs VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
  db.execute('BEGIN');
  var n = 0, skipped = 0;
  for (final line in text.split('\n').skip(1)) {
    final c = line.split('\t');
    if (c.length < 3) continue;
    final from = _xref(c[0]);
    final range = c[1].split('-');
    final to = _xref(range[0]);
    if (from == null || to == null) {
      skipped++;
      continue;
    }
    var end = to.$3;
    if (range.length > 1) {
      final e = _xref(range[1]);
      if (e != null && e.$1 == to.$1 && e.$2 == to.$2) end = e.$3;
    }
    stmt.execute([
      from.$1,
      from.$2,
      from.$3,
      to.$1,
      to.$2,
      to.$3,
      end,
      int.tryParse(c[2].trim()) ?? 0,
    ]);
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  stdout.writeln('xrefs: $n (skipped $skipped)');
}
