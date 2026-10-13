import 'package:sqlite3/sqlite3.dart';

import 'commentary.dart';
import 'notebook_text.dart';
import 'ref_parser.dart';
import 'tier.dart';

/// Where a notebook source came from. Stored by name, so names never change.
enum SourceKind {
  text('Pasted text'),
  note('Your note'),
  passage('Bible passage'),
  commentary('Commentary'),
  pdf('PDF'),
  epub('EPUB');

  final String label;
  const SourceKind(this.label);

  static SourceKind? byName(String name) => values.where((k) => k.name == name).firstOrNull;
}

// Ids never get reused and triggers keep the index, so a late read or a restore stays consistent.
// Study store migration 0: never edit this text, add a migration instead.
const notebookSchema = '''
  CREATE TABLE IF NOT EXISTS notebooks(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
    created INTEGER, updated INTEGER);
  CREATE TABLE IF NOT EXISTS notebook_sources(id INTEGER PRIMARY KEY AUTOINCREMENT,
    notebook_id INTEGER NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL,
    origin TEXT NOT NULL DEFAULT '', text TEXT NOT NULL, created INTEGER);
  CREATE INDEX IF NOT EXISTS notebook_sources_notebook ON notebook_sources(notebook_id);
  CREATE TABLE IF NOT EXISTS notebook_chunks(id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL,
    ordinal INTEGER NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL,
    page INTEGER, text TEXT NOT NULL);
  CREATE INDEX IF NOT EXISTS notebook_chunks_source ON notebook_chunks(source_id, ordinal);
  CREATE VIRTUAL TABLE IF NOT EXISTS notebook_chunks_fts USING fts5(text,
    content='notebook_chunks', content_rowid='id', tokenize='porter unicode61');
  CREATE TRIGGER IF NOT EXISTS notebook_chunks_ai AFTER INSERT ON notebook_chunks BEGIN
    INSERT INTO notebook_chunks_fts(rowid, text) VALUES (new.id, new.text);
  END;
  CREATE TRIGGER IF NOT EXISTS notebook_chunks_ad AFTER DELETE ON notebook_chunks BEGIN
    INSERT INTO notebook_chunks_fts(notebook_chunks_fts, rowid, text)
      VALUES ('delete', old.id, old.text);
  END;
  CREATE TRIGGER IF NOT EXISTS notebook_chunks_au AFTER UPDATE ON notebook_chunks BEGIN
    INSERT INTO notebook_chunks_fts(notebook_chunks_fts, rowid, text)
      VALUES ('delete', old.id, old.text);
    INSERT INTO notebook_chunks_fts(rowid, text) VALUES (new.id, new.text);
  END;
''';

/// A passage of a notebook source, or of an installed commentary, that an answer may draw on.
class SourceChunk {
  /// The notebook source; null for a passage of an installed commentary pack.
  final int? sourceId;
  final String title;
  final SourceKind kind;

  /// The 0-based section of its source, or of its comment for commentary from a pack.
  final int ordinal;

  /// The 1-based PDF page, null for sources without pages.
  final int? page;
  final String text;

  /// For commentary from a pack, the verses it comments on, so it can be opened again.
  final Ref? ref;
  const SourceChunk({
    this.sourceId,
    required this.title,
    required this.kind,
    required this.ordinal,
    this.page,
    required this.text,
    this.ref,
  });

  bool get fromPack => sourceId == null;

  /// The same chunk with other text, used for what was actually shown to the model.
  SourceChunk withText(String t) => SourceChunk(
    sourceId: sourceId,
    title: title,
    kind: kind,
    ordinal: ordinal,
    page: page,
    text: t,
    ref: ref,
  );

  /// Identity across turns: a notebook chunk by source and section, a pack passage by place.
  String get key => fromPack ? 'C|${ref?.label}|$title|$ordinal' : 'S|$sourceId|$ordinal';

  /// True when [o] is part of the same source: the same notebook source, or the same comment.
  bool sameSource(SourceChunk o) =>
      fromPack ? o.fromPack && o.title == title && o.ref == ref : o.sourceId == sourceId;
}

/// A chunk as the model was shown it, with the tag it is cited by: "S3 p.14" for a PDF page,
/// "S3 §2" for a section of any other source, "C1" for commentary from a pack.
class ShownSource {
  final String tag;
  final SourceChunk chunk;
  const ShownSource(this.tag, this.chunk);

  /// Everything a saved answer needs to open the cited text again; the text itself stays in the
  /// notebook, so a saved answer never holds a second copy of it.
  Map<String, Object?> toJson() => {
    'tag': tag,
    'source': chunk.sourceId,
    'title': chunk.title,
    'kind': chunk.kind.name,
    'ordinal': chunk.ordinal,
    'page': chunk.page,
    'ref': chunk.ref?.label,
  };

