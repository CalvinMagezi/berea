import 'dart:io';

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

/// Translation codes are short uppercase identifiers; they also name files on disk.
const translationCodeMax = 8;
final translationCode = RegExp('^[A-Z0-9]{1,$translationCodeMax}\$');
const maxPassageVerses = 40;

class BibleDb {
  final Database db;
  BibleDb(this.db);

  /// Read-write so user-imported translations can live in the same file.
  factory BibleDb.open(String path) => BibleDb(sqlite3.open(path));

  void close() => db.dispose();

  /// Translations the database was built with, from its meta table.
  Set<String> bundledTranslations() {
    final rows = db.select("SELECT value FROM meta WHERE key = 'translations'");
    return rows.isEmpty ? const {} : (rows.first['value'] as String).split(',').toSet();
  }

  List<String> translations() => [
    for (final r in db.select('SELECT DISTINCT translation FROM verses ORDER BY translation'))
      r['translation'] as String,
  ];

  /// Verse of the day for [date], cycling through the database's daily list. Null on databases
  /// built before the list existed.
  Ref? dailyVerse(DateTime date) {
    final has = db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'daily_verses'",
    );
    if (has.isEmpty) return null;
    final count = db.select('SELECT COUNT(*) AS n FROM daily_verses').first['n'] as int;
    if (count == 0) return null;
    final dayOfYear = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(date.year)).inDays;
    final r = db.select('SELECT book, chapter, verse FROM daily_verses WHERE day = ?', [
      dayOfYear % count + 1,
    ]).first;
    return Ref(bookById(r['book'] as int), r['chapter'] as int, r['verse'] as int);
  }

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
    if (!translationCode.hasMatch(code)) {
      throw FormatException('translation code must be 1 to 8 letters or digits, not "$code"');
    }
    if (rows.isEmpty) throw const FormatException('no verses found');
    final unique = <String, VerseRow>{
      for (final r in rows) '${r.book.id}:${r.chapter}:${r.verse}': r,
    };
    rows = unique.values.toList();
    final insert = db.prepare(
      'INSERT INTO verses(translation, book, chapter, verse, text) VALUES (?, ?, ?, ?, ?)',
    );
    db.execute('BEGIN');
    try {
      // Keep the search index in step for this translation only; a full rebuild would touch
      // every verse of every translation.
      db.execute(
        "INSERT INTO verses_fts(verses_fts, rowid, text) "
        "SELECT 'delete', id, text FROM verses WHERE translation = ?",
        [code],
      );
      db.execute('DELETE FROM verses WHERE translation = ?', [code]);
      for (final r in rows) {
        insert.execute([code, r.book.id, r.chapter, r.verse, r.text]);
      }
      db.execute(
        'INSERT INTO verses_fts(rowid, text) SELECT id, text FROM verses WHERE translation = ?',
        [code],
      );
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
      'SELECT COUNT(DISTINCT verse) AS n FROM verses WHERE translation = ? AND book = ? AND chapter = ? AND verse IN (?, ?)',
      [translation, ref.book.id, ref.chapter, vs, ve],
    ).first;
    return (row['n'] as int) == (vs == ve ? 1 : 2);
  }

  static final _word = RegExp(r"[A-Za-z']{3,}");

  /// Words that carry no topic: question scaffolding and very common English.
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
    'verses',
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
    'teach',
    'teaches',
    'teaching',
    'scripture',
    'scriptures',
    'christian',
    'christians',
    'think',
    'deal',
    'wrong',
    'right',
    'way',
    'ways',
    'when',
    'where',
    'which',
    'there',
    'they',
    'them',
    'some',
    'any',
    'all',
    'our',
    'your',
    'its',
    'not',
    'but',
    'than',
    'then',
    'also',
    'just',
    'like',
    'get',
    'got',
    'did',
    'done',
    'doing',
    'make',
    'makes',
    'need',
    'want',
    'know',
    'show',
    'shows',
    'help',
    'really',
    'very',
    'much',
    'many',
    'more',
    'most',
    'god',
    'lord',
    'jesus',
    'christ',
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

  bool _hasFullLexicon = false;

  /// True once the optional full lexicon pack is attached.
  bool get hasFullLexicon => _hasFullLexicon;

  /// Attaches the optional LSJ pack built by `bin/build_lexicon_pack.dart`. Returns false when
  /// the file is missing or not a pack.
  bool attachFullLexicon(String path) {
    if (_hasFullLexicon || !File(path).existsSync()) return _hasFullLexicon;
    try {
      db.execute('ATTACH DATABASE ? AS lsj', [path]);
      db.select('SELECT key, base, definition FROM lsj.lexicon_full LIMIT 1');
      _hasFullLexicon = true;
    } on SqliteException {
      try {
        db.execute('DETACH DATABASE lsj');
      } on SqliteException {
        // Never attached; nothing to undo.
      }
    }
    return _hasFullLexicon;
  }

  /// Detaches the pack so its file can be replaced.
  void detachFullLexicon() {
    if (!_hasFullLexicon) return;
    db.execute('DETACH DATABASE lsj');
    _hasFullLexicon = false;
  }

  /// The full LSJ entry for a Greek Strong's number, when the pack is attached.
  String? fullLexicon(String strongs) {
    if (!_hasFullLexicon) return null;
    final base = strongs.replaceAll(RegExp(r'[A-Za-z]$'), '');
    try {
      final rows = db.select(
        'SELECT definition FROM lsj.lexicon_full WHERE key = ? OR base = ? '
        'ORDER BY (key = ?) DESC LIMIT 1',
        [strongs, base, strongs],
      );
      return rows.isEmpty ? null : rows.first['definition'] as String?;
    } on SqliteException {
      return null;
    }
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

  /// Verses that several of [sources] cross-reference, ranked by how many point to them and
  /// then by votes. Sources themselves are excluded.
  List<Ref> crossReferenceHubs(List<Ref> sources, {int k = 8}) {
    if (sources.isEmpty) return const [];
    final where = List.filled(
      sources.length,
      '(from_book = ? AND from_chapter = ? AND from_verse = ?)',
    ).join(' OR ');
    final rows = db.select(
      "SELECT to_book, to_chapter, to_verse_start, "
      "COUNT(DISTINCT from_book || ':' || from_chapter || ':' || from_verse) AS n, "
      'SUM(votes) AS v FROM xrefs '
      'WHERE ($where) AND votes > 0 GROUP BY to_book, to_chapter, to_verse_start '
      'ORDER BY n DESC, v DESC LIMIT ?',
      [
        for (final r in sources) ...[r.book.id, r.chapter, r.verseStart ?? 1],
        k + sources.length,
      ],
    );
    final from = {for (final r in sources) '${r.book.id}:${r.chapter}:${r.verseStart}'};
    return [
      for (final r in rows)
        if (!from.contains('${r['to_book']}:${r['to_chapter']}:${r['to_verse_start']}'))
          Ref(
            bookById(r['to_book'] as int),
            r['to_chapter'] as int,
            r['to_verse_start'] as int,
            r['to_verse_start'] as int,
          ),
    ].take(k).toList();
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
