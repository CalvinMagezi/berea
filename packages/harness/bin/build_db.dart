// Builds assets/berea.sqlite from public domain and CC BY datasets.
// Usage: dart run bin/build_db.dart [--out ../../assets/berea.sqlite] [--cache .cache]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea_harness/src/books.dart';
import 'package:berea_harness/src/csv.dart';
import 'package:berea_harness/src/importers.dart';
import 'package:berea_harness/src/source_checks.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

const _scrollmapper =
    'https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/csv';
const _bsb = 'https://bereanbible.com/bsb.txt';
// Bump only after reading the diff report for the new text; the narrated audio follows it.
const _bsbSha256 = '2ac3af1de52d4e68261cba91d85c320b7eadc6560e830d99e591767b8ff5ca96';
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
const _step = 'https://raw.githubusercontent.com/STEPBible/STEPBible-Data/master';
const _stepText = '$_step/Translators%20Amalgamated%20OT%2BNT';
const _stepLex = '$_step/Lexicons';
const _xrefs = 'https://a.openbible.info/data/cross-references.zip';
const _web = 'https://ebible.org/Scriptures/engwebp_usfm.zip';

const scrollmapperTranslations = ['KJV'];
const stepTextFiles = [
  'TAHOT%20Gen-Deu%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt',
  'TAHOT%20Jos-Est%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt',
  'TAHOT%20Job-Sng%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt',
  'TAHOT%20Isa-Mal%20-%20Translators%20Amalgamated%20Hebrew%20OT%20-%20STEPBible.org%20CC%20BY.txt',
  'TAGNT%20Mat-Jhn%20-%20Translators%20Amalgamated%20Greek%20NT%20-%20STEPBible.org%20CC-BY.txt',
  'TAGNT%20Act-Rev%20-%20Translators%20Amalgamated%20Greek%20NT%20-%20STEPBible.org%20CC-BY.txt',
];
const stepLexFiles = [
  'TBESH%20-%20Translators%20Brief%20lexicon%20of%20Extended%20Strongs%20for%20Hebrew%20-%20STEPBible.org%20CC%20BY.txt',
  'TBESG%20-%20Translators%20Brief%20lexicon%20of%20Extended%20Strongs%20for%20Greek%20-%20STEPBible.org%20CC%20BY.txt',
];
const maxDefinitionChars = 600;

Future<void> main(List<String> args) async {
  var out = '../../assets/berea.sqlite';
  var cache = '.cache';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--out') out = args[i + 1];
    if (args[i] == '--cache') cache = args[i + 1];
  }
  Directory(cache).createSync(recursive: true);
  final bsb = parseBsbText(await _fetch(_bsb, '$cache/bsb.txt', pin: _bsbSha256));
  checkVerseCount(bsb);
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
      built = _writeMeta(db);
    } finally {
      db.dispose();
    }
    _publish(tmp, out, built);
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

void _createSchema(Database db) => db.execute('''
  PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;
  CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT);
  CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id', tokenize='porter unicode61');
  CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT, translit TEXT, gloss TEXT, strongs TEXT, morph TEXT, PRIMARY KEY(book, chapter, verse, pos)) WITHOUT ROWID;
  CREATE TABLE lexicon(key TEXT PRIMARY KEY, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT, definition TEXT);
  CREATE INDEX lexicon_base ON lexicon(base);
  CREATE TABLE xrefs(from_book INTEGER, from_chapter INTEGER, from_verse INTEGER, to_book INTEGER, to_chapter INTEGER, to_verse_start INTEGER, to_verse_end INTEGER, votes INTEGER);
  CREATE INDEX xrefs_from ON xrefs(from_book, from_chapter, from_verse);
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
''');

