import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'pdf_text.dart';
import 'study_store.dart';

export 'package:berea_harness/berea_harness.dart' show SourceKind, notebookSchema;

/// A PDF or EPUB larger than this is refused before it is read.
const maxNotebookFileBytes = 64 * 1024 * 1024;

/// A PDF with more pages than this is refused; the text cap usually stops it sooner.
const maxPdfPages = 2000;

const maxSourcesPerNotebook = 100;

/// About what fits a small model's prompt beside the question.
const notebookSearchLimit = 8;
const maxNotebookTitleChars = 80;

/// Study store migration 1: pins, and one conversation per notebook. The answer's verse
/// references and cited source chunks are JSON lists beside its text.
const notebookChatSchema = '''
  ALTER TABLE notebook_sources ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;
  CREATE TABLE IF NOT EXISTS notebook_messages(id INTEGER PRIMARY KEY AUTOINCREMENT,
    notebook_id INTEGER NOT NULL, role TEXT NOT NULL, text TEXT NOT NULL,
    refs TEXT NOT NULL DEFAULT '[]', sources TEXT NOT NULL DEFAULT '[]', created INTEGER);
  CREATE INDEX IF NOT EXISTS notebook_messages_notebook ON notebook_messages(notebook_id, id);
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

  /// Pinned sources are offered to every answer in the notebook's chat, not only when they match.
  final bool pinned;

  /// The note a note source links to; null for other kinds, and for a copy whose note is gone.
  final int? noteId;
  const NotebookSource(
    this.id,
    this.notebookId,
    this.kind,
    this.title,
    this.origin,
    this.chunkCount, {
    this.pinned = false,
    this.noteId,
  });
}

/// One message of a notebook's conversation. An answer keeps the verse references and source
/// chunks it cited, so its chips still open them after the app restarts.
class NotebookMessage {
  final String role;
  final String text;
  final List<Ref> refs;
  final List<ShownSource> sources;
  const NotebookMessage(this.role, this.text, this.refs, this.sources);
  bool get isUser => role == 'user';
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

  /// For a note source, the note it links to.
  final int? noteId;
  const SourceRequest(this.kind, this.title, {this.origin = '', this.text, this.path, this.noteId});
}

/// Extracts and chunks [r]. Runs in a background isolate; touches no database. [pdfiumPath]
/// overrides where PDFium is loaded from, for tests.
ChunkedText ingestSource(SourceRequest r, {String? pdfiumPath}) {
  switch (r.kind) {
    case SourceKind.pdf:
      final pages = pdfPageTexts(
        _checkedFile(r),
        maxPages: maxPdfPages,
        maxChars: maxNotebookSourceChars,
        libraryPath: pdfiumPath,
      );
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

/// A source still being read after this long is abandoned and its isolate killed, so one
/// hostile file cannot hold up every source queued behind it.
const ingestTimeout = Duration(minutes: 5);

class _IngestFailure {
  final String message;
  const _IngestFailure(this.message);
}

/// Background isolate entry point; it receives only the request and a port.
void _ingestEntry((SourceRequest, SendPort) args) {
  final (r, port) = args;
  Object result;
  try {
    result = ingestSource(r);
  } on FormatException catch (e) {
    result = _IngestFailure(e.message);
  }
  Isolate.exit(port, result);
}

const _timedOut = Object();

Future<void> _lastExit = Future.value();

/// Completes when the last reader has left native code; a killed isolate waits for PDFium.
Future<void> ingestIdle() => _lastExit;

/// Reads [r] on a background isolate that is killed if it outlives [timeout]. Throws
/// [FormatException] for problems the user can act on, [StateError] for anything else.
Future<ChunkedText> ingestInBackground(SourceRequest r, {Duration timeout = ingestTimeout}) async {
  final port = ReceivePort();
  final result = Completer<Object?>();
  final exited = Completer<void>();
  _lastExit = exited.future;
  // The result or an error arrives first; null arrives when the isolate has exited.
  port.listen((m) {
    if (!result.isCompleted) result.complete(m);
    if (m != null || exited.isCompleted) return;
    exited.complete();
    port.close();
  });
  final Isolate isolate;
  try {
    isolate = await Isolate.spawn(
      _ingestEntry,
      (r, port.sendPort),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
  } catch (_) {
    port.close();
    exited.complete();
    rethrow;
  }
  final message = await result.future.timeout(timeout, onTimeout: () => _timedOut);
  if (identical(message, _timedOut)) {
    isolate.kill(priority: Isolate.immediate);
    throw const FormatException('That source took too long to read.');
  }
  return switch (message) {
    final ChunkedText c => c,
    final _IngestFailure f => throw FormatException(f.message),
    _ => throw StateError('Reading stopped: $message'),
  };
}

/// A source being read, shown with a progress indicator until it is saved or fails.
class PendingSource {
  final int notebookId;
  final SourceKind kind;
  final String title;

  /// Set when its notebook is deleted or a backup replaces the notebooks; nothing is saved.
  bool cancelled = false;
  PendingSource(this.notebookId, this.kind, this.title);
}

/// Notebooks, their sources and the chunks a later chat retrieves from. Lives in study.sqlite
/// beside the user's notes, so it is backed up and restored with them. Notifies its own
/// listeners, so notebook screens do not rebuild on every streamed chat token.
class NotebookStore extends ChangeNotifier {
  final Database db;

  /// Reads a source; tests replace it to control timing.
  final Future<ChunkedText> Function(SourceRequest) ingest;

  /// Sources being read, in the order they were asked for. In memory only, so quitting
  /// mid-way leaves nothing half saved.
  final pending = <PendingSource>[];

  /// One ingestion at a time: PDFium is not thread safe, and it keeps memory use flat.
  Future<void> _queue = Future.value();

  /// Completes when the reading isolate has really exited; tests replace it.
  final Future<void> Function() idle;

  NotebookStore(this.db, {this.ingest = ingestInBackground, this.idle = ingestIdle});

  void _changed() => notifyListeners();

  /// For writes made through [StudyStore] that can add a notebook, such as the first note on a
  /// verse creating the notes on verses notebook.
  void refresh() => _changed();

  /// Sources still being read for [notebookId].
  List<PendingSource> pendingFor(int notebookId) =>
      pending.where((p) => p.notebookId == notebookId && !p.cancelled).toList();

  /// Counts the times the notebook tables were replaced underneath (a restore), so an answer
  /// written across one is not saved into a notebook that may now be another.
  int epoch = 0;

  /// Drops every source being read. Call after the notebook tables are replaced underneath.
  void cancelAll() {
    for (final p in pending) {
      p.cancelled = true;
    }
    epoch++;
    _changed();
  }

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
    _changed();
    return id;
  }

  void renameNotebook(int id, String title) {
    db.execute('UPDATE notebooks SET title = ?, updated = ? WHERE id = ?', [
      _title(title),
      _now(),
      id,
    ]);
    _changed();
  }

  /// Removes the notebook with its sources and chunks in one transaction. Its notes and study
  /// pages move to the notes on verses notebook and its conversations to the Bible, so
  /// deleting a notebook never deletes what the user wrote.
  /// Word studies Study notebook added to notebook [id] that the reader has not changed.
  int addedWords(int id) =>
      db.select('SELECT COUNT(*) AS n FROM notes WHERE notebook_id = ? AND kind = ?', [
            id,
            studyWordKind,
          ]).first['n']
          as int;

  /// Whether [id] is the notes on verses notebook, where a deleted notebook's notes go.
  bool isNotesOnVerses(int id) => db
      .select('SELECT 1 FROM notebooks WHERE id = ? AND system_key = ?', [id, notesOnVersesKey])
      .isNotEmpty;

  /// Notes and study pages in notebook [id]: what a delete moves, or for the notes on verses
  /// notebook, deletes.
  int writtenIn(int id) =>
      db.select(
            'SELECT (SELECT COUNT(*) FROM notes WHERE notebook_id = ?) + '
            '(SELECT COUNT(*) FROM study_pages WHERE notebook_id = ?) AS n',
            [id, id],
          ).first['n']
          as int;

  void deleteNotebook(int id) {
    for (final p in pending.where((p) => p.notebookId == id)) {
      p.cancelled = true;
    }
    _transaction(() {
      // What Study notebook added is the notebook's, not the reader's, so it goes with it.
      db.execute('DELETE FROM notes WHERE notebook_id = ? AND kind = ?', [id, studyWordKind]);
      // The notes on verses notebook is where notes go; moving them would only make it again.
      if (isNotesOnVerses(id)) {
        db.execute('DELETE FROM notes WHERE notebook_id = ?', [id]);
        db.execute('DELETE FROM study_pages WHERE notebook_id = ?', [id]);
      }
      final holds = db.select(
        'SELECT 1 FROM notes WHERE notebook_id = ? UNION ALL '
        'SELECT 1 FROM study_pages WHERE notebook_id = ? LIMIT 1',
        [id, id],
      );
      if (holds.isNotEmpty) {
        final home = StudyStore.notesOnVersesNotebook(db, except: id);
        db.execute('UPDATE notes SET notebook_id = ? WHERE notebook_id = ?', [home, id]);
        db.execute('UPDATE study_pages SET notebook_id = ? WHERE notebook_id = ?', [home, id]);
      }
      db.execute('UPDATE conversations SET notebook_id = NULL WHERE notebook_id = ?', [id]);
      db.execute(
        'DELETE FROM notebook_chunks WHERE source_id IN '
        '(SELECT id FROM notebook_sources WHERE notebook_id = ?)',
        [id],
      );
      db.execute('DELETE FROM notebook_sources WHERE notebook_id = ?', [id]);
      db.execute('DELETE FROM notebook_messages WHERE notebook_id = ?', [id]);
      db.execute('DELETE FROM notebooks WHERE id = ?', [id]);
    });
    _changed();
  }

  List<NotebookSource> sources(int notebookId) => [
    for (final r in db.select(
      'SELECT s.id, s.notebook_id, s.kind, s.title, s.origin, s.pinned, s.note_id, '
      '(SELECT COUNT(*) FROM notebook_chunks c WHERE c.source_id = s.id) AS chunks '
      'FROM notebook_sources s WHERE s.notebook_id = ? ORDER BY s.created, s.id',
      [notebookId],
    ))
      _source(r),
  ];

  static NotebookSource _source(Row r) => NotebookSource(
    r['id'] as int,
    r['notebook_id'] as int,
    SourceKind.byName(r['kind'] as String) ?? SourceKind.text,
    r['title'] as String,
    r['origin'] as String,
    r['chunks'] as int,
    pinned: r['pinned'] == 1,
    noteId: r['note_id'] as int?,
  );

  /// The source with [id], or null when it has been removed.
  NotebookSource? source(int id) {
    final rows = db.select(
      'SELECT s.id, s.notebook_id, s.kind, s.title, s.origin, s.pinned, s.note_id, '
      '(SELECT COUNT(*) FROM notebook_chunks c WHERE c.source_id = s.id) AS chunks '
      'FROM notebook_sources s WHERE s.id = ?',
      [id],
    );
    return rows.isEmpty ? null : _source(rows.first);
  }

  void setPinned(int sourceId, bool pinned) {
    db.execute('UPDATE notebook_sources SET pinned = ? WHERE id = ?', [pinned ? 1 : 0, sourceId]);
    _changed();
  }

  /// Ids of the notebook's pinned sources.
  List<int> pinnedSources(int notebookId) => [
    for (final r in db.select(
      'SELECT id FROM notebook_sources WHERE notebook_id = ? AND pinned = 1 ORDER BY created, id',
      [notebookId],
    ))
      r['id'] as int,
  ];

  /// Returns the new source id, or null when its notebook went away while it was read.
  Future<int?> addSource(int notebookId, SourceRequest r) async {
    if (sources(notebookId).length + pendingFor(notebookId).length >= maxSourcesPerNotebook) {
      throw const FormatException('A notebook holds up to $maxSourcesPerNotebook sources.');
    }
    final job = PendingSource(notebookId, r.kind, r.title);
    pending.add(job);
    _changed();
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      await previous;
      if (job.cancelled) return null;
      final chunked = await ingest(r);
      return job.cancelled ? null : _save(notebookId, r, chunked);
    } finally {
      pending.remove(job);
      _changed();
      // The next source waits until this one's isolate has left PDFium, even after a timeout.
      unawaited(idle().then((_) => done.complete()));
    }
  }

  int? _save(int notebookId, SourceRequest r, ChunkedText chunked) {
    if (db.select('SELECT 1 FROM notebooks WHERE id = ?', [notebookId]).isEmpty) return null;
    // A note deleted while it was read leaves a copy, as deleting a linked note does.
    final noteId =
        r.noteId != null && db.select('SELECT 1 FROM notes WHERE id = ?', [r.noteId]).isNotEmpty
        ? r.noteId
        : null;
    late int sourceId;
    _transaction(() {
      db.execute(
        'INSERT INTO notebook_sources(notebook_id, kind, title, origin, text, note_id, created) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [notebookId, r.kind.name, r.title, r.origin, chunked.text, noteId, _now()],
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
    _changed();
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
  List<SourceChunk> search(int notebookId, String query, {int limit = notebookSearchLimit}) =>
      NotebookIndex(db, notebookId).search(query, limit: limit);

  /// The notebook's conversation, oldest first.
  List<NotebookMessage> messages(int notebookId) => [
    for (final r in db.select(
      'SELECT role, text, refs, sources FROM notebook_messages WHERE notebook_id = ? ORDER BY id',
      [notebookId],
    ))
      NotebookMessage(r['role'] as String, r['text'] as String, _refs(r['refs'] as String), [
        for (final s in jsonDecode(r['sources'] as String) as List) ?ShownSource.fromJson(s),
      ]),
  ];

  static List<Ref> _refs(String json) => [
    for (final label in (jsonDecode(json) as List).whereType<String>()) ...RefParser.parse(label),
  ];

  /// Appends to the conversation; false, saving nothing, when the notebook has gone.
  bool addMessage(
    int notebookId,
    String role,
    String text, {
    List<Ref> refs = const [],
    List<ShownSource> sources = const [],
  }) {
    if (db.select('SELECT 1 FROM notebooks WHERE id = ?', [notebookId]).isEmpty) return false;
    db.execute(
      'INSERT INTO notebook_messages(notebook_id, role, text, refs, sources, created) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        notebookId,
        role,
        text,
        jsonEncode([for (final r in refs) r.label]),
        jsonEncode([for (final s in sources) s.toJson()]),
        _now(),
      ],
    );
    return true;
  }

  /// A question and its answer, saved together or not at all.
  void addExchange(
    int notebookId,
    String question,
    String answer,
    List<Ref> refs,
    List<ShownSource> sources,
  ) => _transaction(() {
    if (!addMessage(notebookId, 'user', question)) return;
    addMessage(notebookId, 'assistant', answer, refs: refs, sources: sources);
  });

  void clearMessages(int notebookId) {
    db.execute('DELETE FROM notebook_messages WHERE notebook_id = ?', [notebookId]);
    _changed();
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

/// A note as a source: a link to the note, which keeps the source in step when it is edited.
SourceRequest noteSource(Note n) => SourceRequest(
  SourceKind.note,
  noteSourceTitle(n),
  origin: n.verse?.label ?? '',
  text: n.text,
  noteId: n.id,
);

/// The verses of [reference] in [translation], one per line with its number, or null when the
/// reference is not a passage in that translation.
SourceRequest? passageSource(BibleDb db, String reference, String translation) {
  final ref = RefParser.parse(reference).firstOrNull;
  if (ref == null) return null;
  final verses = db.verses(ref, translation: translation);
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