  /// Null when [json] is not a citation this version wrote.
  static ShownSource? fromJson(Object? json) {
    if (json is! Map) return null;
    final (tag, title, kind, ordinal) = (json['tag'], json['title'], json['kind'], json['ordinal']);
    if (tag is! String || title is! String || kind is! String || ordinal is! int) return null;
    final (source, page, ref) = (json['source'], json['page'], json['ref']);
    if ((source != null && source is! int) || (page != null && page is! int)) return null;
    final chunk = SourceChunk(
      sourceId: source as int?,
      title: title,
      kind: SourceKind.byName(kind) ?? SourceKind.text,
      ordinal: ordinal,
      page: page as int?,
      text: '',
      ref: ref is String ? RefParser.parse(ref).firstOrNull : null,
    );
    return ShownSource(tag, chunk);
  }
}

/// Tags for [chunks] in the order they were shown. Notebook sources keep their id and pack
/// commentary a number drawn from where it comments, so a tag means the same passage in every
/// answer and an earlier answer in the history never names something else.
List<ShownSource> tagSources(Iterable<SourceChunk> chunks) {
  final used = <String>{};
  final out = <ShownSource>[];
  for (final c in chunks) {
    final tag = c.fromPack ? packTag(c, used) : notebookTag(c);
    if (c.fromPack) used.add(tag);
    out.add(ShownSource(tag, c));
  }
  return out;
}

String notebookTag(SourceChunk c) =>
    c.page != null ? 'S${c.sourceId} p.${c.page}' : 'S${c.sourceId} §${c.ordinal + 1}';

/// Pack commentary tags run from C1000 to C9999.
const _packTagFirst = 1000;
const _packTagCount = 9000;
const _fnvOffset = 0x811c9dc5;
const _fnvPrime = 0x01000193;
const _mask32 = 0xffffffff;

/// A stable tag for pack commentary [c] from its place (FNV-1a of [SourceChunk.key]), moved on
/// past any tag already in [used] so two passages in one prompt never share one.
String packTag(SourceChunk c, Set<String> used) {
  var h = _fnvOffset;
  for (final u in c.key.codeUnits) {
    h = ((h ^ u) * _fnvPrime) & _mask32;
  }
  var n = h % _packTagCount;
  while (used.contains('C${_packTagFirst + n}')) {
    n = (n + 1) % _packTagCount;
  }
  return 'C${_packTagFirst + n}';
}

/// One tag: the source, then optionally a page ("p.14", "pp. 14-15", "page 14") or a section
/// ("§3", "section 3"), possibly a range.
const _tagShape =
    r'[SC]\d{1,9}(?:,?\s*(?:pp?\.?|pages?|§|sec\.?|sections?)\s*\d{1,5}(?:\s*[-–]\s*\d{1,5})?)?';
final _tag = RegExp(
  r'([SC])(\d{1,9})(?:,?\s*(pp?\.?|pages?|§|sec\.?|sections?)\s*(\d{1,5})(?:\s*[-–]\s*(\d{1,5}))?)?',
  caseSensitive: false,
);

/// Brackets or parentheses holding only tags, several separated by ";" or ",". Models often
/// cite "(S3 p.1)" although the rules ask for square brackets, and an unchecked parenthesis
/// would let an invented one through.
final sourceCitationGroup = RegExp(
  '[\\[(]\\s*$_tagShape(?:\\s*[;,]\\s*$_tagShape)*\\s*[\\])]',
  caseSensitive: false,
);

/// Any brackets or parentheses on one line, judged one by one.
final _bracket = RegExp(r'[\[(][^\[\]()\n]{1,160}[\])]');

/// What a model writes when it means a source but not in the tag form: "[S 9]", "[Source 9]",
/// "[S3 and S9]", "[S9 §2-§4]", or a number too long to be a source. Square brackets only:
/// "(Source 9 of the list)" in prose is left alone.
final _looseTag = RegExp(r'^\[\s*(?:S|C|sources?)\s*#?\s*\d', caseSensitive: false);

/// The shown chunk [t] cites, or null when the source, page or section was not shown.
ShownSource? _resolve(Match t, List<ShownSource> shown) {
  final n = int.parse(t[2]!);
  final locator = t[3]?.toLowerCase();
  if (t[1]!.toUpperCase() == 'C') {
    return locator == null ? shown.where((s) => s.tag == 'C$n').firstOrNull : null;
  }
  final mine = shown.where((s) => s.chunk.sourceId == n).toList();
  if (locator == null) return mine.firstOrNull;
  final byPage = locator.startsWith('p');
  bool at(ShownSource s, int k) => byPage ? s.chunk.page == k : s.chunk.ordinal == k - 1;
  final from = int.parse(t[4]!);
  final to = t[5] == null ? null : int.parse(t[5]!);
  final first = mine.where((s) => at(s, from)).firstOrNull;
  if (first == null || (to != null && !mine.any((s) => at(s, to)))) return null;
  return first;
}

