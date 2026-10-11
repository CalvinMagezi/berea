import 'dart:convert';

import 'package:berea_harness/berea_harness.dart';
import 'package:sqlite3/sqlite3.dart';

/// Everything the user writes: notes, highlights and saved studies. One local SQLite file,
/// never synced, never sent anywhere.
class Note {
  final int id;
  final Ref ref;
  final String text;
  final DateTime updated;
  const Note(this.id, this.ref, this.text, this.updated);
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
    ''');
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

  void deleteConversation(int id) {
    db.execute('DELETE FROM messages WHERE conversation_id = ?', [id]);
    db.execute('DELETE FROM conversations WHERE id = ?', [id]);
  }
}
