import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'books.dart';
import 'importers.dart';
import 'ref_parser.dart';
import 'word_study.dart';

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

  /// Place in the verse in the original language's word order, from 1; 0 when not known.
  final int pos;
  const WordTag(this.original, this.translit, this.gloss, this.strongs, this.morph, {this.pos = 0});
}

/// One verse where a word is used, with the word as it appears there (more than once in some).
class WordUse {
  final Ref ref;

  /// The verse in the reader's translation, or null when that translation numbers it differently.
  final String? text;
  final List<WordTag> words;
  const WordUse(this.ref, this.text, this.words);
}

/// A word that some verses gloss with a given English word.
class GlossedWord {
  final String code;
  final LexEntry? entry;

  /// Times STEP glosses it with the English word, and times it is used at all.
  final int glossed;
  final int uses;
  const GlossedWord(this.code, this.entry, this.glossed, this.uses);
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
      'SELECT original, translit, gloss, strongs, morph, pos FROM words '
      'WHERE book = ? AND chapter = ? AND verse BETWEEN ? AND ? ORDER BY verse, pos',
      [ref.book.id, ref.chapter, vs, ve],
    );
    return rows.map(_wordTag).toList();
  }

  static WordTag _wordTag(Row r) => WordTag(
    r['original'] as String,
    r['translit'] as String,
    r['gloss'] as String,
    r['strongs'] as String,
    r['morph'] as String,
    pos: r['pos'] as int,
  );

  bool? _hasWordIndex;

  /// Builds the word concordance from `words`: `word_index` finds every use of a base Strong's
  /// number, and `gloss_index` finds the words STEP glosses with an English stem. build_db.dart
  /// calls this; a database without the tables gets them the first time a word is studied.
  void buildWordIndex() {
    final glossed = <String, int>{};
    db.execute('BEGIN');
    try {
      db.execute('''
        DROP TABLE IF EXISTS word_index;
        DROP TABLE IF EXISTS gloss_index;
        CREATE TABLE word_index(strongs TEXT, book INTEGER, chapter INTEGER, verse INTEGER,
          pos INTEGER, PRIMARY KEY(strongs, book, chapter, verse, pos)) WITHOUT ROWID;
        CREATE TABLE gloss_index(term TEXT, strongs TEXT, n INTEGER,
          PRIMARY KEY(term, strongs)) WITHOUT ROWID;
      ''');
      final read = db.prepare('SELECT book, chapter, verse, pos, gloss, strongs FROM words');
      final insert = db.prepare('INSERT OR IGNORE INTO word_index VALUES (?, ?, ?, ?, ?)');
      try {
        final cursor = read.selectCursor();
        while (cursor.moveNext()) {
          final r = cursor.current;
          final codes = (r['strongs'] as String).split(' ').where((c) => c.isNotEmpty).toList();
          if (codes.isEmpty) continue;
          // A word with a prefix ("and/ upright") is filed under the word, not the "and".
          var words = codes.where((c) => !isParticleCode(c)).map(strongsBase).toSet();
          if (words.isEmpty) words = {strongsBase(codes.first)};
          for (final code in words) {
            insert.execute([code, r['book'], r['chapter'], r['verse'], r['pos']]);
          }
          for (final term in glossStems(r['gloss'] as String)) {
            final key = '$term\t${words.first}';
            glossed[key] = (glossed[key] ?? 0) + 1;
          }
        }
      } finally {
        read.dispose();
        insert.dispose();
      }
      final put = db.prepare('INSERT INTO gloss_index VALUES (?, ?, ?)');
      try {
        for (final e in glossed.entries) {
          final tab = e.key.indexOf('\t');
          put.execute([e.key.substring(0, tab), e.key.substring(tab + 1), e.value]);
        }
      } finally {
        put.dispose();
      }
      db.execute('COMMIT');
      _hasWordIndex = true;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _ensureWordIndex() {
    _hasWordIndex ??= db
        .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'gloss_index'")
        .isNotEmpty;
    if (!_hasWordIndex!) buildWordIndex();
  }

  /// How often the word with base Strong's number [code] is used, and in how many verses.
  ({int uses, int verses}) wordCount(String code) {
    _ensureWordIndex();
    final r = db.select(
      "SELECT COUNT(*) AS n, COUNT(DISTINCT book || ':' || chapter || ':' || verse) AS v "
      'FROM word_index WHERE strongs = ?',
      [strongsBase(code)],
    ).first;
    return (uses: r['n'] as int, verses: r['v'] as int);
  }

  /// Uses of [code] per book, in canonical order.
  List<(Book, int)> wordBooks(String code) {
    _ensureWordIndex();
    return [
      for (final r in db.select(
        'SELECT book, COUNT(*) AS n FROM word_index WHERE strongs = ? GROUP BY book ORDER BY book',
        [strongsBase(code)],
      ))
        (bookById(r['book'] as int), r['n'] as int),
    ];
  }

  /// How STEP glosses [code] across its uses, most common first, as [cleanGloss] words.
  List<(String, int)> wordGlosses(String code) {
    _ensureWordIndex();
    final counts = <String, int>{};
    for (final r in db.select(
      'SELECT w.gloss, w.strongs FROM word_index i JOIN words w ON w.book = i.book AND '
      'w.chapter = i.chapter AND w.verse = i.verse AND w.pos = i.pos WHERE i.strongs = ?',
      [strongsBase(code)],
    )) {
      final g = cleanGloss(r['gloss'] as String, strongs: r['strongs'] as String);
      if (g.isNotEmpty) counts[g] = (counts[g] ?? 0) + 1;
    }
    return [for (final e in counts.entries) (e.key, e.value)]
      ..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  }

  /// The verses that use [code], in canonical order, a page at a time. With [book], only that
  /// book. Each holds the verse in [translation] and the word as it appears there.
  List<WordUse> wordUses(
    String code, {
    String translation = defaultTranslation,
    Book? book,
    int limit = 30,
    int offset = 0,
  }) {
    _ensureWordIndex();
    final base = strongsBase(code);
    final rows = db.select(
      'WITH vs AS (SELECT DISTINCT book, chapter, verse FROM word_index '
      'WHERE strongs = ? AND (? IS NULL OR book = ?) ORDER BY book, chapter, verse LIMIT ? OFFSET ?) '
      'SELECT vs.book, vs.chapter, vs.verse, w.original, w.translit, w.gloss, w.strongs, w.morph, '
      'w.pos FROM vs JOIN word_index i ON i.strongs = ? AND i.book = vs.book AND '
      'i.chapter = vs.chapter AND i.verse = vs.verse JOIN words w ON w.book = i.book AND '
      'w.chapter = i.chapter AND w.verse = i.verse AND w.pos = i.pos '
      'ORDER BY vs.book, vs.chapter, vs.verse, w.pos',
      [base, book?.id, book?.id, limit, offset, base],
    );
    final uses = <WordUse>[];
    for (final r in rows) {
      final ref = Ref(
        bookById(r['book'] as int),
        r['chapter'] as int,
        r['verse'] as int,
        r['verse'] as int,
      );
      if (uses.isEmpty || uses.last.ref != ref) {
        uses.add(WordUse(ref, passage(ref, translation: translation).firstOrNull?.text, []));
      }
      uses.last.words.add(_wordTag(r));
    }
    return uses;
  }

  /// Up to [k] verses that use [code], spread across the Bible rather than the first few, leaving
  /// out [exclude]. For putting a word's range of use in front of the model.
  List<Verse> wordSample(
    String code, {
    int k = 6,
    Ref? exclude,
    String translation = defaultTranslation,
  }) {
    _ensureWordIndex();
    final refs = [
      for (final r in db.select(
        'SELECT DISTINCT book, chapter, verse FROM word_index WHERE strongs = ? '
        'ORDER BY book, chapter, verse',
        [strongsBase(code)],
      ))
        Ref(bookById(r['book'] as int), r['chapter'] as int, r['verse'] as int, r['verse'] as int),
    ]..removeWhere((r) => exclude != null && r.overlaps(exclude));
    if (k <= 0 || refs.isEmpty) return const [];
    final picks = refs.length <= k
        ? refs
        : [for (var i = 0; i < k; i++) refs[(i * refs.length) ~/ k]];
    return [for (final r in picks) ...passage(r, translation: translation)];
  }

  /// Hebrew and Greek words STEP glosses with [english] (by [wordStem]), most often first.
  List<GlossedWord> wordsGlossed(String english, {int k = 8}) {
    _ensureWordIndex();
    final rows = db.select(
      'SELECT strongs, n FROM gloss_index WHERE term = ? ORDER BY n DESC, strongs LIMIT ?',
      [wordStem(english), k],
    );
    return [
      for (final r in rows)
        GlossedWord(
          r['strongs'] as String,
          lexicon(r['strongs'] as String),
          r['n'] as int,
          wordCount(r['strongs'] as String).uses,
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