Future<void> _loadData(Database db, List<VerseRow> bsb, String cache) async {
  _loadRows(db, 'BSB', bsb);
  for (final t in scrollmapperTranslations) {
    _loadTranslation(db, t, await _fetch('$_scrollmapper/$t.csv', '$cache/$t.csv'));
  }
  final web = await _fetchBytes(_web, '$cache/engwebp_usfm.zip');
  _loadRows(db, 'WEB', parseBibleFile('engwebp_usfm.zip', web));
  db.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')");

  for (final f in stepTextFiles) {
    final text = await _fetch('$_stepText/$f', '$cache/${Uri.decodeComponent(f)}');
    f.startsWith('TAHOT') ? _loadHebrew(db, text) : _loadGreek(db, text);
  }
  for (final f in stepLexFiles) {
    _loadLexicon(db, await _fetch('$_stepLex/$f', '$cache/${Uri.decodeComponent(f)}'));
  }

  final zip = '$cache/cross-references.zip';
  await _fetchBytes(_xrefs, zip);
  final unzip = await Process.run('unzip', ['-o', '-q', zip, '-d', '$cache/xrefs']);
  if (unzip.exitCode != 0) throw StateError('unzip failed: ${unzip.stderr}');
  _loadXrefs(db, File('$cache/xrefs/cross_references.txt').readAsStringSync());
  _buildDailyVerses(db);
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
    ..dispose();
  db.execute('VACUUM');
  for (final t in ['verses', 'words', 'lexicon', 'xrefs']) {
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
  final path = '$cache/bsb-diff.md';
  try {
    final oldPath = '$cache/BSB-scrollmapper-${_oldBsbCommit.substring(0, 7)}.csv';
    final old = parseCsvBible(await _fetch(_oldBsb, oldPath, pin: _oldBsbSha256));
    final title = 'BSB: official bsb.txt against scrollmapper ${_oldBsbCommit.substring(0, 7)}';
    File(path).writeAsStringSync(verseDiffReport(old, bsb, title: title, watched: _watchedVerses));
    stdout.writeln('BSB diff report: $path');
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
  if (s.startsWith('﻿')) s = s.substring(1);
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
  final stmt = db.prepare(
    'INSERT INTO verses(translation, book, chapter, verse, text) VALUES (?, ?, ?, ?, ?)',
  );
  db.execute('BEGIN');
  for (final r in rows) {
    stmt.execute([translation, r.book.id, r.chapter, r.verse, r.text]);
  }
  db.execute('COMMIT');
  stmt.dispose();
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

final _stepRef = RegExp(r'^([1-3]?[A-Za-z]{2,3})\.(\d+)\.(\d+)(?:\(\d+\.\d+\))?#(\d+)');
final _strongs = RegExp(r'[HG]\d{4}[A-Za-z]?');

(int, int, int, int)? _ref(String col) {
  final m = _stepRef.firstMatch(col);
  if (m == null) return null;
  final book = bookFor(m[1]!);
  if (book == null) throw StateError('unknown STEP book ${m[1]}');
  return (book.id, int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!));
}

void _loadHebrew(Database db, String text) {
  final stmt = db.prepare('INSERT OR IGNORE INTO words VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)');
  db.execute('BEGIN');
  var n = 0;
  for (final line in text.split('\n')) {
    final c = line.split('\t');
    if (c.length < 6) continue;
    final r = _ref(c[0]);
    if (r == null) continue;
    final strongs = _strongs.allMatches(c[4]).map((m) => m[0]!).join(' ');
    stmt.execute([
      r.$1,
      r.$2,
      r.$3,
      r.$4,
      c[1].trim(),
      c[2].trim(),
      c[3].trim(),
      strongs,
      c[5].trim(),
    ]);
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  stdout.writeln('hebrew words: $n');
}

void _loadGreek(Database db, String text) {
  final stmt = db.prepare('INSERT OR IGNORE INTO words VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)');
  db.execute('BEGIN');
  var n = 0;
  for (final line in text.split('\n')) {
    final c = line.split('\t');
    if (c.length < 5) continue;
    final r = _ref(c[0]);
    if (r == null) continue;
    final paren = c[1].indexOf(' (');
    final original = paren < 0 ? c[1].trim() : c[1].substring(0, paren).trim();
    final translit = paren < 0 ? '' : c[1].substring(paren + 2).replaceAll(')', '').trim();
    final eq = c[3].indexOf('=');
    final strongs = _strongs.allMatches(c[3]).map((m) => m[0]!).join(' ');
    final morph = eq < 0 ? '' : c[3].substring(eq + 1).trim();
    stmt.execute([r.$1, r.$2, r.$3, r.$4, original, translit, c[2].trim(), strongs, morph]);
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  stdout.writeln('greek words: $n');
}

final _lexRow = RegExp(r'^[HG]\d{4}[a-z]?\t');
final _tag = RegExp(r'<[^>]+>');
final _ws = RegExp(r'\s+');

void _loadLexicon(Database db, String text) {
  final stmt = db.prepare('INSERT OR IGNORE INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?)');
  db.execute('BEGIN');
  var n = 0;
  for (final line in text.split('\n')) {
    if (!_lexRow.hasMatch(line)) continue;
    final c = line.split('\t');
    if (c.length < 8) continue;
    var def = c[7].replaceAll(_tag, ' ').replaceAll(_ws, ' ').trim();
    if (def.length > maxDefinitionChars) def = '${def.substring(0, maxDefinitionChars)}...';
    final base = c[0].trim().toUpperCase().replaceAll(RegExp(r'[A-Z]$'), '');
    final key = c[1].trim().split(' ').first;
    stmt.execute([key, base, c[3].trim(), c[4].trim(), c[5].trim(), c[6].trim(), def]);
    n++;
  }
  db.execute('COMMIT');
  stmt.dispose();
  stdout.writeln('lexicon entries: $n');
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
