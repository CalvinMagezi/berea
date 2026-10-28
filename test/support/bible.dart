import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';

const john316 =
    'For God so loved the world that He gave His one and only Son, that everyone who believes in '
    'Him shall not perish but have eternal life.';

/// An in-memory Bible holding John 3:16 in the BSB, with the tables retrieval reads.
BibleDb testBible() {
  final raw = sqlite3.openInMemory()
    ..execute('''
      CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER,
        verse INTEGER, text TEXT);
      CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id');
      CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT,
        translit TEXT, gloss TEXT, strongs TEXT, morph TEXT);
      CREATE TABLE lexicon(key TEXT, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT,
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

/// Null when the built Bible database is here; else why a test that opens it is skipped. CI
/// writes an empty stand-in, since the database is built, not committed.
final String? needsBuiltBible = () {
  final db = File('assets/berea.sqlite');
  return db.existsSync() && db.lengthSync() > 0
      ? null
      : 'needs the built Bible database; CI has an empty stand-in';
}();