/// The result of checking every source tag in an answer.
class SourceCheck {
  final String text;
  final List<ShownSource> cited;
  final List<String> unverified;
  const SourceCheck(this.text, this.cited, this.unverified);
}

/// Keeps each tag in [output] that names a shown chunk and marks the rest
/// "unverified source: S9 p.40", in place, as invented verse references are marked. Brackets that
/// look like a source citation but are not in the tag form are marked whole.
SourceCheck checkSourceCitations(String output, List<ShownSource> shown) {
  final cited = <String, ShownSource>{};
  final unverified = <String>[];
  final text = output.replaceAllMapped(_bracket, (b) {
    final whole = b[0]!;
    if (sourceCitationGroup.matchAsPrefix(whole)?.end != whole.length) {
      if (!_looseTag.hasMatch(whole)) return whole;
      final inner = whole.substring(1, whole.length - 1).trim();
      unverified.add(inner);
      return '[unverified source: $inner]';
    }
    final parts = <String>[];
    for (final t in _tag.allMatches(whole)) {
      final hit = _resolve(t, shown);
      if (hit != null) {
        cited.putIfAbsent(hit.tag, () => hit);
        parts.add(t[0]!);
      } else {
        unverified.add(t[0]!);
        parts.add('unverified source: ${t[0]}');
      }
    }
    return '${whole[0]}${parts.join('; ')}${whole[whole.length - 1]}';
  });
  return SourceCheck(text, cited.values.toList(), unverified);
}

/// The shown chunks a tag group cites, or null when it cites none that were shown.
List<ShownSource>? citedChunks(Match group, List<ShownSource> shown) {
  final out = <ShownSource>[];
  for (final t in _tag.allMatches(group[0]!)) {
    if (_resolve(t, shown) case final hit?) {
      // A quote may come from any shown part of the cited source, not only the page named.
      out.addAll(shown.where((s) => s.chunk.sameSource(hit.chunk)));
    }
  }
  return out.isEmpty ? null : out;
}

/// Notebook chunk search for answers, over the tables in [notebookSchema]. The app and the eval
/// both use it, so the eval measures the retrieval that ships.
class NotebookIndex {
  final Database db;
  final int notebookId;
  const NotebookIndex(this.db, this.notebookId);

  static const _columns = 's.id AS source_id, s.title, s.kind, c.ordinal, c.page, c.text';

  static SourceChunk _chunk(Row r) => SourceChunk(
    sourceId: r['source_id'] as int,
    title: r['title'] as String,
    kind: SourceKind.byName(r['kind'] as String) ?? SourceKind.text,
    ordinal: r['ordinal'] as int,
    page: r['page'] as int?,
    text: r['text'] as String,
  );

  /// `AND s.id IN (...)` for [within], or nothing when it is null.
  static (String, List<Object>) _scope(Iterable<int>? within) {
    if (within == null) return ('', const []);
    final ids = within.toList();
    return ('AND s.id IN (${List.filled(ids.length, '?').join(', ')})', ids);
  }

  /// Chunks that best match any word of [query], best first; only of [within] when given.
  List<SourceChunk> search(String query, {required int limit, Iterable<int>? within}) {
    final q = notebookFtsQuery(query);
    if (q == null || limit <= 0 || (within != null && within.isEmpty)) return const [];
    final (scope, ids) = _scope(within);
    return db
        .select(
          'SELECT $_columns FROM notebook_chunks_fts f '
          'JOIN notebook_chunks c ON c.id = f.rowid '
          'JOIN notebook_sources s ON s.id = c.source_id '
          'WHERE notebook_chunks_fts MATCH ? AND s.notebook_id = ? $scope '
          'ORDER BY bm25(notebook_chunks_fts) LIMIT ?',
          [q, notebookId, ...ids, limit],
        )
        .map(_chunk)
        .toList();
  }

  /// The first sections of each source, taken in turn: every source's first, then every
  /// second, so a broad question ("summarise this") still sees each source.
  List<SourceChunk> openings({required int limit, Iterable<int>? within}) {
    if (limit <= 0 || (within != null && within.isEmpty)) return const [];
    final (scope, ids) = _scope(within);
    return db
        .select(
          'SELECT $_columns FROM notebook_chunks c '
          'JOIN notebook_sources s ON s.id = c.source_id WHERE s.notebook_id = ? $scope '
          'ORDER BY c.ordinal, s.created, s.id LIMIT ?',
          [notebookId, ...ids, limit],
        )
        .map(_chunk)
        .toList();
  }

