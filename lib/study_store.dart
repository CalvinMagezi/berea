import 'dart:convert';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';

import 'notebook_store.dart';

/// Everything the user writes: notes, highlights and saved studies. One local SQLite file,
/// never synced, never sent anywhere.
class Note {
  final int id;
  final Ref ref;
  final String text;
  final DateTime updated;
  const Note(this.id, this.ref, this.text, this.updated);
}

class StudyPageRecord {
  final int id;
  final Ref ref;
  final String observation;
  final String interpretation;
  final String application;
  final DateTime updated;
  const StudyPageRecord(
    this.id,
    this.ref,
    this.observation,
    this.interpretation,
    this.application,
    this.updated,
  );
}

class Conversation {
  final int id;
  final String title;
  final DateTime updated;
  final int messageCount;
  const Conversation(this.id, this.title, this.updated, this.messageCount);
}

class SavedMessage {
  final String role;
  final String text;
  final List<Ref> refs;
  const SavedMessage(this.role, this.text, this.refs);
  bool get isUser => role == 'user';
}

const maxTitleChars = 60;

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
  static const migrations = [notebookSchema];

  static int get schemaVersion => migrations.length;

  /// A file from a newer Berea (a downgrade) is opened as it is: later migrations only add
  /// tables, so the ones this version reads keep their meaning.
  void _migrate() {
    final version = db.select('PRAGMA user_version').first.values.first as int;
    for (var v = version; v < migrations.length; v++) {
      db.execute('BEGIN');
      try {
        db.execute(migrations[v]);
        db.execute('PRAGMA user_version = ${v + 1}');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  factory StudyStore.open(String path) => StudyStore(sqlite3.open(path));

  void close() => db.dispose();

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Note _note(Row r) => Note(
    r['id'] as int,
    Ref(
      bookById(r['book'] as int),
      r['chapter'] as int,
      r['verse_start'] as int,
      r['verse_end'] as int,
    ),
    r['text'] as String,
    DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
  );

  List<Note> notes({Book? book, int? chapter}) {
    final rows = book == null
        ? db.select('SELECT * FROM notes ORDER BY updated DESC')
        : chapter == null
        ? db.select('SELECT * FROM notes WHERE book = ? ORDER BY chapter, verse_start', [book.id])
        : db.select('SELECT * FROM notes WHERE book = ? AND chapter = ? ORDER BY verse_start', [
            book.id,
            chapter,
          ]);
    return rows.map(_note).toList();
  }

  int addNote(Ref ref, String text) {
    final vs = ref.verseStart ?? 1;
    db.execute(
      'INSERT INTO notes(book, chapter, verse_start, verse_end, text, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [ref.book.id, ref.chapter, vs, ref.verseEnd ?? vs, text, _now(), _now()],
    );
    return db.lastInsertRowId;
  }

  void updateNote(int id, String text) =>
      db.execute('UPDATE notes SET text = ?, updated = ? WHERE id = ?', [text, _now(), id]);

  void deleteNote(int id) => db.execute('DELETE FROM notes WHERE id = ?', [id]);

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

  List<Conversation> conversations() => [
    for (final r in db.select(
      'SELECT c.id, c.title, c.updated, COUNT(m.id) AS n FROM conversations c '
      'LEFT JOIN messages m ON m.conversation_id = c.id GROUP BY c.id ORDER BY c.updated DESC',
    ))
      Conversation(
        r['id'] as int,
        r['title'] as String,
        DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
        r['n'] as int,
      ),
  ];

  int createConversation(String firstQuestion) {
    final title = firstQuestion.length > maxTitleChars
        ? '${firstQuestion.substring(0, maxTitleChars).trimRight()}…'
        : firstQuestion;
    db.execute('INSERT INTO conversations(title, created, updated) VALUES (?, ?, ?)', [
      title,
      _now(),
      _now(),
    ]);
    return db.lastInsertRowId;
  }

  void addMessage(int conversationId, String role, String text, List<Ref> refs) {
    db.execute(
      'INSERT INTO messages(conversation_id, role, text, refs, created) VALUES (?, ?, ?, ?, ?)',
      [
        conversationId,
        role,
        text,
        jsonEncode([for (final r in refs) r.label]),
        _now(),
      ],
    );
    db.execute('UPDATE conversations SET updated = ? WHERE id = ?', [_now(), conversationId]);
  }

  List<SavedMessage> messages(int conversationId) => [
    for (final r in db.select(
      'SELECT role, text, refs FROM messages WHERE conversation_id = ? ORDER BY id',
      [conversationId],
    ))
      SavedMessage(r['role'] as String, r['text'] as String, [
        for (final label in (jsonDecode(r['refs'] as String) as List).cast<String>())
          ...RefParser.parse(label),
      ]),
  ];

  Set<int> planDaysDone(String planId) => {
    for (final r in db.select('SELECT day FROM plan_progress WHERE plan_id = ?', [planId]))
      r['day'] as int,
  };

  void setPlanDay(String planId, int day, bool done) => db.execute(
    done
        ? 'INSERT OR REPLACE INTO plan_progress VALUES (?, ?, ?)'
        : 'DELETE FROM plan_progress WHERE plan_id = ? AND day = ?',
    done ? [planId, day, _now()] : [planId, day],
  );

  void clearPlan(String planId) =>
      db.execute('DELETE FROM plan_progress WHERE plan_id = ?', [planId]);

  StudyPageRecord _page(Row r) => StudyPageRecord(
    r['id'] as int,
    Ref(
      bookById(r['book'] as int),
      r['chapter'] as int,
      r['verse_start'] as int,
      r['verse_end'] as int,
    ),
    r['observation'] as String,
    r['interpretation'] as String,
    r['application'] as String,
    DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
  );

  List<StudyPageRecord> studyPages() =>
      db.select('SELECT * FROM study_pages ORDER BY updated DESC').map(_page).toList();

  StudyPageRecord? studyPageFor(Ref ref) {
    final vs = ref.verseStart ?? 1;
    final rows = db.select(
      'SELECT * FROM study_pages WHERE book = ? AND chapter = ? AND verse_start = ? AND verse_end = ?',
      [ref.book.id, ref.chapter, vs, ref.verseEnd ?? vs],
    );
    return rows.isEmpty ? null : _page(rows.first);
  }

  /// Inserts or updates the page for exactly [ref].
  void saveStudyPage(Ref ref, String observation, String interpretation, String application) {
    final existing = studyPageFor(ref);
    final vs = ref.verseStart ?? 1;
    if (existing == null) {
      db.execute(
        'INSERT INTO study_pages(book, chapter, verse_start, verse_end, observation, interpretation, '
        'application, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          ref.book.id,
          ref.chapter,
          vs,
          ref.verseEnd ?? vs,
          observation,
          interpretation,
          application,
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
    'study_pages',
    'notebooks',
    'notebook_sources',
    'notebook_chunks',
  ];

  Map<String, List<Map<String, Object?>>> exportTables() => {
    for (final t in userTables)
      t: [for (final r in db.select('SELECT * FROM $t')) Map<String, Object?>.from(r)],
  };

  /// What each column must hold for the readers in this class not to fail. Every listed column
  /// is required; columns not listed (created) may be absent.
  static const _columnTypes = <String, Map<String, Type>>{
    'notes': {
      'id': int,
      'book': int,
      'chapter': int,
      'verse_start': int,
      'verse_end': int,
      'text': String,
      'updated': int,
    },
    'highlights': {'book': int, 'chapter': int, 'verse': int},
    'conversations': {'id': int, 'title': String, 'updated': int},
    'messages': {'conversation_id': int, 'role': String, 'text': String, 'refs': String},
    'plan_progress': {'plan_id': String, 'day': int},
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
  };

  /// Throws [FormatException] when a row has a column the table lacks, a missing or mistyped
  /// value, a book outside the 66, saved references that are not a list, or notebook rows that
  /// do not fit together.
  void validateTables(Map<String, List<Map<String, Object?>>> tables) {
    final notebookTables = _notebookTables.where(tables.containsKey).length;
    if (notebookTables != 0 && notebookTables != _notebookTables.length) {
      throw const FormatException('notebook tables must be backed up together');
    }
    _validateColumns(tables);
    _validateNotebooks(tables);
  }

  void _validateColumns(Map<String, List<Map<String, Object?>>> tables) {
    for (final t in userTables) {
      final columns = {for (final r in db.select('PRAGMA table_info($t)')) r['name'] as String};
      final types = _columnTypes[t]!;
      for (final row in tables[t] ?? const <Map<String, Object?>>[]) {
        final unknown = row.keys.where((c) => !columns.contains(c));
        if (unknown.isNotEmpty) throw FormatException('unknown column ${unknown.first} in $t');
        for (final e in types.entries) {
          final v = row[e.key];
          final ok = e.value == int ? v is int : v is String;
          if (!ok) throw FormatException('$t.${e.key} must be ${e.value}, not $v');
        }
        final book = row['book'];
        if (book is int && (book < 1 || book > books.length)) {
          throw FormatException('bad book $book in $t');
        }
        if (t == 'messages') {
          try {
            if (jsonDecode(row['refs'] as String) is! List) throw const FormatException('');
          } on FormatException {
            throw const FormatException('messages.refs must be a JSON list');
          }
        }
      }
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
  }

  /// Added in backup version 2; a version 1 backup has none of them.
  static const _notebookTables = {'notebooks', 'notebook_sources', 'notebook_chunks'};

  /// Replaces every user table with [tables] in one transaction; on any error nothing changes.
  /// A backup without notebook tables (version 1) leaves the notebooks on the device alone.
  void importTables(Map<String, List<Map<String, Object?>>> tables) {
    validateTables(tables);
    db.execute('BEGIN');
    try {
      for (final t in userTables) {
        if (!tables.containsKey(t) && _notebookTables.contains(t)) continue;
        db.execute('DELETE FROM $t');
        for (final row in tables[t] ?? const <Map<String, Object?>>[]) {
          final cols = row.keys.toList();
          db.execute(
            'INSERT INTO $t(${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final c in cols) row[c]],
          );
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteConversation(int id) {
    db.execute('DELETE FROM messages WHERE conversation_id = ?', [id]);
    db.execute('DELETE FROM conversations WHERE id = ?', [id]);
  }
}
