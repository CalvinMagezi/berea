import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const john316 =
    'For God so loved the world that He gave His one and only Son, that everyone who believes in '
    'Him shall not perish but have eternal life.';

const defaultDbPath = 'assets/berea.sqlite';

/// File pointing to the Bible database, configurable via BEREA_DB.
File bibleDbFile() => File(Platform.environment['BEREA_DB'] ?? defaultDbPath);

/// Intercepts rootBundle asset loading if BEREA_DB points to a different database file.
void ensureBereaDbAssets() {
  final override = Platform.environment['BEREA_DB'];
  if (override == null) return;
  final file = File(override);
  if (!file.existsSync()) return;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
    if (message == null) return null;
    final key = utf8.decode(message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
    if (key == defaultDbPath) {
      return file.readAsBytesSync().buffer.asByteData();
    }
    if (key == '$defaultDbPath.version') {
      final versionFile = File('$override.version');
      final version = versionFile.existsSync() ? versionFile.readAsStringSync() : 'ci';
      return utf8.encode(version).buffer.asByteData();
    }
    final f = File(key);
    if (f.existsSync()) return f.readAsBytesSync().buffer.asByteData();
    return null;
  });
}

/// An in-memory Bible holding John 3:16 in the BSB, with the tables retrieval reads.
BibleDb testBible() {
  final raw = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER,
        verse INTEGER, text TEXT);
      CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id');
      CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT,
        translit TEXT, gloss TEXT, strongs TEXT, morph TEXT);
      CREATE TABLE lexicon(key TEXT PRIMARY KEY, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT,
        definition TEXT);
      CREATE TABLE xrefs(from_book INTEGER, from_chapter INTEGER, from_verse INTEGER,
        to_book INTEGER, to_chapter INTEGER, to_verse_start INTEGER, to_verse_end INTEGER,
        votes INTEGER);
    ''');
  raw.execute(
    "INSERT INTO verses(translation, book, chapter, verse, text) VALUES ('BSB', 43, 3, 16, ?)",
    [john316],
  );
  raw.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')");
  return BibleDb(raw);
}

/// Null when the database holding the BSB verse text is present; else why a test is skipped.
final String? needsBibleText = () {
  final db = bibleDbFile();
  if (!db.existsSync() || db.lengthSync() == 0) {
    return 'needs the Bible text; CI has an empty stand-in';
  }
  return null;
}();

/// Null when the full Bible database (words, lexicon, xrefs) is present; else why a test is skipped.
final String? needsFullDatabase = () {
  final db = bibleDbFile();
  if (!db.existsSync() || db.lengthSync() == 0) {
    return 'needs the full Bible database; CI has an empty stand-in';
  }
  try {
    final raw = sqlite3.open(db.path, mode: OpenMode.readOnly);
    try {
      final rows = raw.select('SELECT 1 FROM words LIMIT 1');
      if (rows.isEmpty) {
        return 'needs the full Bible database (words, lexicon, xrefs); this database has BSB text only';
      }
    } finally {
      raw.dispose();
    }
  } catch (e) {
    return 'needs the full Bible database: $e';
  }
  return null;
}();