  /// The passages of the notebook's Bible passage sources, from their origin ("John 3:16|BSB").
  List<Ref> passages() => [
    for (final r in db.select(
      "SELECT origin FROM notebook_sources WHERE notebook_id = ? AND kind = 'passage' "
      'ORDER BY created, id',
      [notebookId],
    ))
      ...RefParser.parse((r['origin'] as String).split('|').first).take(1),
  ];
}

/// Passages of the installed commentaries on [refs], cut to notebook chunk size so one long
/// comment cannot fill the prompt, best match for [question] first. At most [limit].
List<SourceChunk> commentaryChunks(
  CommentaryLibrary library,
  String question,
  List<Ref> refs,
  int limit,
) {
  if (limit <= 0 || library.isEmpty || refs.isEmpty) return const [];
  final words = _queryWords(question);
  final titles = {for (final m in library.modules()) m.id: m.title};
  final scored = <(int, SourceChunk)>[];
  for (final ref in refs.take(_maxCommentaryRefs)) {
    final first = ref.verseStart ?? 1;
    final last = ref.verseStart == null ? _wholeChapter : (ref.verseEnd ?? first);
    for (final e in library.forRange(ref.book.id, ref.chapter, first, last)) {
      final on = Ref(ref.book, e.chapter, e.verseStart, e.verseEnd);
      final title = '${titles[e.module] ?? e.module} on ${on.label}';
      for (final piece in _pieces(e.text)) {
        final chunk = SourceChunk(
          title: title,
          kind: SourceKind.commentary,
          ordinal: piece.ordinal,
          text: piece.text,
          ref: on,
        );
        scored.add((_overlap(words, piece.text), chunk));
      }
    }
  }
  // Stable: equal scores keep catalog and verse order.
  final ranked = [for (var i = 0; i < scored.length; i++) (i, scored[i])]
    ..sort((a, b) {
      final byScore = b.$2.$1.compareTo(a.$2.$1);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
  return [for (final r in ranked.take(limit)) r.$2.$2];
}

/// Questions rarely name more passages than this; each costs a query per pack.
const _maxCommentaryRefs = 3;

/// Larger than any chapter, so a chapter reference takes every verse comment.
const _wholeChapter = 999;

/// Words shorter than this ("the", "and", "was") say nothing about which piece fits.
const _minMatchWordChars = 4;

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

Set<String> _queryWords(String s) => {
  for (final m in _word.allMatches(s.toLowerCase()))
    if (m[0]!.length >= _minMatchWordChars) m[0]!,
};

int _overlap(Set<String> words, String text) {
  final have = _queryWords(text);
  return words.where(have.contains).length;
}

List<TextChunk> _pieces(String text) {
  try {
    return chunkSections([text]).chunks;
  } on FormatException {
    return const [];
  }
}

/// The verses commentary is retrieved for: those the question names, else the notebook's own
/// Bible passages, so commentary arrives only where it bears on what is being studied.
List<Ref> commentaryAnchors(String question, List<Ref> notebookPassages) {
  final asked = RefParser.parse(question);
  return asked.isNotEmpty ? asked : notebookPassages;
}

/// What a notebook answer may draw on, best first and each chunk once: sections of pinned
/// sources that match, then their starts (half the candidates at most), search hits across the
/// notebook, commentary on the passages in view, then the start of every source. The prompt
/// builder keeps as many as the tier's source budget allows.
List<SourceChunk> notebookSources({
  required NotebookIndex index,
  required String question,
  required Tier tier,
  Iterable<int> pinned = const [],
  CommentaryLibrary? commentary,
}) {
  final pins = pinned.toList();
  // Pins take at most half the candidates, so matches elsewhere in the notebook still arrive.
  final pinnedShare = (tier.sourceK + 1) ~/ 2;
  final pinnedChunks = pins.isEmpty
      ? const <SourceChunk>[]
      : _unique([
          ...index.search(question, limit: pinnedShare, within: pins),
          ...index.openings(limit: pinnedShare, within: pins),
        ]).take(pinnedShare);
  final candidates = [
    ...pinnedChunks,
    ...index.search(question, limit: tier.sourceK),
    if (commentary != null)
      ...commentaryChunks(
        commentary,
        question,
        commentaryAnchors(question, index.passages()),
        tier.commentaryK,
      ),
    ...index.openings(limit: tier.sourceK),
  ];
  return _unique(candidates);
}

List<SourceChunk> _unique(Iterable<SourceChunk> chunks) {
  final seen = <String>{};
  return [
    for (final c in chunks)
      if (seen.add(c.key)) c,
  ];
}
