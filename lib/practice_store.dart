import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// Study store migration 9: practice sets (a person's list of references, or one received as a
/// line of text) and practice items (a passage on the recall ladder). Only new tables, so an
/// older Berea opens the file and ignores them.
const practiceSchema = '''
  CREATE TABLE IF NOT EXISTS practice_sets(id INTEGER PRIMARY KEY, title TEXT,
    made_by TEXT NOT NULL DEFAULT 'person', created INTEGER NOT NULL,
    archived INTEGER NOT NULL DEFAULT 0);
  CREATE TABLE IF NOT EXISTS practice_set_refs(set_id INTEGER NOT NULL, pos INTEGER NOT NULL,
    book INTEGER NOT NULL, chapter INTEGER NOT NULL, verse_start INTEGER, verse_end INTEGER,
    PRIMARY KEY(set_id, pos)) WITHOUT ROWID;
  CREATE TABLE IF NOT EXISTS practice_items(id INTEGER PRIMARY KEY, book INTEGER NOT NULL,
    chapter INTEGER NOT NULL, verse_start INTEGER NOT NULL, verse_end INTEGER NOT NULL,
    translation TEXT NOT NULL, rung INTEGER NOT NULL DEFAULT 0, due_day INTEGER NOT NULL,
    last_at INTEGER, last_result TEXT, check_kind TEXT NOT NULL DEFAULT 'recall');
''';

/// The practice tables in backup order: a set before the references that belong to it.
const practiceTables = ['practice_sets', 'practice_set_refs', 'practice_items'];

const practiceColumnTypes = <String, Map<String, Type>>{
  'practice_sets': {
    'id': int,
    'made_by': String,
    'created': int,
    'archived': int,
  },
  'practice_set_refs': {'set_id': int, 'pos': int, 'book': int, 'chapter': int},
  'practice_items': {
    'id': int,
    'book': int,
    'chapter': int,
    'verse_start': int,
    'verse_end': int,
    'translation': String,
    'rung': int,
    'due_day': int,
    'check_kind': String,
  },
};

const madeByPerson = 'person';
const madeByReceived = 'received';
const _madeBy = {madeByPerson, madeByReceived};

/// Throws [FormatException] when a backed-up set or item is not one the readers can show: a
/// reference to a book outside the 66, a reference outside any set, an unknown maker.
void validatePracticeTables(Map<String, List<Map<String, Object?>>> tables) {
  final sets = tables['practice_sets'] ?? const <Map<String, Object?>>[];
  final ids = {for (final r in sets) r['id']};
  for (final r in sets) {
    if (!_madeBy.contains(r['made_by'])) {
      throw FormatException('practice set ${r['id']} has an unknown maker');
    }
    if (r['archived'] != 0 && r['archived'] != 1) {
      throw FormatException('practice set ${r['id']} has a bad archived flag');
    }
  }
  for (final r
      in tables['practice_set_refs'] ?? const <Map<String, Object?>>[]) {
    if (!ids.contains(r['set_id'])) {
      throw const FormatException('a practice reference has no set');
    }
    _checkBook(r['book'], 'practice reference');
  }
  for (final r in tables['practice_items'] ?? const <Map<String, Object?>>[]) {
    _checkBook(r['book'], 'practice item ${r['id']}');
    final rung = r['rung'];
    if (rung is! int || rung < 0) {
      throw FormatException('practice item ${r['id']} has a bad rung');
    }
  }
}

void _checkBook(Object? book, String what) {
  if (book is! int || book < 1 || book > books.length) {
    throw FormatException('$what has a bad book');
  }
}

/// A person's list of passages to practise.
class PracticeSet {
  final int id;
  final String? title;
  final String madeBy;
  final List<Ref> refs;
  const PracticeSet(this.id, this.title, this.madeBy, this.refs);

  /// The title, or the references when the set has none.
  String get label => title != null && title!.isNotEmpty
      ? title!
      : refs.map((r) => r.label).join('; ');
}

/// Practice sets, kept in study.sqlite beside the notes. A set is references only; the words come
/// from the installed translation when it is shown.
class PracticeStore extends ChangeNotifier {
  final Database db;
  final DateTime Function() now;
  PracticeStore(this.db, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  /// Tells the screens to read again after a restore replaced the rows underneath.
  void refresh() => notifyListeners();

  /// Saves [refs] as a set, newest last. Returns its id, or null when there is nothing to save.
  int? saveSet(List<Ref> refs, {String? title, String madeBy = madeByPerson}) {
    if (refs.isEmpty) return null;
    db.execute('BEGIN');
    try {
      db.execute(
        'INSERT INTO practice_sets(title, made_by, created) VALUES (?, ?, ?)',
        [
          title?.trim().isEmpty ?? true ? null : title!.trim(),
          madeBy,
          now().millisecondsSinceEpoch,
        ],
      );
      final id = db.lastInsertRowId;
      for (var i = 0; i < refs.length; i++) {
        final r = refs[i];
        db.execute(
          'INSERT INTO practice_set_refs(set_id, pos, book, chapter, verse_start, verse_end) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [id, i, r.book.id, r.chapter, r.verseStart, r.verseEnd],
        );
      }
      db.execute('COMMIT');
      notifyListeners();
      return id;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// The sets that are not archived, oldest first.
  List<PracticeSet> sets() => [
    for (final r in db.select(
      'SELECT * FROM practice_sets WHERE archived = 0 ORDER BY id',
    ))
      _set(r),
  ];

  PracticeSet? set(int id) {
    final rows = db.select('SELECT * FROM practice_sets WHERE id = ?', [id]);
    return rows.isEmpty ? null : _set(rows.first);
  }

  PracticeSet _set(Row r) => PracticeSet(
    r['id'] as int,
    r['title'] as String?,
    r['made_by'] as String,
    [
      for (final ref in db.select(
        'SELECT * FROM practice_set_refs WHERE set_id = ? ORDER BY pos',
        [r['id']],
      ))
        Ref(
          bookById(ref['book'] as int),
          ref['chapter'] as int,
          ref['verse_start'] as int?,
          ref['verse_end'] as int?,
        ),
    ],
  );

  void rename(int id, String? title) {
    db.execute('UPDATE practice_sets SET title = ? WHERE id = ?', [
      title?.trim().isEmpty ?? true ? null : title!.trim(),
      id,
    ]);
    notifyListeners();
  }

  /// A set the person no longer wants is deleted with its references.
  void delete(int id) {
    db.execute('DELETE FROM practice_set_refs WHERE set_id = ?', [id]);
    db.execute('DELETE FROM practice_sets WHERE id = ?', [id]);
    notifyListeners();
  }
}
