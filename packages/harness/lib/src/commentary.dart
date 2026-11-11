import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'search_text.dart';

/// A public domain commentary Berea can carry, with the attribution shown beside its text.
class CommentaryModule {
  /// The CrossWire SWORD module name; also the `module` column of a pack.
  final String id;
  final String title;
  final String author;
  final String licence;
  final String source;

  /// Matthew Henry keys each comment to a section's first verse; it runs to the next comment.
  final bool sectionKeyed;

  /// Calvin's sections name their verses, and his front matter comes before the first one.
  final bool annotateKeyed;

  /// Spurgeon keeps a whole psalm at its first verse, with paragraphs headed "Verse N."
  final bool verseParagraphs;

  /// KD, Clarke and Barnes put a book's preface before a heading such as "Isa 1:1" or "Verse 1".
  final bool introBeforeHeading;
  const CommentaryModule(
    this.id,
    this.title,
    this.author, {
    this.licence = 'Public domain',
    this.source = 'CrossWire SWORD module',
    this.sectionKeyed = false,
    this.annotateKeyed = false,
    this.verseParagraphs = false,
    this.introBeforeHeading = false,
  });
}

const commentaryModules = <CommentaryModule>[
  CommentaryModule('MHCC', "Matthew Henry's Concise Commentary", 'Matthew Henry, 1706-1721'),
  CommentaryModule(
    'JFB',
    'Commentary Critical and Explanatory on the Whole Bible',
    'Robert Jamieson, A. R. Fausset and David Brown, 1871',
  ),
  CommentaryModule('TSK', 'The Treasury of Scripture Knowledge', 'R. A. Torrey (ed.), 1880s'),
  CommentaryModule(
    'Catena',
    'Catena Aurea on the Gospels',
    'Thomas Aquinas, tr. John Henry Newman, 1842',
    licence: 'Public domain (CrossWire); OSIS by Tom Lemmens, github.com/lemtom/catena, CC0',
  ),
  CommentaryModule(
    'MHC',
    "Matthew Henry's Commentary on the Whole Bible",
    'Matthew Henry, 1706-1721',
    sectionKeyed: true,
  ),
  CommentaryModule(
    'Clarke',
    "Adam Clarke's Commentary on the Bible",
    'Adam Clarke, 1810-1826',
    introBeforeHeading: true,
  ),
  CommentaryModule(
    'CalvinCommentaries',
    "Calvin's Commentaries",
    'John Calvin, tr. Calvin Translation Society, 1844-1856',
    annotateKeyed: true,
  ),
  CommentaryModule(
    'KD',
    'Commentary on the Old Testament',
    'C. F. Keil and F. Delitzsch, tr. 1866-1891',
    introBeforeHeading: true,
  ),
  CommentaryModule(
    'Barnes',
    "Barnes' Notes on the New Testament",
    'Albert Barnes, 1832-1851',
    introBeforeHeading: true,
  ),
  CommentaryModule('Wesley', "Wesley's Explanatory Notes", 'John Wesley, 1755-1765'),
  CommentaryModule(
    'TDavid',
    'The Treasury of David',
    'C. H. Spurgeon, 1869-1885',
    verseParagraphs: true,
  ),
];

CommentaryModule? commentaryModuleById(String id) {
  for (final m in commentaryModules) {
    if (m.id == id) return m;
  }
  return null;
}

/// A downloadable SQLite file holding one or more modules.
class CommentaryPackSpec {
  final String id;
  final String title;
  final List<String> modules;
  const CommentaryPackSpec(this.id, this.title, this.modules);

  String get fileName => 'commentary-$id.sqlite';
}

const commentaryPackSpecs = <CommentaryPackSpec>[
  CommentaryPackSpec('core', 'Core commentaries', ['MHCC', 'JFB', 'TSK', 'Catena']),
  CommentaryPackSpec('mhc', 'Matthew Henry, complete', ['MHC']),
  CommentaryPackSpec('clarke', 'Adam Clarke', ['Clarke']),
  CommentaryPackSpec('calvin', 'John Calvin', ['CalvinCommentaries']),
  CommentaryPackSpec('kd', 'Keil and Delitzsch (Old Testament)', ['KD']),
  CommentaryPackSpec('barnes', 'Albert Barnes (New Testament)', ['Barnes']),
  CommentaryPackSpec('wesley', 'John Wesley', ['Wesley']),
  CommentaryPackSpec('tdavid', 'Spurgeon, The Treasury of David (Psalms)', ['TDavid']),
];

