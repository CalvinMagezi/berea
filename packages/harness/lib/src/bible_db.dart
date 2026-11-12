import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'books.dart';
import 'bsb_marks.dart';
import 'importers.dart';
import 'ref_parser.dart';
import 'search_text.dart';
import 'sword.dart';
import 'word_study.dart';

class Verse {
  final Book book;
  final int chapter;
  final int verse;
  final String text;
  const Verse(this.book, this.chapter, this.verse, this.text);
  String get label => '${book.name} $chapter:$verse';
}

/// One labelled run of search hits, in Bible order. [total] counts them all; [verses] holds at
/// most the first few.
class SearchGroup {
  final String label;
  final List<Verse> verses;
  final int total;
  const SearchGroup(this.label, this.verses, this.total);
}

/// A word the search could not find, with every word of the translation one letter away from it.
class Spelling {
  final String word;
  final List<(String, int)> near;
  const Spelling(this.word, this.near);
}

/// What the search box shows: the groups, or, when there are none, a spelling line.
class SearchResult {
  final List<SearchGroup> groups;
  final Spelling? spelling;
  const SearchResult(this.groups, this.spelling);
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

  /// The work the definition comes from: AS (Abbott-Smith), ML (Middle Liddell, kept out of the
  /// bundled database), OB (Online Bible's abridged Brown-Driver-Briggs), or empty when STEPBible
  /// names none. Empty too for a database built before sources were recorded.
  final String source;
  const LexEntry(
    this.key,
    this.lemma,
    this.translit,
    this.pos,
    this.gloss,
    this.definition, [
    this.source = '',
  ]);
}

class XRef {
  final Ref to;
  final int votes;
  const XRef(this.to, this.votes);
}

/// How a Hebrew or Greek word came to be listed for a search.
enum WordMatchKind {
  /// The search was the word's Strong's number, such as G40.
  number,

  /// The search was the word's spelling in English letters ("hagios") or its own script.
  original,

  /// STEPBible's tagging glosses the word with an English word of the search.
  glossed,

  /// The lexicon's own gloss for the word holds an English word of the search.
  defined,
}

/// A Hebrew or Greek word a search found, and why. Opens as a word study by its [code].
class WordMatch {
  final LexEntry entry;

  /// The base Strong's number, such as H6918.
  final String code;
  final WordMatchKind kind;

  /// The English word of the search that found it; empty for a number or a spelling.
  final String term;

  /// Times STEPBible's tagging glosses the word with [term]; 0 unless [kind] is
  /// [WordMatchKind.glossed].
  final int glossed;

  /// Times and verses the word is used in the Bible.
  final int uses;
  final int verses;
  const WordMatch({
    required this.entry,
    required this.code,
    required this.kind,
    required this.term,
    required this.glossed,
    required this.uses,
    required this.verses,
  });

  String get language => entry.pos.startsWith('A:') ? 'Aramaic' : languageOf(code);
}

/// A heading printed before [verse]; see [HeadingRow] for the kinds.
/// How many verses before an empty one the publisher's footnote that prints it may sit.
const _emptyVerseReach = 3;

class Heading {
  final int verse;
  final String kind;
  final String text;
  final String refs;
  const Heading(this.verse, this.kind, this.text, this.refs);

  /// Lower is broader: a division, then a section, a subsection, an acrostic stanza.
  int get rank => _headingRanks.contains(kind) ? _headingRanks.indexOf(kind) : _headingRanks.length;
}

const _headingRanks = ['ms', 's1', 's2', 'qa'];

/// The verses [heading] covers in a chapter whose last verse is [last]: up to the next heading
/// of the same or a broader rank, or the end of the chapter.
({int start, int end}) sectionSpan(List<Heading> headings, Heading heading, int last) {
  final next = [
    for (final h in headings)
      if (h.verse > heading.verse && h.rank <= heading.rank) h.verse,
  ];
  return (
    start: heading.verse,
    end: next.isEmpty ? last : next.reduce((a, b) => a < b ? a : b) - 1,
  );
}

/// How a word came to be a candidate for the word search, best first.
enum _WordTier {
  glossed(WordMatchKind.glossed),
  defined(WordMatchKind.defined),
  spelled(WordMatchKind.original);

  final WordMatchKind kind;
  const _WordTier(this.kind);
}

/// A word the search is considering, with everything that tied it to the query.
class _WordCandidate {
  final String code;
  _WordTier? _tier;
  final terms = <String>{};

  /// The most times any of the query's words is the gloss STEPBible gives this word.
  var glossed = 0;
  _WordCandidate(this.code);

  _WordTier get tier => _tier!;

  void add(_WordTier tier, String term, {int glossed = 0}) {
    if (_tier == null || tier.index < _tier!.index) _tier = tier;
    if (term.isNotEmpty) terms.add(term);
    if (glossed > this.glossed) this.glossed = glossed;
  }
}

const defaultTranslation = 'BSB';

/// Translation codes are short uppercase identifiers; they also name files on disk.
const translationCodeMax = 8;
final translationCode = RegExp('^[A-Z0-9]{1,$translationCodeMax}\$');
const maxPassageVerses = 40;

/// A verse with fewer of the query's words than this is not listed as a partial match.
const minPartialWords = 2;

/// SQLite reads a negative LIMIT as no limit.
const _noLimit = -1;

/// The initial schema for the Bible database: verses, search, words, lexicon, xrefs and meta.
void createBibleSchema(Database db) => db.execute('''
  PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;
  CREATE TABLE verses(id INTEGER PRIMARY KEY, translation TEXT, book INTEGER, chapter INTEGER, verse INTEGER, text TEXT);
  CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id', tokenize='porter unicode61');
  CREATE TABLE words(book INTEGER, chapter INTEGER, verse INTEGER, pos INTEGER, original TEXT, translit TEXT, gloss TEXT, strongs TEXT, morph TEXT, PRIMARY KEY(book, chapter, verse, pos)) WITHOUT ROWID;
  CREATE TABLE lexicon(key TEXT PRIMARY KEY, base TEXT, lemma TEXT, translit TEXT, pos TEXT, gloss TEXT, definition TEXT);
  CREATE INDEX lexicon_base ON lexicon(base);
  CREATE TABLE xrefs(from_book INTEGER, from_chapter INTEGER, from_verse INTEGER, to_book INTEGER, to_chapter INTEGER, to_verse_start INTEGER, to_verse_end INTEGER, votes INTEGER);
  CREATE INDEX xrefs_from ON xrefs(from_book, from_chapter, from_verse);
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
  CREATE INDEX verses_ref ON verses(translation, book, chapter, verse);
''');

