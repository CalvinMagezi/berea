import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';

import 'notebook_store.dart';
import 'plans.dart';
import 'prayer_plan_store.dart';
import 'prayer_store.dart';

/// Everything the user writes: notes, highlights and saved studies. One local SQLite file,
/// never synced, never sent anywhere.
class Note {
  final int id;

  /// Null for a note that is not on a verse, such as sermon notes.
  final Ref? verse;
  final String text;
  final DateTime updated;
  final int? notebookId;
  final String title;

  /// [plainNoteKind] for what the reader wrote, [keptWordKind] for a word kept from a word study.
  final String kind;
  const Note(
    this.id,
    this.verse,
    this.text,
    this.updated, {
    this.notebookId,
    this.title = '',
    this.kind = plainNoteKind,
  });

  bool get isKeptWord => kind == keptWordKind;

  /// The verse of a verse note. [StudyStore.notes] returns only verse notes.
  Ref get ref => verse!;
}

class StudyPageRecord {
  final int id;
  final Ref ref;
  final String observation;
  final String interpretation;
  final String application;
  final DateTime updated;
  final int? notebookId;
  const StudyPageRecord(
    this.id,
    this.ref,
    this.observation,
    this.interpretation,
    this.application,
    this.updated, {
    this.notebookId,
  });
}

/// A saved question and its answers. Scoped to a notebook, or to the Bible when [notebookId]
/// is null; the Bible's are the past questions in Study.
class Conversation {
  final int id;
  final String title;
  final DateTime updated;
  final int messageCount;
  final int? notebookId;
  const Conversation(this.id, this.title, this.updated, this.messageCount, {this.notebookId});
}

class SavedMessage {
  final String role;
  final String text;
  final List<Ref> refs;

  /// Notebook source chunks the answer cited.
  final List<ShownSource> sources;
  const SavedMessage(this.role, this.text, this.refs, {this.sources = const []});
  bool get isUser => role == 'user';
}

const maxTitleChars = 60;

/// Where verse notes, and study pages whose passage no notebook holds, are kept.
const notesOnVersesTitle = 'Notes on verses';

/// Finds the notes on verses notebook whatever the reader renames it to, in any language.
const notesOnVersesKey = 'verse_notes';

const plainNoteKind = 'note';
const keptWordKind = 'word';

/// Study store migration 5: the notes on verses notebook carries a key, so it is found by key
/// rather than by its title, and a note says whether it is a kept word.
const notebookKeySchema = '''
  ALTER TABLE notebooks ADD COLUMN system_key TEXT;
  CREATE UNIQUE INDEX IF NOT EXISTS notebooks_system_key ON notebooks(system_key);
  ALTER TABLE notes ADD COLUMN kind TEXT NOT NULL DEFAULT 'note';
''';

/// How word study bodies marked a kept word before notes had a kind: an optional meaning line,
/// then the Strong's line that keptWordBody writes.
final _legacyKeptWord = RegExp("^(?:[^\\n]*\\n)?Strong's [GH]\\d+(?: · |\$|\\n)");

/// Study store migration 2: notes and study pages belong to notebooks, a note need not be on a
/// verse, a note source links to its note, and conversations are scoped to the Bible (null) or
/// a notebook. [StudyStore.mergeNotes] then moves the rows.
const notesMergeSchema = '''
  ALTER TABLE notes ADD COLUMN notebook_id INTEGER;
  ALTER TABLE notes ADD COLUMN title TEXT NOT NULL DEFAULT '';
  CREATE INDEX IF NOT EXISTS notes_notebook ON notes(notebook_id);
  ALTER TABLE study_pages ADD COLUMN notebook_id INTEGER;
  ALTER TABLE conversations ADD COLUMN notebook_id INTEGER;
  ALTER TABLE messages ADD COLUMN sources TEXT NOT NULL DEFAULT '[]';
  ALTER TABLE messages ADD COLUMN notebook_message_id INTEGER;
  ALTER TABLE notebook_sources ADD COLUMN note_id INTEGER;
''';

/// Study store migration 4: plans tick chapters, not days. [StudyStore.carryPlanDays] then
/// ticks every chapter of each day already ticked.
const planChaptersSchema = '''
  CREATE TABLE IF NOT EXISTS plan_chapters(plan_id TEXT, book INTEGER, chapter INTEGER,
    done_at INTEGER, PRIMARY KEY(plan_id, book, chapter)) WITHOUT ROWID;
''';

/// The copy of study.sqlite written before the notes merge, beside the database.
const preNotesMergeSuffix = '.pre-notes-merge';

class StudyStore {
  final Database db;
  StudyStore(this.db) {
    db.execute('''
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS notes(
        id INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER, verse_start INTEGER, verse_end INTEGER,
        text TEXT, created INTEGER, updated INTEGER);
      CREATE INDEX IF NOT EXISTS notes_ref ON notes(book, chapter);
      CREATE TABLE IF NOT EXISTS highlights(book INTEGER, chapter INTEGER, verse INTEGER,
        PRIMARY KEY(book, chapter, verse)) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS conversations(id INTEGER PRIMARY KEY, title TEXT, created INTEGER, updated INTEGER);
      CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY, conversation_id INTEGER, role TEXT,
        text TEXT, refs TEXT, created INTEGER);
      CREATE INDEX IF NOT EXISTS messages_conv ON messages(conversation_id);
      CREATE TABLE IF NOT EXISTS plan_progress(plan_id TEXT, day INTEGER, done_at INTEGER,
        PRIMARY KEY(plan_id, day)) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS study_pages(id INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER,
        verse_start INTEGER, verse_end INTEGER, observation TEXT, interpretation TEXT,
        application TEXT, created INTEGER, updated INTEGER);
    ''');
    _migrate();
  }