/// Bumped when the pack schema changes; the app refuses packs it cannot read.
const commentaryPackFormat = '1';

const commentaryPackSchema = '''
  CREATE TABLE modules(id TEXT PRIMARY KEY, title TEXT, author TEXT, licence TEXT, source TEXT, position INTEGER);
  CREATE TABLE entries(id INTEGER PRIMARY KEY, module TEXT, book INTEGER, chapter INTEGER, verse_start INTEGER, verse_end INTEGER, html_or_text TEXT);
  CREATE INDEX entries_ref ON entries(book, chapter, verse_start);
  CREATE VIRTUAL TABLE entries_fts USING fts5(html_or_text, content='entries', content_rowid='id', tokenize='porter unicode61');
  CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
''';

/// One comment. A book introduction has chapter 0; a chapter introduction has verse 0.
class CommentaryEntry {
  final String module;
  final int book;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final String text;
  const CommentaryEntry(
    this.module,
    this.book,
    this.chapter,
    this.verseStart,
    this.verseEnd,
    this.text,
  );

  bool get isIntroduction => chapter == 0 || verseStart == 0;
}

/// Runs each single-verse comment to the verse before the next one in its chapter, or to its end.
List<CommentaryEntry> expandSectionStarts(
  List<CommentaryEntry> entries,
  int Function(int book, int chapter) versesIn,
) {
  final out = <CommentaryEntry>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (e.isIntroduction || e.verseEnd > e.verseStart) {
      out.add(e);
      continue;
    }
    final next = i + 1 < entries.length ? entries[i + 1] : null;
    final sameChapter =
        next != null &&
        next.module == e.module &&
        next.book == e.book &&
        next.chapter == e.chapter &&
        next.verseStart > e.verseStart;
    final end = sameChapter ? next.verseStart - 1 : versesIn(e.book, e.chapter);
    out.add(CommentaryEntry(e.module, e.book, e.chapter, e.verseStart, end, e.text));
  }
  return out;
}

final _notes = RegExp(r'<note\b[^>]*>(.*?)</note>', dotAll: true);
final _selfClosingNote = RegExp(r'<note\b[^>]*/>');
final _titles = RegExp(r'<title\b[^>]*>(.*?)</title>', dotAll: true);
final _blockTags = RegExp(
  r'<(?:br|lb|p|/p|l|/l|lg|/lg|item|/item|list|/list|row|/row|cell|/cell)\b[^>]*>|'
  r'<div\b[^>]*type="(?:x-p|paragraph|introduction|section|subSection)"[^>]*>',
  caseSensitive: false,
);
final _anyTag = RegExp(r'<[^>]*>');
final _numericEntity = RegExp(r'&#(x[0-9a-fA-F]+|\d+);');
final _namedEntity = RegExp(r'&([a-zA-Z]+);');
final _spaces = RegExp(r'[ \t\u00a0]+');
final _lineEdges = RegExp(r' *\n *');
final _blankLines = RegExp(r'\n{2,}');

const _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'mdash': '\u2014',
  'ndash': '\u2013',
  'lsquo': '\u2018',
  'rsquo': '\u2019',
  'ldquo': '\u201c',
  'rdquo': '\u201d',
  'hellip': '\u2026',
};

/// Plain display text from OSIS or ThML: line breaks kept, notes bracketed, other markup gone.
String commentaryPlainText(String markup) {
  final text = markup
      .replaceAllMapped(_notes, (m) => ' [${m[1]!.replaceAll(_anyTag, '').trim()}]')
      .replaceAll(_selfClosingNote, '')
      .replaceAllMapped(_titles, (m) => '\n${m[1]}\n')
      .replaceAll(_blockTags, '\n')
      .replaceAll(_anyTag, '')
      .replaceAll(' []', '');
  return decodeHtmlEntities(text)
      .replaceAll('\r', '')
      .replaceAll(_spaces, ' ')
      .replaceAll(_lineEdges, '\n')
      .replaceAll(_blankLines, '\n')
      .trim();
}

