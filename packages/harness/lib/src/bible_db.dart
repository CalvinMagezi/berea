import 'package:sqlite3/sqlite3.dart';

import 'books.dart';
import 'importers.dart';
import 'ref_parser.dart';

class Verse {
  final Book book;
  final int chapter;
  final int verse;
  final String text;
  const Verse(this.book, this.chapter, this.verse, this.text);
  String get label => '${book.name} $chapter:$verse';
}

class WordTag {
  final String original;
  final String translit;
  final String gloss;
  final String strongs;
  final String morph;
  const WordTag(this.original, this.translit, this.gloss, this.strongs, this.morph);
}

class LexEntry {
  final String key;
  final String lemma;
  final String translit;
  final String pos;
  final String gloss;
  final String definition;
  const LexEntry(this.key, this.lemma, this.translit, this.pos, this.gloss, this.definition);
}

class XRef {
  final Ref to;
  final int votes;
  const XRef(this.to, this.votes);
}

const defaultTranslation = 'BSB';
const maxPassageVerses = 40;

class BibleDb {
  final Database db;
  BibleDb(this.db);

  /// Read-write so user-imported translations can live in the same file.
  factory BibleDb.open(String path) => BibleDb(sqlite3.open(path));

  void close() => db.dispose();

  List<String> translations() => [
    for (final r in db.select('SELECT DISTINCT translation FROM verses ORDER BY translation'))
      r['translation'] as String,
  ];

  int chapterCount(Book book, {String translation = defaultTranslation}) {
    final row = db.select(
      'SELECT MAX(chapter) AS n FROM verses WHERE translation = ? AND book = ?',
      [translation, book.id],
    ).first;
    return (row['n'] as int?) ?? 0;
  }

  /// Imports a `Book,Chapter,Verse,Text` CSV (the scrollmapper layout) as [code].
  int importCsv(String csv, String code) => importRows(parseCsvBible(csv), code);

  /// Stores [rows] as translation [code], replacing any existing rows for that code, and rebuilds
  /// the search index. Returns the verse count. Nothing changes if [rows] is empty.
  int importRows(List<VerseRow> rows, String code) {
    if (rows.isEmpty) throw const FormatException('no verses found');
    final insert = db.prepare(
      'INSERT INTO verses(translation, book, chapter, verse, text) VALUES (?, ?, ?, ?, ?)',
    );
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM verses WHERE translation = ?', [code]);
      for (final r in rows) {
        insert.execute([code, r.book.id, r.chapter, r.verse, r.text]);
      }
      db.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')");
      db.execute('COMMIT');
      return rows.length;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      insert.dispose();
    }
  }

  Verse _verse(Row r) => Verse(
    bookById(r['book'] as int),
    r['chapter'] as int,
    r['verse'] as int,
    r['text'] as String,
  );

  List<Verse> passage(Ref ref, {String translation = defaultTranslation}) {
    final vs = ref.verseStart ?? 1;
    final ve = ref.verseStart == null ? 999 : (ref.verseEnd ?? vs);
    final rows = db.select(
      'SELECT book, chapter, verse, text FROM verses '
      'WHERE translation = ? AND book = ? AND chapter = ? AND verse BETWEEN ? AND ? '
      'ORDER BY verse LIMIT ?',
      [translation, ref.book.id, ref.chapter, vs, ve, maxPassageVerses],
    );
    return rows.map(_verse).toList();
  }

  bool exists(Ref ref, {String translation = defaultTranslation}) {
    final vs = ref.verseStart ?? 1;
    final ve = ref.verseEnd ?? vs;
    final row = db.select(
      'SELECT COUNT(*) AS n FROM verses WHERE translation = ? AND book = ? AND chapter = ? AND verse IN (?, ?)',
      [translation, ref.book.id, ref.chapter, vs, ve],
    ).first;
    return (row['n'] as int) == (vs == ve ? 1 : 2);
  }

  static final _word = RegExp(r"[A-Za-z']{3,}");
  static const _stop = {
    'the',
    'and',
    'that',
    'this',
    'with',
    'for',
    'what',
    'does',
    'mean',
    'about',
    'from',
    'have',
    'why',
    'how',
    'who',
    'are',
    'was',
    'were',
    'bible',
    'verse',
    'passage',
    'say',
    'says',
    'tell',
    'explain',
    'study',
    'can',
    'you',
    'please',
    'should',
    'would',
    'into',
    'his',
    'her',
    'their',
  };

  String? ftsQuery(String text) {
    final terms = _word
        .allMatches(text)
        .map((m) => m[0]!.toLowerCase())
        .where((w) => !_stop.contains(w))
        .toSet();
    if (terms.isEmpty) return null;
    return terms.map((t) => '"$t"').join(' OR ');
  }

  List<Verse> search(String text, {String translation = defaultTranslation, int k = 6}) {
    final q = ftsQuery(text);
    if (q == null) return const [];
    final rows = db.select(
      'SELECT v.book, v.chapter, v.verse, v.text FROM verses_fts f '
      'JOIN verses v ON v.id = f.rowid '
      'WHERE verses_fts MATCH ? AND v.translation = ? '
      'ORDER BY bm25(verses_fts) LIMIT ?',
      [q, translation, k],
    );
    return rows.map(_verse).toList();
  }

  List<WordTag> words(Ref ref) {
    final vs = ref.verseStart ?? 1;
    final ve = ref.verseStart == null ? 999 : (ref.verseEnd ?? vs);
    final rows = db.select(
      'SELECT original, translit, gloss, strongs, morph FROM words '
      'WHERE book = ? AND chapter = ? AND verse BETWEEN ? AND ? ORDER BY verse, pos',
      [ref.book.id, ref.chapter, vs, ve],
    );
    return [
      for (final r in rows)
        WordTag(
          r['original'] as String,
          r['translit'] as String,
          r['gloss'] as String,
          r['strongs'] as String,
          r['morph'] as String,
        ),
    ];
  }

  LexEntry? lexicon(String strongs) {
    final base = strongs.replaceAll(RegExp(r'[A-Za-z]$'), '');
    final rows = db.select(
      'SELECT key, lemma, translit, pos, gloss, definition FROM lexicon '
      'WHERE key = ? OR base = ? ORDER BY (key = ?) DESC, key LIMIT 1',
      [strongs, base, strongs],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return LexEntry(
      r['key'] as String,
      r['lemma'] as String,
      r['translit'] as String,
      r['pos'] as String,
      r['gloss'] as String,
      r['definition'] as String,
    );
  }

  List<XRef> xrefs(Ref ref, {int k = 8}) {
    final vs = ref.verseStart ?? 1;
    final ve = ref.verseStart == null ? 999 : (ref.verseEnd ?? vs);
    final rows = db.select(
      'SELECT to_book, to_chapter, to_verse_start, to_verse_end, MAX(votes) AS votes FROM xrefs '
      'WHERE from_book = ? AND from_chapter = ? AND from_verse BETWEEN ? AND ? '
      'GROUP BY to_book, to_chapter, to_verse_start, to_verse_end ORDER BY votes DESC LIMIT ?',
      [ref.book.id, ref.chapter, vs, ve, k],
    );
    return [
      for (final r in rows)
        XRef(
          Ref(
            bookById(r['to_book'] as int),
            r['to_chapter'] as int,
            r['to_verse_start'] as int,
            r['to_verse_end'] as int,
          ),
          r['votes'] as int,
        ),
    ];
  }
}
