// Builds assets/berea.sqlite from public domain and CC BY datasets.
// Usage: dart run bin/build_db.dart [--out ../../assets/berea.sqlite] [--cache .cache]
import 'dart:io';

import 'package:berea_harness/src/books.dart';
import 'package:berea_harness/src/csv.dart';
import 'package:berea_harness/src/importers.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

const _scrollmapper =
    'https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/csv';
const _step = 'https://raw.githubusercontent.com/STEPBible/STEPBible-Data/master';
const _stepText = '$_step/Translators%20Amalgamated%20OT%2BNT';
const _stepLex = '$_step/Lexicons';
const _xrefs = 'https://a.openbible.info/data/cross-references.zip';
const _web = 'https://ebible.org/Scriptures/engwebp_usfm.zip';

const translations = ['BSB', 'KJV'];
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
  Directory(File(out).parent.path).createSync(recursive: true);
  if (File(out).existsSync()) File(out).deleteSync();

  final db = sqlite3.open(out);
  db.execute('''
    PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;
    CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id');
    CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT, translit TEXT, gloss TEXT, strongs TEXT, morph TEXT, PRIMARY KEY(book, chapter, verse, pos)) WITHOUT ROWID;
    CREATE TABLE lexicon(key TEXT PRIMARY KEY, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT, definition TEXT);
    CREATE INDEX lexicon_base ON lexicon(base);
    CREATE TABLE xrefs(from_book INTEGER, from_chapter INTEGER, from_verse INTEGER, to_book INTEGER, to_chapter INTEGER, to_verse_start INTEGER, to_verse_end INTEGER, votes INTEGER);
    CREATE INDEX xrefs_from ON xrefs(from_book, from_chapter, from_verse);
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  ''');

  for (final t in translations) {
    final csv = await _fetch('$_scrollmapper/$t.csv', '$cache/$t.csv');
    _loadTranslation(db, t, csv);
  }
  final webZip = File('$cache/engwebp_usfm.zip');
  if (!webZip.existsSync()) {
    stdout.writeln('downloading $_web');
    webZip.writeAsBytesSync((await http.get(Uri.parse(_web))).bodyBytes);
  }
  _loadRows(db, 'WEB', parseBibleFile('engwebp_usfm.zip', webZip.readAsBytesSync()));
  db.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')");

  for (final f in stepTextFiles) {
    final text = await _fetch('$_stepText/$f', '$cache/${Uri.decodeComponent(f)}');
    f.startsWith('TAHOT') ? _loadHebrew(db, text) : _loadGreek(db, text);
  }
  for (final f in stepLexFiles) {
    _loadLexicon(db, await _fetch('$_stepLex/$f', '$cache/${Uri.decodeComponent(f)}'));
  }

  final zip = '$cache/cross-references.zip';
  if (!File(zip).existsSync()) {
    File(zip).writeAsBytesSync((await http.get(Uri.parse(_xrefs))).bodyBytes);
  }
  final unzip = await Process.run('unzip', ['-o', '-q', zip, '-d', '$cache/xrefs']);
  if (unzip.exitCode != 0) throw StateError('unzip failed: ${unzip.stderr}');
  _loadXrefs(db, File('$cache/xrefs/cross_references.txt').readAsStringSync());

  db.execute("INSERT INTO meta VALUES('built', '${DateTime.now().toUtc().toIso8601String()}')");
  db.execute("INSERT INTO meta VALUES('translations', '${[...translations, 'WEB'].join(',')}')");
  db.execute('VACUUM');
  for (final t in ['verses', 'words', 'lexicon', 'xrefs']) {
    final n = db.select('SELECT COUNT(*) AS n FROM $t').first['n'];
    stdout.writeln('$t: $n rows');
  }
  db.dispose();
  stdout.writeln('wrote $out (${(File(out).lengthSync() / 1048576).toStringAsFixed(1)} MB)');
}

Future<String> _fetch(String url, String path) async {
  final f = File(path);
  if (!f.existsSync()) {
    stdout.writeln('downloading $url');
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} for $url');
    f.writeAsBytesSync(r.bodyBytes);
  }
  var s = f.readAsStringSync();
  if (s.startsWith('﻿')) s = s.substring(1);
  return s;
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
