import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const defaultDbPath = '../../assets/berea.sqlite';

/// File pointing to the Bible database, configurable via BEREA_DB.
File bibleDbFile() => File(Platform.environment['BEREA_DB'] ?? defaultDbPath);

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

@Deprecated('Use needsBibleText or needsFullDatabase')
final String? needsBuiltBible = needsFullDatabase;
