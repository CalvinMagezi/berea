import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'books.dart';
import 'importers.dart';
import 'ref_parser.dart';
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

/// A heading printed before [verse]; see [HeadingRow] for the kinds.
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

const defaultTranslation = 'BSB';

/// Translation codes are short uppercase identifiers; they also name files on disk.
const translationCodeMax = 8;
final translationCode = RegExp('^[A-Z0-9]{1,$translationCodeMax}\$');
const maxPassageVerses = 40;

/// SQLite reads a negative LIMIT as no limit.
const _noLimit = -1;

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

  /// Every verse of a chapter, for reading. [passage] caps what goes into a prompt instead.
  List<Verse> chapter(Book book, int chapter, {String translation = defaultTranslation}) => db
      .select(
        'SELECT book, chapter, verse, text FROM verses '
        'WHERE translation = ? AND book = ? AND chapter = ? ORDER BY verse',
        [translation, book.id, chapter],
      )
      .map(_verse)
      .toList();

  /// At most [maxPassageVerses] verses, so a whole chapter named in a question cannot crowd out
  /// the rest of a prompt.
  List<Verse> passage(Ref ref, {String translation = defaultTranslation}) =>
      _range(ref, translation, maxPassageVerses);

  /// Every verse of [ref], for reading or keeping; [passage] caps what goes into a prompt.
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

  /// Stores each BSB verse's words aligned to the BSB translation tables (see [alignBsbWords]),
  /// replacing any earlier alignment. Returns the number of verses aligned.
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
