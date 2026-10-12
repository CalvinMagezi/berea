import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';

import 'pdf_text.dart';
import 'study_store.dart';

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

/// A PDF or EPUB larger than this is refused before it is read.
const maxNotebookFileBytes = 64 * 1024 * 1024;

/// A PDF with more pages than this is refused; the text cap usually stops it sooner.
const maxPdfPages = 2000;

const maxSourcesPerNotebook = 100;
const maxNotebookTitleChars = 80;

/// Notebook tables in study.sqlite. Chunks are indexed for search by an external content FTS5
/// table that triggers keep in step, so restoring the chunk rows restores the index.
const notebookSchema = '''
  CREATE TABLE IF NOT EXISTS notebooks(id INTEGER PRIMARY KEY, title TEXT NOT NULL,
    created INTEGER, updated INTEGER);
  CREATE TABLE IF NOT EXISTS notebook_sources(id INTEGER PRIMARY KEY,
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

class Notebook {
  final int id;
  final String title;
  final DateTime updated;
  final int sourceCount;
  const Notebook(this.id, this.title, this.updated, this.sourceCount);
}

class NotebookSource {
  final int id;
  final int notebookId;
  final SourceKind kind;
  final String title;
  final String origin;
  final int chunkCount;
  const NotebookSource(
    this.id,
    this.notebookId,
    this.kind,
    this.title,
    this.origin,
    this.chunkCount,
  );
}

/// A searchable slice of a source, with what a citation needs: the source, the character range
/// in its text and, for a PDF, the page.
class NotebookChunk {
  final int id;
  final int sourceId;
  final String sourceTitle;
  final SourceKind kind;
  final int ordinal;
  final int start;
  final int end;
  final int? page;
  final String text;
  const NotebookChunk(
    this.id,
    this.sourceId,
    this.sourceTitle,
    this.kind,
    this.ordinal,
    this.start,
    this.end,
    this.page,
    this.text,
  );
}

/// What to add to a notebook. Plain values only, so it can be sent to a background isolate:
/// [text] for text kinds, [path] for PDF and EPUB files.
class SourceRequest {
  final SourceKind kind;
  final String title;
  final String origin;
  final String? text;
  final String? path;
  const SourceRequest(this.kind, this.title, {this.origin = '', this.text, this.path});
}

/// Extracts and chunks [r]. Runs in a background isolate; touches no database. [pdfiumPath]
/// overrides where PDFium is loaded from, for tests.
ChunkedText ingestSource(SourceRequest r, {String? pdfiumPath}) {
  switch (r.kind) {
    case SourceKind.pdf:
      final pages = pdfPageTexts(_checkedFile(r), maxPages: maxPdfPages, libraryPath: pdfiumPath);
      if (pages.every((p) => p.trim().isEmpty)) {
        throw const FormatException(
          'No text was found in that PDF. Scanned pages without a text layer are not read yet.',
        );
      }
      return chunkSections(pages, paged: true);
    case SourceKind.epub:
      return chunkSections(epubSections(File(_checkedFile(r)).readAsBytesSync()));
    case SourceKind.text || SourceKind.note || SourceKind.passage || SourceKind.commentary:
      return chunkSections([r.text ?? '']);
  }
}

String _checkedFile(SourceRequest r) {
  final path = r.path;
  if (path == null || !File(path).existsSync()) {
    throw const FormatException('That file could not be opened.');
  }
  if (File(path).lengthSync() > maxNotebookFileBytes) {
    throw const FormatException('That file is too large. The limit is 64 MB.');
  }
  return path;
}

/// Ingests [r] on a background isolate. Top level so the closure captures nothing but [r].
Future<ChunkedText> ingestInBackground(SourceRequest r) => Isolate.run(() => ingestSource(r));

/// A source being read, shown with a progress indicator until it is saved or fails.
class PendingSource {
  final int notebookId;
  final SourceKind kind;
  final String title;
  const PendingSource(this.notebookId, this.kind, this.title);
}

/// Notebooks, their sources and the chunks a later chat retrieves from. Lives in study.sqlite
/// beside the user's notes, so it is backed up and restored with them.
class NotebookStore {
  final Database db;
  final void Function() onChange;

  /// Reads a source; tests replace it to control timing.
  final Future<ChunkedText> Function(SourceRequest) ingest;

  /// Sources being read, in the order they were asked for. In memory only, so quitting
  /// mid-way leaves nothing half saved.
  final pending = <PendingSource>[];

  /// One ingestion at a time: PDFium is not thread safe, and it keeps memory use flat.
  Future<void> _queue = Future.value();

  NotebookStore(this.db, this.onChange, {this.ingest = ingestInBackground});

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  List<Notebook> notebooks() => [
    for (final r in db.select(
      'SELECT n.id, n.title, n.updated, COUNT(s.id) AS sources FROM notebooks n '
      'LEFT JOIN notebook_sources s ON s.notebook_id = n.id GROUP BY n.id ORDER BY n.updated DESC',
    ))
      Notebook(
        r['id'] as int,
        r['title'] as String,
        DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
        r['sources'] as int,
      ),
  ];

  Notebook? notebook(int id) => notebooks().where((n) => n.id == id).firstOrNull;

  static String _title(String title) {
    final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) throw const FormatException('Give the notebook a name.');
    return t.length > maxNotebookTitleChars ? t.substring(0, maxNotebookTitleChars) : t;
  }

  int createNotebook(String title) {
    db.execute('INSERT INTO notebooks(title, created, updated) VALUES (?, ?, ?)', [
      _title(title),
      _now(),
      _now(),
    ]);
    final id = db.lastInsertRowId;
    onChange();
    return id;
  }

  void renameNotebook(int id, String title) {
    db.execute('UPDATE notebooks SET title = ?, updated = ? WHERE id = ?', [
      _title(title),
      _now(),
      id,
    ]);
    onChange();
  }

  /// Removes the notebook with its sources and chunks in one transaction.
  void deleteNotebook(int id) {
    _transaction(() {
      db.execute(
        'DELETE FROM notebook_chunks WHERE source_id IN '
        '(SELECT id FROM notebook_sources WHERE notebook_id = ?)',
        [id],
      );
      db.execute('DELETE FROM notebook_sources WHERE notebook_id = ?', [id]);
      db.execute('DELETE FROM notebooks WHERE id = ?', [id]);
    });
    onChange();
  }

  List<NotebookSource> sources(int notebookId) => [
    for (final r in db.select(
      'SELECT s.id, s.notebook_id, s.kind, s.title, s.origin, '
      '(SELECT COUNT(*) FROM notebook_chunks c WHERE c.source_id = s.id) AS chunks '
      'FROM notebook_sources s WHERE s.notebook_id = ? ORDER BY s.created, s.id',
      [notebookId],
    ))
      NotebookSource(
        r['id'] as int,
        r['notebook_id'] as int,
        SourceKind.byName(r['kind'] as String) ?? SourceKind.text,
        r['title'] as String,
        r['origin'] as String,
        r['chunks'] as int,
      ),
  ];

  /// Reads [r] off the UI isolate, then saves it with its chunks in one transaction. Returns the
  /// new source id, or null when the notebook was deleted meanwhile. Throws [FormatException]
  /// with a message for the user when the source cannot be read.
  Future<int?> addSource(int notebookId, SourceRequest r) async {
    if (sources(notebookId).length + _pendingFor(notebookId) >= maxSourcesPerNotebook) {
      throw const FormatException('A notebook holds up to $maxSourcesPerNotebook sources.');
    }
    final job = PendingSource(notebookId, r.kind, r.title);
    pending.add(job);
    onChange();
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      await previous;
      final chunked = await ingest(r);
      return _save(notebookId, r, chunked);
    } finally {
      done.complete();
      pending.remove(job);
      onChange();
    }
  }

  int _pendingFor(int notebookId) => pending.where((p) => p.notebookId == notebookId).length;

  int? _save(int notebookId, SourceRequest r, ChunkedText chunked) {
    if (db.select('SELECT 1 FROM notebooks WHERE id = ?', [notebookId]).isEmpty) return null;
    late int sourceId;
    _transaction(() {
      db.execute(
        'INSERT INTO notebook_sources(notebook_id, kind, title, origin, text, created) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [notebookId, r.kind.name, r.title, r.origin, chunked.text, _now()],
      );
      sourceId = db.lastInsertRowId;
      final insert = db.prepare(
        'INSERT INTO notebook_chunks(source_id, ordinal, start_offset, end_offset, page, text) '
        'VALUES (?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final c in chunked.chunks) {
          insert.execute([sourceId, c.ordinal, c.start, c.end, c.page, c.text]);
        }
      } finally {
        insert.dispose();
      }
      db.execute('UPDATE notebooks SET updated = ? WHERE id = ?', [_now(), notebookId]);
    });
    return sourceId;
  }

  void removeSource(int sourceId) {
    _transaction(() {
      db.execute('DELETE FROM notebook_chunks WHERE source_id = ?', [sourceId]);
      db.execute('DELETE FROM notebook_sources WHERE id = ?', [sourceId]);
    });
    onChange();
  }

  /// The normalised text a source's chunk offsets point into.
  String sourceText(int sourceId) {
    final rows = db.select('SELECT text FROM notebook_sources WHERE id = ?', [sourceId]);
    return rows.isEmpty ? '' : rows.first['text'] as String;
  }

  static const _chunkColumns =
      'c.id, c.source_id, s.title, s.kind, c.ordinal, c.start_offset, c.end_offset, c.page, c.text';

  NotebookChunk _chunk(Row r) => NotebookChunk(
    r['id'] as int,
    r['source_id'] as int,
    r['title'] as String,
    SourceKind.byName(r['kind'] as String) ?? SourceKind.text,
    r['ordinal'] as int,
    r['start_offset'] as int,
    r['end_offset'] as int,
    r['page'] as int?,
    r['text'] as String,
  );

  /// Every chunk of a notebook's sources, source by source in the order they were added.
  List<NotebookChunk> chunks(int notebookId) => db
      .select(
        'SELECT $_chunkColumns FROM notebook_chunks c '
        'JOIN notebook_sources s ON s.id = c.source_id WHERE s.notebook_id = ? '
        'ORDER BY s.created, s.id, c.ordinal',
        [notebookId],
      )
      .map(_chunk)
      .toList();

  /// Chunks of [sourceId] in order.
  List<NotebookChunk> sourceChunks(int sourceId) => db
      .select(
        'SELECT $_chunkColumns FROM notebook_chunks c '
        'JOIN notebook_sources s ON s.id = c.source_id WHERE c.source_id = ? ORDER BY c.ordinal',
        [sourceId],
      )
      .map(_chunk)
      .toList();

  /// The chunks of a notebook that best match any word of [query], best first.
  List<NotebookChunk> search(int notebookId, String query, {int limit = 8}) {
    final q = notebookFtsQuery(query);
    if (q == null) return const [];
    return db
        .select(
          'SELECT $_chunkColumns FROM notebook_chunks_fts f '
          'JOIN notebook_chunks c ON c.id = f.rowid '
          'JOIN notebook_sources s ON s.id = c.source_id '
          'WHERE notebook_chunks_fts MATCH ? AND s.notebook_id = ? '
          'ORDER BY bm25(notebook_chunks_fts) LIMIT ?',
          [q, notebookId, limit],
        )
        .map(_chunk)
        .toList();
  }

  void _transaction(void Function() body) {
    db.execute('BEGIN');
    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

/// A note as a source: its reference, then what the user wrote.
SourceRequest noteSource(Note n) =>
    SourceRequest(SourceKind.note, 'Note on ${n.ref.label}', origin: n.ref.label, text: n.text);

/// The verses of [reference] in [translation], one per line with its number, or null when the
/// reference is not a passage in that translation.
SourceRequest? passageSource(BibleDb db, String reference, String translation) {
  final ref = RefParser.parse(reference).firstOrNull;
  if (ref == null) return null;
  final verses = db.passage(ref, translation: translation);
  if (verses.isEmpty) return null;
  return SourceRequest(
    SourceKind.passage,
    '${ref.label} ($translation)',
    origin: '${ref.label}|$translation',
    text: verses.map((v) => '${v.verse} ${v.text}').join('\n'),
  );
}

/// One source per installed commentary that comments on [reference], titled with the work so
/// each chunk keeps its attribution. Empty when the reference does not parse or none do.
List<SourceRequest> commentarySources(CommentaryLibrary library, String reference) {
  final ref = RefParser.parse(reference).firstOrNull;
  if (ref == null) return const [];
  final first = ref.verseStart ?? 1;
  final last = ref.verseStart == null ? _wholeChapter : (ref.verseEnd ?? first);
  final entries = library.forRange(ref.book.id, ref.chapter, first, last);
  final modules = {for (final m in library.modules()) m.id: m};
  final byModule = <String, List<CommentaryEntry>>{};
  for (final e in entries) {
    byModule.putIfAbsent(e.module, () => []).add(e);
  }
  return [
    for (final MapEntry(key: id, value: list) in byModule.entries)
      if (modules[id] case final m?)
        SourceRequest(
          SourceKind.commentary,
          '${m.title} on ${ref.label}',
          origin: '${m.id}|${m.author}|${m.licence}',
          text: list.map((e) => e.text).join('\n\n'),
        ),
  ];
}

/// Larger than any chapter, so a chapter reference takes every verse comment.
const _wholeChapter = 999;