const _maxCodePoint = 0x10FFFF;
const _surrogateFirst = 0xD800;
const _surrogateLast = 0xDFFF;
const _replacementCharacter = '�';

/// Numeric entities and the named ones these sources use; invalid code points become U+FFFD.
String decodeHtmlEntities(String s) => s
    .replaceAllMapped(_numericEntity, (m) {
      final v = m[1]!;
      final code = v.startsWith('x') ? int.tryParse(v.substring(1), radix: 16) : int.tryParse(v);
      if (code == null) return m[0]!;
      final valid = code > 0 && code <= _maxCodePoint;
      final surrogate = code >= _surrogateFirst && code <= _surrogateLast;
      return valid && !surrogate ? String.fromCharCode(code) : _replacementCharacter;
    })
    .replaceAllMapped(_namedEntity, (m) => _entities[m[1]] ?? m[0]!);

/// A comment that holds the words searched for, cut to the passage around the first of them.
class CommentaryHit {
  final String module;
  final int book;
  final int chapter;
  final int verseStart;
  final int verseEnd;

  /// A few lines of the comment around the words, with an ellipsis where it was cut.
  final String snippet;

  /// Character ranges of [snippet] that are the searched words, or forms of them.
  final List<(int, int)> marks;
  const CommentaryHit(
    this.module,
    this.book,
    this.chapter,
    this.verseStart,
    this.verseEnd,
    this.snippet,
    this.marks,
  );

  bool get isIntroduction => chapter == 0 || verseStart == 0;
}

/// What the commentary search found: the best comments of each work, and how many each work has.
class CommentarySearch {
  /// The best matches of each work, in catalog order and, within a work, best match first.
  final List<CommentaryHit> hits;

  /// Comments that hold the words, by work, whether or not they are in [hits].
  final Map<String, int> totals;
  const CommentarySearch(this.hits, this.totals);

  static const empty = CommentarySearch([], {});

  int get total => totals.values.fold(0, (a, b) => a + b);
}

/// Characters before and after the first match that a snippet keeps.
const _snippetBefore = 90;
const _snippetAfter = 190;

/// The shortest stem a snippet marks, so a mark is a word's form and not any word it begins.
const _minMarkStem = 3;

const _packTables = {'entries', 'modules', 'meta'};

/// The installed packs, each its own read-only SQLite file apart from the Bible database.
class CommentaryLibrary {
  final _packs = <String, Database>{};

  Iterable<String> get installed => _packs.keys;

  bool get isEmpty => _packs.isEmpty;