  /// Schema changes after 0.3.0, applied in order and recorded in `user_version`. The tables
  /// above predate it and stay `IF NOT EXISTS`.
  /// Append only: a migration that has shipped is never edited, since installs that ran it
  /// would differ from new ones. Change the schema with a new entry; a test pins each text.
  static const migrations = [
    notebookSchema,
    notebookChatSchema,
    notesMergeSchema,
    prayerSchema,
    planChaptersSchema,
    notebookKeySchema,
    prayerPlanSchema,
  ];

  static int get schemaVersion => migrations.length;

  /// Data moves SQL cannot make, run after the migration at the same index, in its transaction.
  static final _dataSteps = <int, void Function(StudyStore)>{
    _notesMergeIndex: (s) => s.mergeNotes(),
    _planChaptersIndex: (s) => s.carryPlanDays(),
    _notebookKeyIndex: (s) => s.keyNotebooksAndWords(),
  };

  static const _notesMergeIndex = 2;
  static const _planChaptersIndex = 4;
  static const _notebookKeyIndex = 5;

  /// A file from a newer Berea (a downgrade) is opened as it is: later migrations only add
  /// tables, and columns with defaults. Not across the notes merge: 0.6.0 cannot read a note
  /// without a verse, and notes it writes after a downgrade get no notebook.
  void _migrate() {
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version <= _notesMergeIndex) _backUpBeforeNotesMerge();
    for (var v = version; v < migrations.length; v++) {
      _transaction(() {
        db.execute(migrations[v]);
        _dataSteps[v]?.call(this);
        db.execute('PRAGMA user_version = ${v + 1}');
      });
    }
  }

  /// Writes a plain copy of a file database that holds user data, beside it, before the notes
  /// merge moves anything. Throws, so nothing migrates, when the copy cannot be written. An
  /// existing copy is kept: it was written before any merge, since a failed merge rolls back.
  void _backUpBeforeNotesMerge() {
    final main = db.select('PRAGMA database_list').where((r) => r['name'] == 'main');
    final file = main.isEmpty ? '' : (main.first['file'] as String? ?? '');
    // An in-memory database has no file and nothing to lose across a restart.
    if (file.isEmpty) return;
    final path = '$file$preNotesMergeSuffix';
    if (File(path).existsSync() || !_hasUserData()) return;
    // Written aside and renamed, so a copy cut short is never taken for a whole one.
    final partial = File('$path.partial');
    if (partial.existsSync()) partial.deleteSync();
    db.execute('VACUUM INTO ?', [partial.path]);
    partial.renameSync(path);
  }

  bool _hasUserData() {
    final tables = {
      for (final r in db.select("SELECT name FROM sqlite_master WHERE type = 'table'")) r['name'],
    };
    return userTables
        .where(tables.contains)
        .any((t) => db.select('SELECT 1 FROM $t LIMIT 1').isNotEmpty);
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

  /// Gives every note and study page without a notebook one, links copied note sources to
  /// their note, and copies notebook conversations into scoped ones. Only touches rows not yet
  /// merged, so it runs again safely after a restore of an older backup.
  void mergeNotes() {
    int? home;
    int homeId() => home ??= notesOnVersesNotebook(db);
    if (db.select('SELECT 1 FROM notes WHERE notebook_id IS NULL LIMIT 1').isNotEmpty) {
      db.execute('UPDATE notes SET notebook_id = ? WHERE notebook_id IS NULL', [homeId()]);
    }
    for (final r in db.select('SELECT * FROM study_pages WHERE notebook_id IS NULL')) {
      final notebook = notebookForPassage(_pageRef(r)) ?? homeId();
      db.execute('UPDATE study_pages SET notebook_id = ? WHERE id = ?', [notebook, r['id']]);
    }
    _linkNoteSources();
    _copyNotebookChats();
  }

  /// The id of the notes on verses notebook, created when there is none. [except] skips a
  /// notebook about to be deleted, which gives up the key.
  static int notesOnVersesNotebook(Database db, {int? except}) {
    // The notes merge (migration 2) runs before the key exists (migration 5).
    if (!_hasNotebookKey(db)) return _notesOnVersesByTitle(db, except);
    if (except != null) {
      db.execute('UPDATE notebooks SET system_key = NULL WHERE id = ?', [except]);
    }
    final rows = db.select('SELECT id FROM notebooks WHERE system_key = ?', [notesOnVersesKey]);
    if (rows.isNotEmpty) return rows.first['id'] as int;
    db.execute('INSERT INTO notebooks(title, created, updated, system_key) VALUES (?, ?, ?, ?)', [
      notesOnVersesTitle,
      _now(),
      _now(),
      notesOnVersesKey,
    ]);
    return db.lastInsertRowId;
  }

  static int _notesOnVersesByTitle(Database db, int? except) {
    final rows = db.select(
      'SELECT id FROM notebooks WHERE title = ? AND id IS NOT ? ORDER BY id LIMIT 1',
      [notesOnVersesTitle, except],
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    db.execute('INSERT INTO notebooks(title, created, updated) VALUES (?, ?, ?)', [
      notesOnVersesTitle,
      _now(),
      _now(),
    ]);
    return db.lastInsertRowId;
  }

  static bool _hasNotebookKey(Database db) => db
      .select("SELECT 1 FROM pragma_table_info('notebooks') WHERE name = 'system_key'")
      .isNotEmpty;

  /// The id of the notes on verses notebook, or null while there is none.
  static int? notesOnVersesId(Database db) =>
      db.select('SELECT id FROM notebooks WHERE system_key = ?', [
            notesOnVersesKey,
          ]).firstOrNull?['id']
          as int?;

  /// Keys the notes on verses notebook made before keys existed (by migration 5, or restored
  /// from an older backup), and marks kept words saved before notes had a kind.
  void keyNotebooksAndWords() {
    _keyNotesOnVerses();
    _markLegacyKeptWords();
  }

  void _keyNotesOnVerses() {
    if (notesOnVersesId(db) == null) {
      db.execute(
        'UPDATE notebooks SET system_key = ? WHERE id = '
        '(SELECT id FROM notebooks WHERE title = ? ORDER BY id LIMIT 1)',
        [notesOnVersesKey, notesOnVersesTitle],
      );
    }
  }

  void _markLegacyKeptWords() {
    for (final r in db.select("SELECT id, text FROM notes WHERE kind = 'note'")) {
      if (_legacyKeptWord.hasMatch(r['text'] as String)) {
        db.execute('UPDATE notes SET kind = ? WHERE id = ?', [keptWordKind, r['id']]);
      }
    }
  }

  /// The notebook with a passage source for exactly [ref], else one whose passage contains it;
  /// the oldest notebook wins a tie. Null when no notebook holds it.
  int? notebookForPassage(Ref ref) {
    final vs = ref.verseStart ?? 1;
    final ve = ref.verseEnd ?? vs;
    int? containing;
    for (final r in db.select(
      "SELECT notebook_id, origin FROM notebook_sources WHERE kind = 'passage' ORDER BY notebook_id, id",
    )) {
      final held = RefParser.parse((r['origin'] as String).split('|').first).firstOrNull;
      if (held == null || held.book.id != ref.book.id || held.chapter != ref.chapter) continue;
      final hs = held.verseStart ?? 1;
      final he = held.verseStart == null ? _wholeChapter : (held.verseEnd ?? hs);
      if (held.verseStart != null && hs == vs && he == ve) return r['notebook_id'] as int;
      if (hs <= vs && ve <= he) containing ??= r['notebook_id'] as int;
    }
    return containing;
  }

  /// A copied note source becomes a link when a note still has its verse and exactly its
  /// text. One whose note was edited or deleted since stays a copy, so nothing is lost.
  void _linkNoteSources() {
    final sources = db.select(
      "SELECT id, origin, text FROM notebook_sources WHERE kind = 'note' AND note_id IS NULL",
    );
    if (sources.isEmpty) return;
    final byContent = <(String, String), int>{};
    for (final n in db.select('SELECT * FROM notes ORDER BY id')) {
      final note = _note(n);
      final ChunkedText chunked;
      try {
        chunked = chunkSections([note.text]);
      } on FormatException {
        continue;
      }
      byContent.putIfAbsent((note.verse?.label ?? '', chunked.text), () => note.id);
    }
    for (final s in sources) {
      final note = byContent[(s['origin'] as String, s['text'] as String)];
      if (note == null) continue;
      db.execute('UPDATE notebook_sources SET note_id = ? WHERE id = ?', [note, s['id']]);
    }
  }

  /// Copies notebook conversation messages not yet copied into one conversation per notebook.
  /// The notebook tables keep theirs until the notebook chat screen is retired.
  void _copyNotebookChats() {
    final pending = db.select(
      'SELECT * FROM notebook_messages n WHERE notebook_id IN (SELECT id FROM notebooks) '
      'AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.notebook_message_id = n.id) ORDER BY id',
    );
    final conversationOf = <int, int>{};
    for (final m in pending) {
      final notebook = m['notebook_id'] as int;
      final conversation = conversationOf[notebook] ??= _notebookConversation(notebook, m);
      db.execute(
        'INSERT INTO messages(conversation_id, role, text, refs, sources, notebook_message_id, '
        'created) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [conversation, m['role'], m['text'], m['refs'], m['sources'], m['id'], m['created']],
      );
      final at = m['created'] as int? ?? _now();
      db.execute('UPDATE conversations SET updated = MAX(updated, ?) WHERE id = ?', [
        at,
        conversation,
      ]);
    }
  }

  /// The conversation earlier copies of [notebook]'s messages went to, or a new one titled by
  /// [first], the oldest message not yet copied.
  int _notebookConversation(int notebook, Row first) {
    final earlier = db.select(
      'SELECT m.conversation_id FROM messages m JOIN notebook_messages n '
      'ON n.id = m.notebook_message_id JOIN conversations c ON c.id = m.conversation_id '
      'WHERE n.notebook_id = ? ORDER BY m.id LIMIT 1',
      [notebook],
    );
    if (earlier.isNotEmpty) return earlier.first['conversation_id'] as int;
    final at = first['created'] as int? ?? _now();
    db.execute(
      'INSERT INTO conversations(title, created, updated, notebook_id) VALUES (?, ?, ?, ?)',
      [_conversationTitle(first['text'] as String), at, at, notebook],
    );
    return db.lastInsertRowId;
  }

  /// Copies notebook conversation messages saved since the last copy. For the move off the
  /// notebook chat screen, which until then saves to its own table.
  void copyNotebookChats() => _transaction(_copyNotebookChats);

  factory StudyStore.open(String path) => StudyStore(sqlite3.open(path));

  void close() => db.dispose();

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Note _note(Row r) => Note(
    r['id'] as int,
    r['book'] == null ? null : _pageRef(r),
    r['text'] as String,
    DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
    notebookId: r['notebook_id'] as int?,
    title: r['title'] as String,
    kind: r['kind'] as String? ?? plainNoteKind,
  );

  static Ref _pageRef(Row r) => Ref(
    bookById(r['book'] as int),
    r['chapter'] as int,
    r['verse_start'] as int,
    r['verse_end'] as int,
  );

  /// Notes on verses, from every notebook. Notes without a verse are in [notebookNotes].
  List<Note> notes({Book? book, int? chapter}) {
    final rows = book == null
        ? db.select('SELECT * FROM notes WHERE book IS NOT NULL ORDER BY updated DESC')
        : chapter == null
        ? db.select('SELECT * FROM notes WHERE book = ? ORDER BY chapter, verse_start', [book.id])
        : db.select('SELECT * FROM notes WHERE book = ? AND chapter = ? ORDER BY verse_start', [
            book.id,
            chapter,
          ]);
    return rows.map(_note).toList();
  }

  /// Every note in [notebookId], with or without a verse, newest first.
  List<Note> notebookNotes(int notebookId) => db
      .select('SELECT * FROM notes WHERE notebook_id = ? ORDER BY updated DESC', [notebookId])
      .map(_note)
      .toList();

  Note? note(int id) {
    final rows = db.select('SELECT * FROM notes WHERE id = ?', [id]);
    return rows.isEmpty ? null : _note(rows.first);
  }

  /// A note on [ref], kept in the notes on verses notebook.
  int addNote(Ref ref, String text) => addNotebookNote(notesOnVersesNotebook(db), text, verse: ref);

  int addNotebookNote(
    int notebookId,
    String text, {
    Ref? verse,
    String title = '',
    String kind = plainNoteKind,
  }) {
    final (book, chapter, vs, ve) = _verseColumns(verse);
    db.execute(
      'INSERT INTO notes(book, chapter, verse_start, verse_end, text, title, notebook_id, kind, '
      'created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [book, chapter, vs, ve, text, title, notebookId, kind, _now(), _now()],
    );
    return db.lastInsertRowId;
  }

  static (int?, int?, int?, int?) _verseColumns(Ref? verse) {
    if (verse == null) return (null, null, null, null);
    final vs = verse.verseStart ?? 1;
    return (verse.book.id, verse.chapter, vs, verse.verseEnd ?? vs);
  }

  void updateNote(int id, String text) => _transaction(() {
    db.execute('UPDATE notes SET text = ?, updated = ? WHERE id = ?', [text, _now(), id]);
    _syncNoteSources(id);
  });

  /// Replaces everything about note [id]: what the note editor saves.
  void saveNote(
    int id, {
    required int notebookId,
    required String text,
    String title = '',
    Ref? verse,
  }) => _transaction(() {
    final (book, chapter, vs, ve) = _verseColumns(verse);
    db.execute(
      'UPDATE notes SET book = ?, chapter = ?, verse_start = ?, verse_end = ?, text = ?, '
      'title = ?, notebook_id = ?, updated = ? WHERE id = ?',
      [book, chapter, vs, ve, text, title, notebookId, _now(), id],
    );
    _syncNoteSources(id);
  });

  /// A note source is a link: it shows the note as it is now. Its chunks are rewritten so
  /// notebook search finds the edited text.
  void _syncNoteSources(int noteId) {
    final note = this.note(noteId);
    final linked = db.select('SELECT id FROM notebook_sources WHERE note_id = ?', [noteId]);
    if (note == null || linked.isEmpty) return;
    final ChunkedText chunked;
    try {
      chunked = chunkSections([note.text]);
    } on FormatException {
      // A blank note still saves; its sources keep the last text until it has some again.
      return;
    }
    for (final s in linked) {
      final id = s['id'] as int;
      db.execute('UPDATE notebook_sources SET title = ?, origin = ?, text = ? WHERE id = ?', [
        noteSourceTitle(note),
        note.verse?.label ?? '',
        chunked.text,
        id,
      ]);
      db.execute('DELETE FROM notebook_chunks WHERE source_id = ?', [id]);
      for (final c in chunked.chunks) {
        db.execute(
          'INSERT INTO notebook_chunks(source_id, ordinal, start_offset, end_offset, page, text) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [id, c.ordinal, c.start, c.end, c.page, c.text],
        );
      }
    }
  }

  /// Sources linking the note keep its last text as a copy, so no notebook loses it.
  void deleteNote(int id) => _transaction(() {
    db.execute('UPDATE notebook_sources SET note_id = NULL WHERE note_id = ?', [id]);
    db.execute('DELETE FROM notes WHERE id = ?', [id]);
  });

  Set<int> highlights(Book book, int chapter) => {
    for (final r in db.select('SELECT verse FROM highlights WHERE book = ? AND chapter = ?', [
      book.id,
      chapter,
    ]))
      r['verse'] as int,
  };

  void toggleHighlight(Book book, int chapter, int verse) {
    final on = highlights(book, chapter).contains(verse);
    db.execute(
      on
          ? 'DELETE FROM highlights WHERE book = ? AND chapter = ? AND verse = ?'
          : 'INSERT INTO highlights VALUES (?, ?, ?)',
      [book.id, chapter, verse],
    );
  }

  static const _conversationColumns =
      'SELECT c.id, c.title, c.updated, c.notebook_id, COUNT(m.id) AS n FROM conversations c '
      'LEFT JOIN messages m ON m.conversation_id = c.id';

  static Conversation _conversation(Row r) => Conversation(
    r['id'] as int,
    r['title'] as String,
    DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
    r['n'] as int,
    notebookId: r['notebook_id'] as int?,
  );

  /// Conversations scoped to [notebookId], or to the Bible (past questions) when it is null.
  List<Conversation> conversations({int? notebookId}) => [
    for (final r in db.select(
      '$_conversationColumns WHERE c.notebook_id IS ? GROUP BY c.id ORDER BY c.updated DESC',
      [notebookId],
    ))
      _conversation(r),
  ];

  Conversation? conversation(int id) {
    final rows = db.select('$_conversationColumns WHERE c.id = ? GROUP BY c.id', [id]);
    return rows.isEmpty ? null : _conversation(rows.first);
  }

  static String _conversationTitle(String firstQuestion) => firstQuestion.length > maxTitleChars
      ? '${firstQuestion.substring(0, maxTitleChars).trimRight()}…'
      : firstQuestion;

  int createConversation(String firstQuestion, {int? notebookId}) {
    db.execute(
      'INSERT INTO conversations(title, created, updated, notebook_id) VALUES (?, ?, ?, ?)',
      [_conversationTitle(firstQuestion), _now(), _now(), notebookId],
    );
    return db.lastInsertRowId;
  }

  void addMessage(
    int conversationId,
    String role,
    String text,
    List<Ref> refs, {
    List<ShownSource> sources = const [],
  }) {
    db.execute(
      'INSERT INTO messages(conversation_id, role, text, refs, sources, created) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        conversationId,
        role,
        text,
        jsonEncode([for (final r in refs) r.label]),
        jsonEncode([for (final s in sources) s.toJson()]),
        _now(),
      ],
    );
    db.execute('UPDATE conversations SET updated = ? WHERE id = ?', [_now(), conversationId]);
  }

  List<SavedMessage> messages(int conversationId) => [
    for (final r in db.select(
      'SELECT role, text, refs, sources FROM messages WHERE conversation_id = ? ORDER BY id',
      [conversationId],
    ))
      SavedMessage(
        r['role'] as String,
        r['text'] as String,
        [
          for (final label in (jsonDecode(r['refs'] as String) as List).cast<String>())
            ...RefParser.parse(label),
        ],
        sources: [
          for (final s in jsonDecode(r['sources'] as String) as List) ?ShownSource.fromJson(s),
        ],
      ),
  ];

  Set<Ref> planChaptersDone(String planId) => {
    for (final r in db.select('SELECT book, chapter FROM plan_chapters WHERE plan_id = ?', [
      planId,
    ]))
      Ref(bookById(r['book'] as int), r['chapter'] as int),
  };

  void setPlanChapter(String planId, Ref chapter, bool done) => db.execute(
    done
        ? 'INSERT OR REPLACE INTO plan_chapters VALUES (?, ?, ?, ?)'
        : 'DELETE FROM plan_chapters WHERE plan_id = ? AND book = ? AND chapter = ?',
    [planId, chapter.book.id, chapter.chapter, if (done) _now()],
  );

  /// Days of the plan whose chapters are all read.
  Set<int> planDaysDone(String planId) {
    final plan = planById(planId);
    if (plan == null) return {};
    final progress = PlanProgress(plan, planChaptersDone(planId), 1);
    return {
      for (var d = 1; d <= plan.days; d++)
        if (progress.dayDone(d)) d,
    };
  }

  /// Ticks or unticks every chapter of [day].
  void setPlanDay(String planId, int day, bool done) {
    final plan = planById(planId);
    if (plan == null || day < 1 || day > plan.days) return;
    _transaction(() {
      for (final chapter in plan.schedule()[day - 1]) {
        setPlanChapter(planId, chapter, done);
      }
    });
  }

  void clearPlan(String planId) => _transaction(() {
    db.execute('DELETE FROM plan_chapters WHERE plan_id = ?', [planId]);
    db.execute('DELETE FROM plan_progress WHERE plan_id = ?', [planId]);
    db.execute('DELETE FROM plan_prayed WHERE plan_id = ?', [planId]);
  });

  /// Ticks every chapter of each day ticked before plans counted chapters, then drops the day,
  /// so a later restore cannot tick again a chapter the reader unticked. Days of a plan Berea
  /// no longer has are left as they are. Safe to run again, as after restoring an older backup.
  void carryPlanDays() {
    final schedules = <String, List<List<Ref>>>{};
    for (final r in db.select('SELECT plan_id, day, done_at FROM plan_progress')) {
      final plan = planById(r['plan_id'] as String?);
      final day = r['day'] as int?;
      if (plan == null || day == null || day < 1 || day > plan.days) continue;
      final days = schedules.putIfAbsent(plan.id, plan.schedule);
      for (final chapter in days[day - 1]) {
        db.execute('INSERT OR IGNORE INTO plan_chapters VALUES (?, ?, ?, ?)', [
          plan.id,
          chapter.book.id,
          chapter.chapter,
          r['done_at'],
        ]);
      }
      db.execute('DELETE FROM plan_progress WHERE plan_id = ? AND day = ?', [plan.id, day]);
    }
  }

  StudyPageRecord _page(Row r) => StudyPageRecord(
    r['id'] as int,
    _pageRef(r),
    r['observation'] as String,
    r['interpretation'] as String,
    r['application'] as String,
    DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
    notebookId: r['notebook_id'] as int?,
  );

  /// Every study page, or those in [notebookId].
  List<StudyPageRecord> studyPages({int? notebookId}) => db
      .select(
        notebookId == null
            ? 'SELECT * FROM study_pages ORDER BY updated DESC'
            : 'SELECT * FROM study_pages WHERE notebook_id = ? ORDER BY updated DESC',
        [?notebookId],
      )
      .map(_page)
      .toList();

  void moveStudyPage(int id, int notebookId) =>
      db.execute('UPDATE study_pages SET notebook_id = ? WHERE id = ?', [notebookId, id]);

  StudyPageRecord? studyPageFor(Ref ref) {
    final vs = ref.verseStart ?? 1;
    final rows = db.select(
      'SELECT * FROM study_pages WHERE book = ? AND chapter = ? AND verse_start = ? AND verse_end = ?',
      [ref.book.id, ref.chapter, vs, ref.verseEnd ?? vs],
    );
    return rows.isEmpty ? null : _page(rows.first);
  }

  /// Inserts or updates the page for exactly [ref]. A new page goes to the notebook that
  /// holds its passage, else to the notes on verses notebook, unless [notebookId] says where.
  void saveStudyPage(
    Ref ref,
    String observation,
    String interpretation,
    String application, {
    int? notebookId,
  }) {
    final existing = studyPageFor(ref);
    final vs = ref.verseStart ?? 1;
    if (existing == null) {
      final notebook = notebookId ?? notebookForPassage(ref) ?? notesOnVersesNotebook(db);
      db.execute(
        'INSERT INTO study_pages(book, chapter, verse_start, verse_end, observation, interpretation, '
        'application, notebook_id, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          ref.book.id,
          ref.chapter,
          vs,
          ref.verseEnd ?? vs,
          observation,
          interpretation,
          application,
          notebook,
          _now(),
          _now(),
        ],
      );
    } else {
      db.execute(
        'UPDATE study_pages SET observation = ?, interpretation = ?, application = ?, updated = ? WHERE id = ?',
        [observation, interpretation, application, _now(), existing.id],
      );
    }
  }

  void deleteStudyPage(int id) => db.execute('DELETE FROM study_pages WHERE id = ?', [id]);

  /// Every user-written table, for backup. The notebook search index is not one: triggers
  /// rebuild it from the chunk rows.
  static const userTables = [
    'notes',
    'highlights',
    'conversations',
    'messages',
    'plan_progress',
    'plan_chapters',
    'study_pages',
    'notebooks',
    'notebook_sources',
    'notebook_chunks',
    'notebook_messages',
    ...prayerTables,
    ...prayerPlanTables,
  ];

  Map<String, List<Map<String, Object?>>> exportTables() => {
    for (final t in userTables)
      t: [for (final r in db.select('SELECT * FROM $t')) Map<String, Object?>.from(r)],
  };

  /// What each column must hold for the readers in this class not to fail. Every listed column
  /// is required; columns not listed (created) may be absent.
  static const _columnTypes = <String, Map<String, Type>>{
    'notes': {'id': int, 'text': String, 'updated': int},
    'highlights': {'book': int, 'chapter': int, 'verse': int},
    'conversations': {'id': int, 'title': String, 'updated': int},
    'messages': {'conversation_id': int, 'role': String, 'text': String, 'refs': String},
    'plan_progress': {'plan_id': String, 'day': int},
    'plan_chapters': {'plan_id': String, 'book': int, 'chapter': int},
    'study_pages': {
      'id': int,
      'book': int,
      'chapter': int,
      'verse_start': int,
      'verse_end': int,
      'observation': String,
      'interpretation': String,
      'application': String,
      'updated': int,
    },
    'notebooks': {'id': int, 'title': String, 'updated': int},
    'notebook_sources': {
      'id': int,
      'notebook_id': int,
      'kind': String,
      'title': String,
      'origin': String,
      'text': String,
    },
    'notebook_chunks': {
      'id': int,
      'source_id': int,
      'ordinal': int,
      'start_offset': int,
      'end_offset': int,
      'text': String,
    },
    'notebook_messages': {
      'notebook_id': int,
      'role': String,
      'text': String,
      'refs': String,
      'sources': String,
    },
    ...prayerColumnTypes,
    ...prayerPlanColumnTypes,
  };

  /// Columns a backup may lack, older ones having been written before they existed. When
  /// present they hold this type, or null where [_nullable] allows it.
  static const _optionalTypes = <String, Map<String, Type>>{
    'notes': {
      'book': int,
      'chapter': int,
      'verse_start': int,
      'verse_end': int,
      'notebook_id': int,
      'title': String,
      'kind': String,
    },
    'notebooks': {'system_key': String},
    'study_pages': {'notebook_id': int},
    'conversations': {'notebook_id': int},
    'messages': {'sources': String, 'notebook_message_id': int},
    'notebook_sources': {'note_id': int},
    'prayers': {'topic': String},
    'prayer_plan_runs': {'prayer_id': int, 'finished': int},
  };

  static const _nullable = {
    'system_key',
    'book',
    'chapter',
    'verse_start',
    'verse_end',
    'notebook_id',
    'notebook_message_id',
    'note_id',
    'topic',
    'prayer_id',
    'finished',
  };

  static const _verseColumnNames = ['book', 'chapter', 'verse_start', 'verse_end'];

  /// Throws [FormatException] when a row has a column the table lacks, a missing or mistyped
  /// value, a book outside the 66, saved references that are not a list, or notebook rows that
  /// do not fit together.
  void validateTables(Map<String, List<Map<String, Object?>>> tables) {
    final notebookTables = _notebookTables.where(tables.containsKey).length;
    if (notebookTables != 0 && notebookTables != _notebookTables.length) {
      throw const FormatException('notebook tables must be backed up together');
    }
    if (notebookTables == 0 && tables.keys.any(_notebookChatTables.contains)) {
      throw const FormatException('notebook conversations need their notebooks');
    }
    _validateColumns(tables);
    _validateNotebooks(tables);
    validatePrayerTables(tables);
    validatePrayerPlanTables(tables);
  }

  void _validateColumns(Map<String, List<Map<String, Object?>>> tables) {
    for (final t in userTables) {
      final columns = {for (final r in db.select('PRAGMA table_info($t)')) r['name'] as String};
      final types = _columnTypes[t]!;
      for (final row in tables[t] ?? const <Map<String, Object?>>[]) {
        final unknown = row.keys.where((c) => !columns.contains(c));
        if (unknown.isNotEmpty) throw FormatException('unknown column ${unknown.first} in $t');
        for (final e in types.entries) {
          _checkType(t, e.key, e.value, row[e.key]);
        }
        for (final e in (_optionalTypes[t] ?? const <String, Type>{}).entries) {
          final v = row[e.key];
          if (v == null && (!row.containsKey(e.key) || _nullable.contains(e.key))) continue;
          _checkType(t, e.key, e.value, v);
        }
        final book = row['book'];
        if (book is int && (book < 1 || book > books.length)) {
          throw FormatException('bad book $book in $t');
        }
        if (t == 'notes') {
          final set = _verseColumnNames.where((c) => row[c] != null).length;
          if (set != 0 && set != _verseColumnNames.length) {
            throw FormatException('note ${row['id']} has part of a verse');
          }
        }
        if (t == 'messages') {
          _jsonList(row, t, 'refs');
          if (row.containsKey('sources')) _jsonList(row, t, 'sources');
        }
        if (t == 'notebook_messages') {
          _jsonList(row, t, 'refs');
          _jsonList(row, t, 'sources');
        }
      }
    }
  }

  static void _checkType(String table, String column, Type type, Object? v) {
    final ok = type == int ? v is int : v is String;
    if (!ok) throw FormatException('$table.$column must be $type, not $v');
  }

  static void _jsonList(Map<String, Object?> row, String table, String column) {
    try {
      if (jsonDecode(row[column] as String) is! List) throw const FormatException('');
    } on FormatException {
      throw FormatException('$table.$column must be a JSON list');
    }
  }

  /// Sources belong to a notebook in the backup, chunks to a source, and each chunk is exactly
  /// the slice of its source's text that its offsets name, so citations stay true.
  static void _validateNotebooks(Map<String, List<Map<String, Object?>>> tables) {
    final notebooks = {for (final r in tables['notebooks'] ?? const []) r['id']};
    final sourceText = <Object?, String>{};
    for (final r in tables['notebook_sources'] ?? const <Map<String, Object?>>[]) {
      if (!notebooks.contains(r['notebook_id'])) {
        throw FormatException('notebook source ${r['id']} has no notebook');
      }
      if (SourceKind.byName(r['kind'] as String) == null) {
        throw FormatException('unknown notebook source kind ${r['kind']}');
      }
      // Older version 2 backups have no pinned column; the database default applies.
      if (r.containsKey('pinned') && r['pinned'] != 0 && r['pinned'] != 1) {
        throw FormatException('notebook source ${r['id']} has a bad pinned flag');
      }
      sourceText[r['id']] = r['text'] as String;
    }
    for (final r in tables['notebook_chunks'] ?? const <Map<String, Object?>>[]) {
      final text = sourceText[r['source_id']];
      if (text == null) throw FormatException('notebook chunk ${r['id']} has no source');
      final (start, end, page) = (r['start_offset'] as int, r['end_offset'] as int, r['page']);
      final inRange = start >= 0 && start <= end && end <= text.length;
      if (!inRange || text.substring(start, end) != r['text']) {
        throw FormatException('notebook chunk ${r['id']} does not match its source');
      }
      if (page != null && (page is! int || page < 1)) {
        throw FormatException('notebook chunk ${r['id']} has a bad page');
      }
    }
    // Rows of a backup without notebooks can point at none: the merge after the restore
    // gives them one.
    for (final t in const ['notes', 'study_pages', 'conversations']) {
      for (final r in tables[t] ?? const <Map<String, Object?>>[]) {
        final id = r['notebook_id'];
        if (id != null && !notebooks.contains(id)) {
          throw FormatException('$t row ${r['id']} is in a notebook the backup lacks');
        }
      }
    }
    final notes = {for (final r in tables['notes'] ?? const []) r['id']};
    for (final r in tables['notebook_sources'] ?? const <Map<String, Object?>>[]) {
      final note = r['note_id'];
      if (note != null && !notes.contains(note)) {
        throw FormatException('notebook source ${r['id']} links a note the backup lacks');
      }
    }
    for (final r in tables['notebook_messages'] ?? const <Map<String, Object?>>[]) {
      if (!notebooks.contains(r['notebook_id'])) {
        throw FormatException('notebook message ${r['id']} has no notebook');
      }
      if (r['role'] != 'user' && r['role'] != 'assistant') {
        throw FormatException('notebook message ${r['id']} has role ${r['role']}');
      }
    }
  }

  /// Added in backup version 2; a version 1 backup has none of them.
  static const _notebookTables = {'notebooks', 'notebook_sources', 'notebook_chunks'};

  /// Notebook conversations, added later in version 2. They follow the notebook tables: kept
  /// when a backup has no notebooks, cleared when it has notebooks but no conversations, so a
  /// conversation never attaches to a notebook id the backup reused.
  static const _notebookChatTables = {'notebook_messages'};

  /// Replaces every user table with [tables] in one transaction; on any error nothing changes.
  /// A backup without notebook tables (version 1) leaves the notebooks on the device alone.
  /// A backup from before the notes merge comes back merged.
  void importTables(Map<String, List<Map<String, Object?>>> tables) {
    validateTables(tables);
    _transaction(() {
      final hasNotebooks = tables.keys.any(_notebookTables.contains);
      for (final t in userTables) {
        if (!tables.containsKey(t) && _notebookTables.contains(t)) continue;
        if (!hasNotebooks && _notebookChatTables.contains(t)) continue;
        // A backup from before Prayer leaves the prayers on the device alone.
        if (!tables.containsKey('prayers') && prayerTables.contains(t)) continue;
        // A backup from before prayer plans leaves the plans on the device alone.
        if (!tables.containsKey('prayer_plan_runs') && prayerPlanTables.contains(t)) continue;
        db.execute('DELETE FROM $t');
        for (final row in tables[t] ?? const <Map<String, Object?>>[]) {
          final cols = row.keys.toList();
          db.execute(
            'INSERT INTO $t(${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final c in cols) row[c]],
          );
        }
      }
      // A restore that replaced the prayers without the plan tables leaves ids that mean other
      // prayers now, so every link goes; with the plan tables, only links to a missing prayer.
      final replacedPrayers = tables.containsKey('prayers');
      final brokeLinks = replacedPrayers && !tables.containsKey('prayer_plan_runs');
      db.execute(
        brokeLinks
            ? 'UPDATE prayer_plan_runs SET prayer_id = NULL'
            : 'UPDATE prayer_plan_runs SET prayer_id = NULL '
                  'WHERE prayer_id IS NOT NULL AND prayer_id NOT IN (SELECT id FROM prayers)',
      );
      // The notes were replaced under the kept notebooks, so their note ids mean other notes.
      if (!hasNotebooks) db.execute('UPDATE notebook_sources SET note_id = NULL');
      // An older backup's notes on verses notebook has no key yet; key it before the merge
      // looks for it, or the merge would make a second one.
      _keyNotesOnVerses();
      // Only notes saved before notes had a kind are guessed from their text.
      if (!(tables['notes'] ?? const []).any((r) => r.containsKey('kind'))) {
        _markLegacyKeptWords();
      }
      mergeNotes();
      // A backup from before chapter ticks brings day ticks; they come back as chapters.
      carryPlanDays();
    });
  }

  /// Also deletes the notebook messages it was copied from, so no later copy brings it back.
  void deleteConversation(int id) => _transaction(() {
    db.execute(
      'DELETE FROM notebook_messages WHERE id IN '
      '(SELECT notebook_message_id FROM messages WHERE conversation_id = ?)',
      [id],
    );
    db.execute('DELETE FROM messages WHERE conversation_id = ?', [id]);
    db.execute('DELETE FROM conversations WHERE id = ?', [id]);
  });
}

/// Larger than any chapter, so a chapter reference holds every verse.
const _wholeChapter = 999;

/// How a note source is titled: its verse, else its title, else its first words.
String noteSourceTitle(Note n) {
  if (n.verse case final v?) return 'Note on ${v.label}';
  if (n.title.trim().isNotEmpty) return n.title.trim();
  final words = n.text.trim().split(RegExp(r'\s+'));
  final head = words.take(_noteTitleWords).join(' ');
  return words.length > _noteTitleWords ? '$head…' : head;
}

const _noteTitleWords = 8;