/// Inserts verse rows into verses under code.
void loadVerseRows(Database db, String code, Iterable<VerseRow> rows) {
  final stmt = db.prepare(
    'INSERT INTO verses(translation, book, chapter, verse, text) VALUES (?, ?, ?, ?, ?)',
  );
  db.execute('BEGIN');
  for (final r in rows) {
    stmt.execute([code, r.book.id, r.chapter, r.verse, r.text]);
  }
  db.execute('COMMIT');
  stmt.dispose();
}

/// Rebuilds the search index from the current verses table.
void rebuildVersesFts(Database db) =>
    db.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')");

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

  /// When this database was built, from its meta table; empty for one without it.
  late final String built = () {
    try {
      return db.select("SELECT value FROM meta WHERE key = 'built'").firstOrNull?['value']
              as String? ??
          '';
    } on SqliteException {
      return '';
    }
  }();

  /// Every verse of a chapter, for reading. [passage] caps its length instead.
  List<Verse> chapter(Book book, int chapter, {String translation = defaultTranslation}) => db
      .select(
        'SELECT book, chapter, verse, text FROM verses '
        'WHERE translation = ? AND book = ? AND chapter = ? ORDER BY verse',
        [translation, book.id, chapter],
      )
      .map(_verse)
      .toList();

  /// At most [maxPassageVerses] verses, so a whole chapter named in a question cannot crowd out
  /// the rest of an answer.
  List<Verse> passage(Ref ref, {String translation = defaultTranslation}) =>
      _range(ref, translation, maxPassageVerses);

  /// Every verse of [ref], for reading or keeping; [passage] caps its length.
  List<Verse> verses(Ref ref, {String translation = defaultTranslation}) =>
      _range(ref, translation, _noLimit);

  List<Verse> _range(Ref ref, String translation, int limit) {
    final vs = ref.verseStart ?? 1;
    final ve = ref.verseStart == null ? 999 : (ref.verseEnd ?? vs);
    final rows = db.select(
      'SELECT book, chapter, verse, text FROM verses '
      'WHERE translation = ? AND book = ? AND chapter = ? AND verse BETWEEN ? AND ? '
      'ORDER BY verse LIMIT ?',
      [translation, ref.book.id, ref.chapter, vs, ve, limit],
    );
    return rows.map(_verse).toList();
  }

  /// The headings of one chapter in printed order. Empty for a translation without headings and
  /// for databases built before headings existed.
  List<Heading> headings(Book book, int chapter, {String translation = defaultTranslation}) {
    if (!_hasHeadings) return const [];
    final rows = db.select(
      'SELECT verse, kind, text, refs FROM headings '
      'WHERE translation = ? AND book = ? AND chapter = ? ORDER BY verse, ord',
      [translation, book.id, chapter],
    );
    return [
      for (final r in rows)
        Heading(r['verse'] as int, r['kind'] as String, r['text'] as String, r['refs'] as String),
    ];
  }

  // Read on every reader build, so the table check runs once; importHeadings sets it.
  late bool _hasHeadings = db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'headings'")
      .isNotEmpty;

  /// Stores [rows] as the headings of translation [code], replacing any it had. Returns how many
  /// anchor to a verse the translation does not have, which a builder should report.
  int importHeadings(List<HeadingRow> rows, String code) {
    db.execute(
      'CREATE TABLE IF NOT EXISTS headings(translation TEXT, book INTEGER, chapter INTEGER, '
      'verse INTEGER, ord INTEGER, kind TEXT, text TEXT, refs TEXT, '
      'PRIMARY KEY(translation, book, chapter, verse, ord)) WITHOUT ROWID',
    );
    final insert = db.prepare('INSERT INTO headings VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    final known = db.prepare(
      'SELECT 1 FROM verses WHERE translation = ? AND book = ? AND chapter = ? AND verse = ?',
    );
    var stray = 0;
    final ords = <String, int>{};
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM headings WHERE translation = ?', [code]);
      for (final r in rows) {
        final key = '${r.book.id}:${r.chapter}:${r.verse}';
        final ord = ords[key] = (ords[key] ?? -1) + 1;
        insert.execute([code, r.book.id, r.chapter, r.verse, ord, r.kind, r.text, r.refs]);
        if (known.select([code, r.book.id, r.chapter, r.verse]).isEmpty) stray++;
      }
      db.execute('COMMIT');
      _hasHeadings = true;
      return stray;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      insert.dispose();
      known.dispose();
    }
  }

  late bool _hasMarks = db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'marks'")
      .isNotEmpty;

  /// Stores the publisher's marks and footnotes of translation [code], replacing any it had. Only
  /// verses the two source files agree on are in [result]; the others get no marks at all.
  void importMarks(MarksResult result, String code) {
    db.execute(
      'CREATE TABLE IF NOT EXISTS marks(translation TEXT, book INTEGER, chapter INTEGER, '
      'verse INTEGER, kind TEXT, start INTEGER, "end" INTEGER)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS footnotes(translation TEXT, book INTEGER, chapter INTEGER, '
      'verse INTEGER, ord INTEGER, at INTEGER, text TEXT, '
      'PRIMARY KEY(translation, book, chapter, verse, ord)) WITHOUT ROWID',
    );
    final mark = db.prepare('INSERT INTO marks VALUES (?, ?, ?, ?, ?, ?, ?)');
    final note = db.prepare('INSERT INTO footnotes VALUES (?, ?, ?, ?, ?, ?, ?)');
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM marks WHERE translation = ?', [code]);
      db.execute('DELETE FROM footnotes WHERE translation = ?', [code]);
      for (final v in result.verses) {
        final r = v.ref;
        for (final s in v.spans) {
          mark.execute([code, r.book.id, r.chapter, r.verseStart, s.kind.name, s.start, s.end]);
        }
        for (var i = 0; i < v.footnotes.length; i++) {
          final n = v.footnotes[i];
          note.execute([code, r.book.id, r.chapter, r.verseStart, i, n.at, n.text]);
        }
      }
      db.execute('CREATE INDEX IF NOT EXISTS marks_verse ON marks(translation, book, chapter, verse)');
      db.execute('COMMIT');
      _hasMarks = true;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      mark.dispose();
      note.dispose();
    }
  }

  /// The footnotes the publisher prints on one verse, in the order of their words.
  List<BsbFootnote> footnotes(int book, int chapter, int verse, {String translation = defaultTranslation}) {
    if (!_hasMarks) return const [];
    return [
      for (final r in db.select(
        'SELECT at, text FROM footnotes WHERE translation = ? AND book = ? AND chapter = ? AND verse = ? ORDER BY ord',
        [translation, book, chapter, verse],
      ))
        (at: r['at'] as int, text: r['text'] as String),
    ];
  }

  /// For a verse the translation leaves empty (the BSB leaves sixteen), the footnote on a verse
  /// just before it that prints the verse, and which verse that is. Null for a verse with text,
  /// and for an empty verse no footnote names.
  ({int host, String text})? emptyVerseNote(
    int book,
    int chapter,
    int verse, {
    String translation = defaultTranslation,
  }) {
    if (!_hasMarks) return null;
    final own = db.select(
      'SELECT text FROM verses WHERE translation = ? AND book = ? AND chapter = ? AND verse = ?',
      [translation, book, chapter, verse],
    );
    if (own.isEmpty || (own.first['text'] as String).trim().isNotEmpty) return null;
    for (var host = verse - 1; host >= verse - _emptyVerseReach && host > 0; host--) {
      for (final n in footnotes(book, chapter, host, translation: translation)) {
        if (RegExp('(?<!\\d)$verse(?!\\d)').hasMatch(n.text)) return (host: host, text: n.text);
      }
    }
    return null;
  }

  /// The passages the publisher prints under the heading that covers [verse], as the heading
  /// gives them ("Genesis 22:1–10; Romans 5:6–11"); empty when that heading has none. A later
  /// heading without any ends the earlier one's reach.
  String parallelPassages(Book book, int chapter, int verse, {String translation = defaultTranslation}) {
    Heading? covering;
    for (final h in headings(book, chapter, translation: translation)) {
      if (h.verse <= verse) covering = h;
    }
    return covering?.refs ?? '';
  }

  /// The publisher's marks and footnotes for each verse of a chapter that has any, keyed by verse
  /// number. Empty for a translation or a database without them.
  Map<int, VerseMarkSet> marksForChapter(int book, int chapter, {String translation = defaultTranslation}) {
    if (!_hasMarks) return const {};
    final spans = <int, List<MarkSpan>>{};
    for (final r in db.select(
      'SELECT verse, kind, start, "end" FROM marks WHERE translation = ? AND book = ? AND chapter = ? ORDER BY verse, start',
      [translation, book, chapter],
    )) {
      (spans[r['verse'] as int] ??= []).add((
        kind: MarkKind.values.byName(r['kind'] as String),
        start: r['start'] as int,
        end: r['end'] as int,
      ));
    }
    final notes = <int, List<BsbFootnote>>{};
    for (final r in db.select(
      'SELECT verse, at, text FROM footnotes WHERE translation = ? AND book = ? AND chapter = ? ORDER BY verse, ord',
      [translation, book, chapter],
    )) {
      (notes[r['verse'] as int] ??= []).add((at: r['at'] as int, text: r['text'] as String));
    }
    return {
      for (final v in {...spans.keys, ...notes.keys})
        v: VerseMarkSet(spans[v] ?? const [], notes[v] ?? const []),
    };
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
  /// A gloss used this rarely for a word is too thin to tie two English words together.
  static const _minFormUses = 2;
  static const _formTail = 2;
  static const _minFormRoot = 3;

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
    return {
      for (final t in terms) ...{t, ...wordForms(t)},
    }.map((t) => '"$t"').join(' OR ');
  }

  /// Other English forms of [word] ("anger" for "angry", "hunger" for "hungry"): words STEP
  /// glosses the same Hebrew or Greek word with that differ only in their last letters. The
  /// search's porter stemmer keeps "angri" and "anger" apart, so "Is it wrong to be angry?"
  /// missed Ephesians 4:26.
  List<String> wordForms(String word) {
    if (!_hasGlossIndex) return const [];
    final stem = wordStem(word);
    final root = stem.length - _formTail;
    if (root < _minFormRoot) return const [];
    // A range on the term key, so the lookup uses the table's index; a join on strongs would scan.
    final prefix = stem.substring(0, root);
    final rows = db.select(
      'SELECT term, strongs FROM gloss_index WHERE term >= ? AND term < ? AND n >= ?',
      [prefix, '$prefix\u{FFFF}', _minFormUses],
    );
    final own = {
      for (final r in rows)
        if (r['term'] == stem) r['strongs'] as String,
    };
    return {
      for (final r in rows)
        if (r['term'] != stem && own.contains(r['strongs']) && _sameWord(stem, r['term'] as String))
          r['term'] as String,
    }.toList();
  }

  /// Two stems are one word's forms when their lengths differ by at most one letter and they
  /// share all but the shorter one's last [_formTail] letters; "fear" and "fearless" are not.
  static bool _sameWord(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    final keep = min(a.length, b.length) - _formTail;
    return keep >= _minFormRoot && a.substring(0, keep) == b.substring(0, keep);
  }

  late final bool _hasGlossIndex = db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'gloss_index'")
      .isNotEmpty;

  List<Verse> search(
    String text, {
    String translation = defaultTranslation,
    int k = 6,
    Book? book,
  }) {
    final q = ftsQuery(text);
    if (q == null) return const [];
    final rows = db.select(
      'SELECT v.book, v.chapter, v.verse, v.text FROM verses_fts f '
      'JOIN verses v ON v.id = f.rowid '
      'WHERE verses_fts MATCH ? AND v.translation = ? ${book == null ? '' : 'AND v.book = ? '}'
      'ORDER BY bm25(verses_fts) LIMIT ?',
      [q, translation, if (book != null) book.id, k],
    );
    return rows.map(_verse).toList();
  }

  /// What the search box shows: groups that each say how their verses were found, every group
  /// in Bible order so no ranking is hidden. "Exact words" are confirmed against the verse text,
  /// because the index matches stems. Everything else is counted from the index's row ids, so no
  /// verse text is read for a verse that is not listed. [perGroup] caps how many a group lists.
  List<SearchGroup> searchVerses(
    String text, {
    String translation = defaultTranslation,
    int perGroup = 100,
  }) {
    final tokens = searchTokens(text);
    if (tokens.isEmpty || searchIsTooCommon(text)) return const [];
    return [
      ..._verseGroups(tokens, translation, perGroup),
      ..._headingGroup(tokens, translation, perGroup),
    ];
  }

  /// The headings the translation's publisher printed that hold every word searched for, listed
  /// last and at the verse each one stands above. They are the publisher's, not Bible text.
  List<SearchGroup> _headingGroup(List<String> tokens, String translation, int perGroup) {
    if (!_hasHeadings) return const [];
    final found = <Verse>[];
    for (final r in db.select(
      'SELECT book, chapter, verse, text FROM headings WHERE translation = ?',
      [translation],
    )) {
      final words = searchTokens(r['text'] as String).toSet();
      if (tokens.every(words.contains)) found.add(_verse(r));
    }
    if (found.isEmpty) return const [];
    final label = 'Section headings, printed by the $translation publisher';
    return [SearchGroup(label, found.take(perGroup).toList(), found.length)];
  }

  List<SearchGroup> _verseGroups(List<String> tokens, String translation, int perGroup) {
    final groups = <SearchGroup>[];
    final taken = <int>{};
    void add(String label, Iterable<int> ids) {
      final fresh = [
        for (final id in ids)
          if (taken.add(id)) id,
      ];
      if (fresh.isEmpty) return;
      groups.add(SearchGroup(label, _versesById(fresh.take(perGroup)), fresh.length));
    }

    final phraseQuery = '"${tokens.join(' ')}"';
    final phrase = phrasePattern(tokens);
    add('Exact words', _exactIds(phraseQuery, phrase, translation));
    if (groups.isEmpty) {
      for (final other in bundledTranslations().where((t) => t != translation)) {
        final ids = _exactIds(phraseQuery, phrase, other);
        if (ids.isEmpty) continue;
        add('Exact words in $other', ids);
        break;
      }
    }

    final content = {
      for (final t in tokens)
        if (!searchStopWords.contains(t)) t,
    }.toList();
    if (content.isEmpty) return groups;
    if (content.length == 1) {
      final word = content.first;
      add(
        tokens.length == 1 ? 'Other forms of the word' : 'Has "$word", without the other words',
        _matchIds('"$word"', translation),
      );
      if (tokens.length == 1) groups.addAll(_glossedGroups(word, translation));
      return groups;
    }
    final perTerm = [for (final t in content) _matchIds('"$t"', translation).toSet()];
    final counts = <int, int>{};
    for (final ids in perTerm) {
      for (final id in ids) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    // Every id is in some term's set, so ordering the union by Bible order orders all groups.
    final inOrder = _matchIds(content.map((t) => '"$t"').join(' OR '), translation);
    for (var n = content.length; n >= minPartialWords; n--) {
      add(
        n == content.length ? 'All your words' : '$n of ${content.length} words',
        inOrder.where((id) => counts[id] == n),
      );
    }
    return groups;
  }

  /// The search with its spelling line: when nothing is found, the first word that no verse of the
  /// translation has, and every word one letter away from it that some verse does have.
  SearchResult searchResult(
    String text, {
    String translation = defaultTranslation,
    int perGroup = 100,
  }) {
    final groups = searchVerses(text, translation: translation, perGroup: perGroup);
    if (groups.isNotEmpty || searchIsTooCommon(text)) return SearchResult(groups, null);
    return SearchResult(groups, _spelling(searchTokens(text), translation));
  }

  /// Notes every word of each translation with the number of verses that hold it, for the
  /// spelling line. A builder calls this once the verses are loaded.
  void buildVocabulary() {
    final counts = <String, Map<String, int>>{};
    final rows = db.select('SELECT translation, text FROM verses');
    for (final r in rows) {
      final byWord = counts.putIfAbsent(r['translation'] as String, () => {});
      for (final w in searchTokens(r['text'] as String).toSet()) {
        byWord[w] = (byWord[w] ?? 0) + 1;
      }
    }
    db.execute('DROP TABLE IF EXISTS vocab');
    db.execute(
      'CREATE TABLE vocab(translation TEXT, word TEXT, verses INTEGER, '
      'PRIMARY KEY(translation, word)) WITHOUT ROWID',
    );
    final insert = db.prepare('INSERT INTO vocab VALUES (?, ?, ?)');
    db.execute('BEGIN');
    for (final t in counts.entries) {
      for (final w in t.value.entries) {
        insert.execute([t.key, w.key, w.value]);
      }
    }
    db.execute('COMMIT');
    insert.dispose();
  }

  late final bool _hasVocab = db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'vocab'")
      .isNotEmpty;

  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz';
  static final _plainWord = RegExp(r'^[a-z]{3,40}$');

  Spelling? _spelling(List<String> tokens, String translation) {
    if (!_hasVocab) return null;
    final known = db.prepare('SELECT 1 FROM vocab WHERE translation = ? AND word = ?');
    try {
      for (final word in tokens) {
        if (!_plainWord.hasMatch(word) || known.select([translation, word]).isNotEmpty) continue;
        final near = _oneLetterAway(word, translation);
        if (near.isNotEmpty) return Spelling(word, near);
      }
    } finally {
      known.dispose();
    }
    return null;
  }

  List<(String, int)> _oneLetterAway(String word, String translation) {
    final edits = <String>{};
    for (var i = 0; i <= word.length; i++) {
      final head = word.substring(0, i), tail = word.substring(i);
      if (tail.isNotEmpty) edits.add(head + tail.substring(1));
      if (tail.length > 1) edits.add(head + tail[1] + tail[0] + tail.substring(2));
      for (final c in _alphabet.split('')) {
        if (tail.isNotEmpty) edits.add(head + c + tail.substring(1));
        edits.add(head + c + tail);
      }
    }
    edits.remove(word);
    final list = edits.toList();
    final rows = db.select(
      'SELECT word, verses FROM vocab WHERE translation = ? AND word IN '
      '(${List.filled(list.length, '?').join(',')}) ORDER BY verses DESC, word',
      [translation, ...list],
    );
    return [for (final r in rows) (r['word'] as String, r['verses'] as int)];
  }

  static const _glossedVersesShown = 5;

  /// One group for every Hebrew or Greek word STEPBible's tagging glosses with [word], most
  /// often first, each listing the verses that use it. None is picked over another.
  List<SearchGroup> _glossedGroups(String word, String translation) {
    if (!_hasGlossIndex || !RegExp(r'^[a-z]+$').hasMatch(word)) return const [];
    // "thee" stems to "the", which STEPBible's tagging glosses on thousands of unrelated words.
    final stem = wordStem(word);
    if (searchStopWords.contains(stem)) return const [];
    final tagged = db.select(
      'SELECT strongs, n FROM gloss_index WHERE term = ? AND n >= ? ORDER BY n DESC, strongs',
      [stem, _minFormUses],
    );
    final lookup = db.prepare(
      'SELECT text FROM verses WHERE translation = ? AND book = ? AND chapter = ? AND verse = ?',
    );
    try {
      return [
        for (final t in tagged)
          ?_glossedGroup(t['strongs'] as String, t['n'] as int, word, translation, lookup),
      ];
    } finally {
      lookup.dispose();
    }
  }

  SearchGroup? _glossedGroup(
    String code,
    int times,
    String word,
    String translation,
    PreparedStatement lookup,
  ) {
    final refs = db.select(
      'SELECT book, chapter, verse FROM word_index WHERE strongs = ? '
      'GROUP BY book, chapter, verse',
      [strongsBase(code)],
    );
    // A translation the reader imported may lack books; list and count only verses it has.
    final present = _orderedRanges.containsKey(translation)
        ? refs.toList()
        : [
            for (final r in refs)
              if (lookup.select([translation, r['book'], r['chapter'], r['verse']]).isNotEmpty) r,
          ];
    if (present.isEmpty) return null;
    final verses = <Verse>[];
    for (final r in present.take(_glossedVersesShown)) {
      final text = lookup.select([translation, r['book'], r['chapter'], r['verse']]);
      if (text.isNotEmpty) {
        verses.add(Verse(bookById(r['book'] as int), r['chapter'] as int, r['verse'] as int,
            text.first['text'] as String));
      }
    }
    final lemma = lexicon(code)?.lemma;
    final name = lemma == null ? code : '$lemma ($code)';
    final label = 'Verses with $name, which STEPBible\'s tagging glosses "$word" $times times';
    return SearchGroup(label, verses, present.length);
  }

  static final _strongsOnly = RegExp(r'^[HG]\d{1,4}[A-Z]?$');
  static final _englishWord = RegExp(r'^[a-z]+$');
  static final _spelledLetters = RegExp(r"^[A-Za-z.'\-·]+$");

  /// Most words the lexicon scan and the gloss index may bring forward before ranking.
  static const _wordCandidates = 300;

  /// The shortest spelling that is searched by its first letters, so "ha" does not list every
  /// word that starts with it, and the shortest that is searched at all.
  static const _minSpellingPrefix = 4;
  static const _minSpellingWord = 3;

  /// The Hebrew and Greek words behind a search, for the search box's "Word studies" section.
  /// None is picked over another, and each says why it is listed:
  ///
  /// 1. A Strong's number ("G40") lists that word alone.
  /// 2. STEPBible's tagging glosses the word with an English word of the search, most often
  ///    first ("holy" lists hagios and qadosh before the words glossed "holy" only now and then).
  /// 3. The lexicon's own gloss for the word holds an English word of the search.
  /// 4. The search is the word's spelling in English letters ("hagios", "qadosh") or its script.
  ///
  /// A word that holds more of the search's words comes before one that holds fewer. Empty when
  /// the database has no word index, as the BSB-only database has none. It reads and never
  /// writes, so a read-only connection may call it.
  List<WordMatch> searchWords(String text, {int limit = 40}) {
    if (!_hasGlossIndex || limit <= 0) return const [];
    final typed = text.trim();
    final tokens = searchTokens(text);
    if (tokens.isEmpty) return const [];
    if (_strongsOnly.hasMatch(typed.toUpperCase())) {
      final code = strongsBase(typed.toUpperCase());
      final entry = lexicon(code);
      if (entry == null) return const [];
      return [_wordMatch(entry, code, WordMatchKind.number, '', 0)];
    }

    final found = <String, _WordCandidate>{};
    _WordCandidate candidate(String code) => found.putIfAbsent(code, () => _WordCandidate(code));
    final content = {
      for (final t in tokens)
        if (t.length >= 2 && !searchStopWords.contains(t)) t,
    };
    for (final t in content) {
      if (!_englishWord.hasMatch(t)) continue;
      final stem = wordStem(t);
      if (stem.length < 2 || searchStopWords.contains(stem)) continue;
      for (final r in db.select(
        'SELECT strongs, n FROM gloss_index WHERE term = ? AND n >= ? ORDER BY n DESC, strongs LIMIT ?',
        [stem, _minFormUses, _wordCandidates],
      )) {
        candidate(r['strongs'] as String).add(_WordTier.glossed, t, glossed: r['n'] as int);
      }
      // "LIKE" narrows the lexicon to rows that might hold the word; the stems decide.
      for (final r in db.select('SELECT base, gloss FROM lexicon WHERE gloss LIKE ?', ['%$t%'])) {
        if (glossStems(r['gloss'] as String).contains(stem)) {
          candidate(r['base'] as String).add(_WordTier.defined, t);
        }
      }
    }
    _spelledWords(typed, candidate);

    // One grouped count for every candidate, so ranking by use is not a query per word.
    final codes = found.keys.toList();
    final uses = <String, int>{};
    for (var i = 0; i < codes.length; i += _textChunk) {
      final chunk = codes.sublist(i, min(i + _textChunk, codes.length));
      for (final r in db.select(
        'SELECT strongs, COUNT(*) AS n FROM word_index WHERE strongs IN '
        '(${List.filled(chunk.length, '?').join(',')}) GROUP BY strongs',
        chunk,
      )) {
        uses[r['strongs'] as String] = r['n'] as int;
      }
    }
    // More of the search's words first; then how the word was found; then how much it is used.
    int weight(_WordCandidate c) => c.tier == _WordTier.glossed ? c.glossed : uses[c.code] ?? 0;
    final ranked = found.values.toList()
      ..sort((a, b) {
        final byWords = b.terms.length.compareTo(a.terms.length);
        if (byWords != 0) return byWords;
        final byTier = a.tier.index.compareTo(b.tier.index);
        if (byTier != 0) return byTier;
        final byUse = weight(b).compareTo(weight(a));
        return byUse != 0 ? byUse : a.code.compareTo(b.code);
      });

    final out = <WordMatch>[];
    for (final c in ranked) {
      if (out.length >= limit) break;
      final entry = lexicon(c.code);
      if (entry == null) continue;
      // A word that only fills a slot in a sentence says nothing about the search's word.
      if (c.tier != _WordTier.spelled && isFunctionWord(entry)) continue;
      out.add(_wordMatch(entry, c.code, c.tier.kind, c.terms.firstOrNull ?? '', c.glossed));
    }
    return out;
  }

  /// Adds the words whose spelling in English letters is [typed], or begins with it, or whose
  /// own script is [typed].
  void _spelledWords(String typed, _WordCandidate Function(String code) candidate) {
    if (typed.isEmpty || typed.contains(RegExp(r'\s'))) return;
    if (!_spelledLetters.hasMatch(typed)) {
      for (final r in db.select('SELECT base FROM lexicon WHERE lemma = ?', [typed])) {
        candidate(r['base'] as String).add(_WordTier.spelled, '');
      }
      return;
    }
    final plain = typed.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (plain.length < _minSpellingWord) return;
    // STEPBible spells Hebrew with dots between syllables ("qa.dosh").
    const letters = "REPLACE(REPLACE(REPLACE(LOWER(translit), '.', ''), '-', ''), '·', '')";
    final rows = plain.length >= _minSpellingPrefix
        ? db.select('SELECT base FROM lexicon WHERE $letters LIKE ?', ['$plain%'])
        : db.select('SELECT base FROM lexicon WHERE $letters = ?', [plain]);
    for (final r in rows) {
      candidate(r['base'] as String).add(_WordTier.spelled, '');
    }
  }

  WordMatch _wordMatch(LexEntry entry, String code, WordMatchKind kind, String term, int glossed) {
    final r = db.select(
      "SELECT COUNT(*) AS n, COUNT(DISTINCT book || ':' || chapter || ':' || verse) AS v "
      'FROM word_index WHERE strongs = ?',
      [code],
    ).first;
    return WordMatch(
      entry: entry,
      code: code,
      kind: kind,
      term: term,
      glossed: glossed,
      uses: r['n'] as int,
      verses: r['v'] as int,
    );
  }

  static const _byBibleOrder = 'ORDER BY v.book, v.chapter, v.verse';
  static const _orderMetaKey = 'bible_order';
  static const _textChunk = 500;

  /// Row-id ranges of the translations stored in Bible order, one contiguous run each, from the
  /// meta row [recordBibleOrder] writes. For these the index answers in Bible order by itself, with
  /// no join to the verse table, which is thousands of random reads on a phone.
  late final Map<String, (int, int)> _orderedRanges = () {
    try {
      final rows = db.select('SELECT value FROM meta WHERE key = ?', [_orderMetaKey]);
      if (rows.isEmpty) return const <String, (int, int)>{};
      return {
        for (final part in (rows.first['value'] as String).split(','))
          if (RegExp(r'^[^:]+:\d+-\d+$').hasMatch(part))
            part.split(':').first: (
              int.parse(part.split(':').last.split('-').first),
              int.parse(part.split('-').last),
            ),
      };
    } on SqliteException {
      return const <String, (int, int)>{};
    }
  }();

  /// Notes which translations hold their verses in one run of rows in Bible order. A builder calls
  /// this once the verses are loaded; a translation that fails the check is left out, and its
  /// searches take the slower join.
  void recordBibleOrder() {
    final last = <String, ({int first, int last, int count, int ordered})>{};
    final prev = <String, (int, int, int)>{};
    final rows = db.select(
      'SELECT id, translation, book, chapter, verse FROM verses ORDER BY id',
    );
    for (final r in rows) {
      final t = r['translation'] as String;
      final key = (r['book'] as int, r['chapter'] as int, r['verse'] as int);
      final id = r['id'] as int;
      final old = last[t];
      final p = prev[t];
      final inOrder = p == null ||
          key.$1 > p.$1 ||
          (key.$1 == p.$1 && (key.$2 > p.$2 || (key.$2 == p.$2 && key.$3 > p.$3)));
      last[t] = old == null
          ? (first: id, last: id, count: 1, ordered: inOrder ? 1 : 0)
          : (
              first: old.first,
              last: id,
              count: old.count + 1,
              ordered: old.ordered + (inOrder ? 1 : 0),
            );
      prev[t] = key;
    }
    final kept = [
      for (final e in last.entries)
        if (e.value.count == e.value.last - e.value.first + 1 && e.value.ordered == e.value.count)
          '${e.key}:${e.value.first}-${e.value.last}',
    ];
    db.execute('DELETE FROM meta WHERE key = ?', [_orderMetaKey]);
    db.execute('INSERT INTO meta VALUES (?, ?)', [_orderMetaKey, kept.join(',')]);
  }

  /// Row ids of the verses the index matches, in Bible order. No verse text is read.
  List<int> _matchIds(String ftsQuery, String translation) {
    final range = _orderedRanges[translation];
    final rows = range != null
        ? db.select(
            'SELECT rowid AS id FROM verses_fts WHERE verses_fts MATCH ? '
            'AND rowid BETWEEN ? AND ? ORDER BY rowid',
            [ftsQuery, range.$1, range.$2],
          )
        : db.select(
            'SELECT v.id FROM verses_fts f JOIN verses v ON v.id = f.rowid '
            'WHERE verses_fts MATCH ? AND v.translation = ? $_byBibleOrder',
            [ftsQuery, translation],
          );
    return [for (final r in rows) r['id'] as int];
  }

  /// Like [_matchIds], keeping only verses whose text holds the words themselves, not a stem.
  List<int> _exactIds(String ftsQuery, RegExp exact, String translation) {
    final candidates = _matchIds(ftsQuery, translation);
    final kept = <int>{};
    for (var i = 0; i < candidates.length; i += _textChunk) {
      final chunk = candidates.sublist(i, min(i + _textChunk, candidates.length));
      final rows = db.select(
        'SELECT id, text FROM verses WHERE id IN (${List.filled(chunk.length, '?').join(',')})',
        chunk,
      );
      for (final r in rows) {
        if (exact.hasMatch(r['text'] as String)) kept.add(r['id'] as int);
      }
    }
    return [
      for (final id in candidates)
        if (kept.contains(id)) id,
    ];
  }

  List<Verse> _versesById(Iterable<int> ids) {
    final list = ids.toList();
    if (list.isEmpty) return const [];
    final rows = db.select(
      'SELECT v.book, v.chapter, v.verse, v.text FROM verses v '
      'WHERE v.id IN (${List.filled(list.length, '?').join(',')}) $_byBibleOrder',
      list,
    );
    return rows.map(_verse).toList();
  }

  /// The file this database was opened from, or null for one held in memory.
  String? get filePath {
    final file = db.select('PRAGMA database_list').firstWhere((r) => r['name'] == 'main')['file'];
    return file is String && file.isNotEmpty ? file : null;
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

  /// Stores each BSB verse's words aligned to the BSB translation tables (see [alignBsbWords]),
  /// replacing any earlier alignment. Returns the number of verses aligned.
  late bool _hasRenderings = db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'bsb_renderings'")
      .isNotEmpty;

  /// Counts every English rendering the BSB tables give each original word: for each Strong's
  /// number, each English phrase and how many times the BSB prints it for that number. A row the
  /// BSB leaves untranslated is kept as an empty phrase. Brackets mark words the translators
  /// supplied and are dropped; phrases are compared in lower case and shown in the casing most
  /// often printed. Returns how many number and phrase pairs were stored.
  int importRenderings(Map<Ref, List<BsbRow>> tables) {
    final counts = <String, Map<String, Map<String, int>>>{};
    for (final rows in tables.values) {
      for (final r in rows) {
        if (r.code.isEmpty) continue;
        var shown = r.english.replaceAll(RegExp(r'[\[\]{}]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
        // The tables mark an original word whose English stands elsewhere with dots, a dash or vvv.
        if (RegExp(r'^[.\s-]*$').hasMatch(shown) || shown == 'vvv') shown = '';
        final byCasing = counts.putIfAbsent(r.code, () => {}).putIfAbsent(shown.toLowerCase(), () => {});
        byCasing[shown] = (byCasing[shown] ?? 0) + 1;
      }
    }
    db.execute(
      'DROP TABLE IF EXISTS bsb_renderings; '
      'CREATE TABLE bsb_renderings(code TEXT, english TEXT, n INTEGER, PRIMARY KEY(code, english)) WITHOUT ROWID;',
    );
    final insert = db.prepare('INSERT INTO bsb_renderings VALUES (?, ?, ?)');
    var stored = 0;
    db.execute('BEGIN');
    try {
      for (final byCode in counts.entries) {
        for (final phrase in byCode.value.values) {
          final total = phrase.values.fold<int>(0, (a, b) => a + b);
          final casing = (phrase.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
          insert.execute([byCode.key, casing, total]);
          stored++;
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      insert.dispose();
    }
    _hasRenderings = true;
    return stored;
  }

  /// How the BSB tables render a Strong's number: each English phrase with its count, most
  /// printed first. The empty phrase is the uses the BSB leaves without an English word of their
  /// own. Empty for a number the tables do not use, and for a database built without them.
  List<({String english, int count})> bsbRenderings(String strongs) {
    if (!_hasRenderings) return const [];
    final code = strongs.replaceAll(RegExp(r'[A-Za-z]$'), '');
    return [
      for (final r in db.select(
        'SELECT english, n FROM bsb_renderings WHERE code = ? ORDER BY n DESC, english',
        [code],
      ))
        (english: r['english'] as String, count: r['n'] as int),
    ];
  }

  int importBsbAlignment(Map<Ref, List<BsbRow>> tables) {
    db.execute('''
      DROP TABLE IF EXISTS bsb_words;
      CREATE TABLE bsb_words(book INTEGER, chapter INTEGER, verse INTEGER, codes TEXT,
        PRIMARY KEY(book, chapter, verse)) WITHOUT ROWID;
    ''');
    final insert = db.prepare('INSERT INTO bsb_words VALUES (?, ?, ?, ?)');
    var n = 0;
    db.execute('BEGIN');
    try {
      for (final e in tables.entries) {
        final text = passage(e.key).firstOrNull?.text;
        if (text == null) continue;
        insert.execute([
          e.key.book.id,
          e.key.chapter,
          e.key.verseStart,
          _encodeBsbWords(alignBsbWords(text, e.value)),
        ]);
        n++;
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      insert.dispose();
    }
    _hasBsbWords = true;
    return n;
  }

  /// One token per word: '-' or the bare number (the book says Hebrew or Greek), then '/n' for the
  /// nth use of that number in the original's order when n is above 0, then '+' when the word
  /// continues the table row of the word before it.
  static String _encodeBsbWords(List<BsbWord> words) => [
    for (var i = 0; i < words.length; i++)
      '${words[i].code.isEmpty ? '-' : int.parse(words[i].code.substring(1))}'
          '${words[i].repeat > 0 ? '/${words[i].repeat}' : ''}'
          '${words[i].rowStart < i ? '+' : ''}',
  ].join(' ');

  static final _bsbToken = RegExp(r'^(-|\d+)(?:/(\d+))?(\+)?$');

  bool? _hasBsbWords;

  /// Each word of [ref] as the BSB translation tables place it, in [verseWordPattern] order. Null
  /// when the database has no alignment for the verse.
  List<BsbWord>? bsbWords(Ref ref) {
    _hasBsbWords ??= db
        .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'bsb_words'")
        .isNotEmpty;
    if (!_hasBsbWords!) return null;
    final rows = db.select(
      'SELECT codes FROM bsb_words WHERE book = ? AND chapter = ? AND verse = ?',
      [ref.book.id, ref.chapter, ref.verseStart ?? 1],
    );
    if (rows.isEmpty) return null;
    final lang = ref.book.id < 40 ? 'H' : 'G';
    final tokens = (rows.first['codes'] as String).split(' ');
    final starts = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      starts.add(tokens[i].endsWith('+') && i > 0 ? starts[i - 1] : i);
    }
    final words = <BsbWord>[];
    for (var i = 0; i < tokens.length; i++) {
      final m = _bsbToken.firstMatch(tokens[i]);
      var end = i + 1;
      while (end < tokens.length && starts[end] == starts[i]) {
        end++;
      }
      words.add(
        BsbWord(
          m == null || m[1] == '-' ? '' : strongsBase('$lang${m[1]}'),
          int.tryParse(m?[2] ?? '') ?? 0,
          starts[i],
          end,
        ),
      );
    }
    return words;
  }

  /// The base Strong's number behind each word of [ref] in the BSB ('' where the translators
  /// supplied the word), in [verseWordPattern] order. Null when the database has no alignment
  /// for the verse.
  List<String>? bsbCodes(Ref ref) => bsbWords(ref)?.map((w) => w.code).toList();

  /// True when [word] is the English of a name in the original-language lexicon ("Jesus", "Noah",
  /// "Christ"), whatever its case.
  bool isName(String word) => db.select(
    "SELECT 1 FROM lexicon WHERE pos LIKE 'N:%' AND gloss = ? COLLATE NOCASE LIMIT 1",
    [word],
  ).isNotEmpty;

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

  /// How many verses use [code] anywhere in the Bible.
  int wordVerseCount(String code) {
    _ensureWordIndex();
    return db.select(
          'SELECT COUNT(*) AS n FROM (SELECT DISTINCT book, chapter, verse FROM word_index '
          'WHERE strongs = ?)',
          [strongsBase(code)],
        ).first['n']
        as int;
  }

  /// How many verses [translation] has.
  int verseCount({String translation = defaultTranslation}) =>
      db.select('SELECT COUNT(*) AS n FROM verses WHERE translation = ?', [translation]).first['n']
          as int;

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

  late final bool _hasLexiconSources = db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'lexicon_source'")
      .isNotEmpty;
  String get _sourceColumn => _hasLexiconSources ? "COALESCE(ls.source, '')" : "''";
  String get _sourceJoin => _hasLexiconSources ? 'LEFT JOIN lexicon_source ls ON ls.key = lexicon.key' : '';

  /// Every entry STEPBible keeps under a Strong's number, by key: H7307 has G (spirit), H (breath),
  /// I (side) and more. [lexicon] gives one of them; a number reached without a verse's own
  /// tag should offer all.
  List<LexEntry> lexiconEntries(String strongs) {
    final base = strongs.replaceAll(RegExp(r'[A-Za-z]$'), '');
    return [
      for (final r in db.select(
        'SELECT lexicon.key AS key, lemma, translit, pos, gloss, definition, $_sourceColumn AS source '
        'FROM lexicon $_sourceJoin WHERE base = ? ORDER BY lexicon.key',
        [base],
      ))
        LexEntry(
          r['key'] as String,
          r['lemma'] as String,
          r['translit'] as String,
          r['pos'] as String,
          r['gloss'] as String,
          r['definition'] as String,
          r['source'] as String,
        ),
    ];
  }

  LexEntry? lexicon(String strongs) {
    final base = strongs.replaceAll(RegExp(r'[A-Za-z]$'), '');
    final rows = db.select(
      'SELECT lexicon.key AS key, lemma, translit, pos, gloss, definition, $_sourceColumn AS source '
      'FROM lexicon $_sourceJoin WHERE lexicon.key = ? OR base = ? '
      'ORDER BY (lexicon.key = ?) DESC, lexicon.key LIMIT 1',
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
      r['source'] as String,
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
      'ORDER BY n DESC, v DESC, to_book, to_chapter, to_verse_start LIMIT ?',
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

  /// The passages [ref] points to, most voted first. With [toNewTestament], only those in the
  /// New Testament (true) or the Old (false).
  List<XRef> xrefs(Ref ref, {int k = 8, bool? toNewTestament}) {
    final vs = ref.verseStart ?? 1;
    final ve = ref.verseStart == null ? 999 : (ref.verseEnd ?? vs);
    final testament = switch (toNewTestament) {
      null => '',
      true => 'AND to_book > $otBookCount ',
      false => 'AND to_book <= $otBookCount ',
    };
    final rows = db.select(
      'SELECT to_book, to_chapter, to_verse_start, to_verse_end, MAX(votes) AS votes FROM xrefs '
      'WHERE from_book = ? AND from_chapter = ? AND from_verse BETWEEN ? AND ? $testament'
      'GROUP BY to_book, to_chapter, to_verse_start, to_verse_end '
      'ORDER BY votes DESC, to_book, to_chapter, to_verse_start, to_verse_end LIMIT ?',
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