  /// Opens the pack at [path] as [id]; false, leaving nothing open, unless it is a readable pack.
  bool open(String id, String path) {
    if (_packs.containsKey(id)) return true;
    if (!File(path).existsSync()) return false;
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      // A picked file is untrusted: no functions from its schema run, and its tables must be real.
      db.execute('PRAGMA trusted_schema = OFF');
      if (!_isPack(db)) {
        db.dispose();
        return false;
      }
      _packs[id] = db;
      return true;
    } on SqliteException {
      db?.dispose();
      return false;
    }
  }

  static bool _isPack(Database db) {
    final tables = {
      for (final r in db.select("SELECT name FROM sqlite_master WHERE type = 'table'"))
        r['name'] as String?,
    };
    if (!tables.containsAll(_packTables)) return false;
    final format = db.select("SELECT value FROM meta WHERE key = 'format'");
    if (format.isEmpty || format.first['value'] != commentaryPackFormat) return false;
    db.select(
      'SELECT module, book, chapter, verse_start, verse_end, html_or_text FROM entries LIMIT 1',
    );
    db.select('SELECT id, title, author, licence, source, position FROM modules LIMIT 1');
    return true;
  }

  /// The id a valid pack at [path] declares, or null when it is not a pack this version reads.
  static String? packIdOf(String path) {
    final probe = CommentaryLibrary();
    if (!probe.open('probe', path)) return null;
    try {
      final rows = probe._packs['probe']!.select("SELECT value FROM meta WHERE key = 'pack'");
      return switch (rows.firstOrNull?['value']) {
        final String id => id,
        _ => null,
      };
    } on SqliteException {
      return null;
    } finally {
      probe.closeAll();
    }
  }

  void close(String id) => _packs.remove(id)?.dispose();

  void closeAll() {
    for (final db in _packs.values) {
      db.dispose();
    }
    _packs.clear();
  }

  /// Modules across the installed packs, in catalog order; a pack that cannot be read is skipped.
  List<CommentaryModule> modules() {
    final out = <CommentaryModule>[];
    for (final db in _packs.values) {
      try {
        for (final r in db.select('SELECT * FROM modules ORDER BY position')) {
          if (_moduleOf(r) case final m?) out.add(m);
        }
      } on SqliteException {
        continue;
      }
    }
    out.sort((a, b) => _order(a.id).compareTo(_order(b.id)));
    return out;
  }

  static CommentaryModule? _moduleOf(Row r) => switch (r) {
    {
      'id': final String id,
      'title': final String title,
      'author': final String author,
      'licence': final String licence,
      'source': final String source,
    } =>
      CommentaryModule(id, title, author, licence: licence, source: source),
    _ => null,
  };

  /// Comments that touch verses [first] to [last] of a chapter, grouped by module in catalog order.
  List<CommentaryEntry> forRange(int book, int chapter, int first, int last) => _query(
    'WHERE book = ? AND chapter = ? AND verse_start > 0 AND verse_start <= ? AND verse_end >= ? '
    'ORDER BY verse_start, id',
    [book, chapter, last, first],
  );

  /// The book introduction and the chapter introduction, when the commentaries have them.
  List<CommentaryEntry> introductions(int book, int chapter) => _query(
    'WHERE book = ? AND ((chapter = 0 AND verse_start = 0) OR (chapter = ? AND verse_start = 0)) '
    'ORDER BY chapter, id',
    [book, chapter],
  );

  /// The comments, across the installed packs, that hold every word of [text] (or its exact
  /// words in order, when it is only function words). Each work's [perModule] best matches come
  /// back with the words marked, and [CommentarySearch.totals] counts all of a work's. A work with
  /// no comment on the words is left out.
  CommentarySearch search(String text, {int perModule = 5}) {
    final tokens = searchTokens(text);
    if (tokens.isEmpty || searchIsTooCommon(text)) return CommentarySearch.empty;
    final words = [
      for (final t in tokens)
        if (!searchStopWords.contains(t)) t,
    ];
    final match = words.isEmpty ? '"${tokens.join(' ')}"' : words.map((t) => '"$t"').join(' ');
    final marker = _markerFor(words.isEmpty ? tokens : words);
    final phrase = words.length > 1 ? phrasePattern(words) : null;
    final hits = <(int, CommentaryHit)>[];
    final totals = <String, int>{};
    for (final db in _packs.values) {
      try {
        final counts = db.select(
          'SELECT e.module AS module, COUNT(*) AS n FROM entries_fts f '
          'JOIN entries e ON e.id = f.rowid WHERE entries_fts MATCH ? GROUP BY e.module',
          [match],
        );
        for (final c in counts) {
          final module = c['module'] as String;
          totals[module] = (totals[module] ?? 0) + (c['n'] as int);
          // A few more than are kept, so an exact phrase can come ahead of a better-scored scatter.
          final rows = db.select(
            'SELECT e.module, e.book, e.chapter, e.verse_start, e.verse_end, e.html_or_text '
            'FROM entries_fts f JOIN entries e ON e.id = f.rowid '
            'WHERE entries_fts MATCH ? AND e.module = ? ORDER BY bm25(entries_fts) LIMIT ?',
            [match, module, perModule * _phraseLookahead],
          );
          final ranked = [
            for (final r in rows)
              if (_entryOf(r) case final e?) (e, phrase != null && phrase.hasMatch(e.text)),
          ];
          // Dart's sort is not stable, so the score order is carried in the key.
          final order = {for (var i = 0; i < ranked.length; i++) ranked[i].$1: i};
          ranked.sort((a, b) {
            if (a.$2 != b.$2) return a.$2 ? -1 : 1;
            return order[a.$1]!.compareTo(order[b.$1]!);
          });
          for (final (e, _) in ranked.take(perModule)) {
            hits.add((_order(module), _hitOf(e, marker)));
          }
        }
      } on SqliteException {
        continue;
      }
    }
    // Ties keep the order they were added in: the best match of a work first.
    final indexed = [for (var i = 0; i < hits.length; i++) (i, hits[i])];
    indexed.sort((a, b) {
      final byModule = a.$2.$1.compareTo(b.$2.$1);
      return byModule != 0 ? byModule : a.$1.compareTo(b.$1);
    });
    return CommentarySearch([for (final h in indexed) h.$2.$2], totals);
  }

  static const _phraseLookahead = 4;
  static const _maxMarks = 8;

  /// Finds each of [words], or a form of it, as a whole word's start: "holy" marks "holiness".
  static RegExp _markerFor(List<String> words) {
    final stems = {for (final w in words) _markStem(w)}.map(RegExp.escape).join('|');
    return RegExp(
      '(?<![\\p{L}\\p{M}\\p{N}])(?:$stems)[\\p{L}\\p{M}\\p{N}]*',
      unicode: true,
      caseSensitive: false,
    );
  }

  /// A word without its ending, so its other forms share it; never shorter than [_minMarkStem].
  static String _markStem(String word) {
    for (final tail in const ['ness', 'ing', 'ies', 'ed', 'es', 'ly', 's', 'y', 'e']) {
      if (word.endsWith(tail) && word.length - tail.length >= _minMarkStem) {
        return word.substring(0, word.length - tail.length);
      }
    }
    return word;
  }

  /// The comment cut to a line or two around the first of the words, at spaces, with the words
  /// marked.
  static CommentaryHit _hitOf(CommentaryEntry e, RegExp marker) {
    final text = e.text;
    final first = marker.firstMatch(text)?.start ?? 0;
    var from = first > _snippetBefore ? first - _snippetBefore : 0;
    var to = first + _snippetAfter < text.length ? first + _snippetAfter : text.length;
    if (from > 0) {
      final space = text.indexOf(RegExp(r'\s'), from);
      from = space < 0 || space > first ? from : space + 1;
    }
    if (to < text.length) {
      final space = text.lastIndexOf(RegExp(r'\s'), to);
      to = space > first ? space : to;
    }
    final body = text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ').trim();
    final snippet = '${from > 0 ? '…' : ''}$body${to < text.length ? '…' : ''}';
    final marks = [
      for (final m in marker.allMatches(snippet).take(_maxMarks)) (m.start, m.end),
    ];
    return CommentaryHit(e.module, e.book, e.chapter, e.verseStart, e.verseEnd, snippet, marks);
  }

  /// Rows from every pack; a pack that cannot be read, or a malformed row, is skipped.
  List<CommentaryEntry> _query(String where, List<Object> args) {
    final out = <CommentaryEntry>[];
    for (final db in _packs.values) {
      try {
        final rows = db.select(
          'SELECT module, book, chapter, verse_start, verse_end, html_or_text FROM entries $where',
          args,
        );
        out.addAll(rows.map(_entryOf).nonNulls);
      } on SqliteException {
        continue;
      }
    }
    // Ties keep query order, so each module keeps its own verse order.
    final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])];
    indexed.sort((a, b) {
      final byModule = _order(a.$2.module).compareTo(_order(b.$2.module));
      return byModule != 0 ? byModule : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  static CommentaryEntry? _entryOf(Row r) => switch (r) {
    {
      'module': final String module,
      'book': final int book,
      'chapter': final int chapter,
      'verse_start': final int start,
      'verse_end': final int end,
      'html_or_text': final String text,
    } =>
      CommentaryEntry(module, book, chapter, start, end, text),
    _ => null,
  };

  static int _order(String module) {
    final i = commentaryModules.indexWhere((m) => m.id == module);
    return i < 0 ? commentaryModules.length : i;
  }
}
