import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// Study store migration for Prayer. Dates are epoch milliseconds. [verse] is a reference label
/// such as "Philippians 4:6-7". A prayed day is a local yyyymmdd number, one row per day, so
/// Amen twice in a day counts once and last prayed is the latest day. [reminder] is minutes
/// after midnight, kept for the notifications run and not shown until then.
const prayerSchema = '''
  CREATE TABLE IF NOT EXISTS prayers(id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL, for_whom TEXT NOT NULL DEFAULT '', verse TEXT,
    note TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL, answered INTEGER, answer TEXT,
    archived INTEGER NOT NULL DEFAULT 0, reminder INTEGER);
  CREATE TABLE IF NOT EXISTS prayer_days(prayer_id INTEGER NOT NULL, day INTEGER NOT NULL,
    PRIMARY KEY(prayer_id, day)) WITHOUT ROWID;
''';

/// The prayer tables in backup order: prayers before the days that point at them.
const prayerTables = ['prayers', 'prayer_days'];

/// The never-null columns of the prayer tables, in the shape of StudyStore's column checks.
/// Nullable columns (verse, answered, answer, reminder) are left out on purpose.
const prayerColumnTypes = <String, Map<String, Type>>{
  'prayers': {
    'id': int,
    'title': String,
    'for_whom': String,
    'note': String,
    'created': int,
    'archived': int,
  },
  'prayer_days': {'prayer_id': int, 'day': int},
};

/// Throws [FormatException] when a backed-up prayer day points at no prayer, or a prayer has a
/// bad archived flag or a verse that is not a reference.
void validatePrayerTables(Map<String, List<Map<String, Object?>>> tables) {
  final ids = <Object?>{};
  for (final r in tables['prayers'] ?? const <Map<String, Object?>>[]) {
    ids.add(r['id']);
    if (r['archived'] != 0 && r['archived'] != 1) {
      throw FormatException('prayer ${r['id']} has a bad archived flag');
    }
    final verse = r['verse'];
    if (verse != null && (verse is! String || RefParser.parse(verse).isEmpty)) {
      throw FormatException('prayer ${r['id']} has a bad verse');
    }
  }
  for (final r in tables['prayer_days'] ?? const <Map<String, Object?>>[]) {
    if (!ids.contains(r['prayer_id'])) {
      throw FormatException('prayer day ${r['day']} has no prayer');
    }
  }
}

/// A local calendar day as yyyymmdd.
int prayerDay(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

DateTime _fromDay(int day) => DateTime(day ~/ 10000, day ~/ 100 % 100, day % 100);

DateTime? _date(Object? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

/// The canonical label for a typed reference, or null when there is none.
String? verseLabel(String? typed) =>
    typed == null ? null : RefParser.parse(typed).firstOrNull?.label;

class Prayer {
  final int id;
  final String title;
  final String forWhom;

  /// A reference label, or null.
  final String? verse;
  final String note;
  final DateTime created;
  final DateTime? lastPrayed;
  final DateTime? firstPrayed;
  final int daysPrayed;
  final DateTime? answered;
  final String? answer;
  final bool archived;

  /// Minutes after midnight. Stored but not offered until reminders exist.
  final int? reminder;
  const Prayer({
    required this.id,
    required this.title,
    this.forWhom = '',
    this.verse,
    this.note = '',
    required this.created,
    this.lastPrayed,
    this.firstPrayed,
    this.daysPrayed = 0,
    this.answered,
    this.answer,
    this.archived = false,
    this.reminder,
  });

  bool get isAnswered => answered != null;
  Ref? get ref => verse == null ? null : RefParser.parse(verse!).firstOrNull;
}

class PrayerStore extends ChangeNotifier {
  final Database db;

  /// The clock, replaceable so tests can cross midnight.
  final DateTime Function() now;
  PrayerStore(this.db, {DateTime Function()? now}) : now = now ?? DateTime.now;

  int _nowMs() => now().millisecondsSinceEpoch;

  static const _select = '''
    SELECT p.*, MAX(d.day) AS last_day, MIN(d.day) AS first_day, COUNT(d.day) AS day_count
    FROM prayers p LEFT JOIN prayer_days d ON d.prayer_id = p.id''';

  Prayer _prayer(Row r) {
    final last = r['last_day'] as int?;
    final first = r['first_day'] as int?;
    return Prayer(
      id: r['id'] as int,
      title: r['title'] as String,
      forWhom: r['for_whom'] as String,
      verse: r['verse'] as String?,
      note: r['note'] as String,
      created: _date(r['created'])!,
      lastPrayed: last == null ? null : _fromDay(last),
      firstPrayed: first == null ? null : _fromDay(first),
      daysPrayed: r['day_count'] as int,
      answered: _date(r['answered']),
      answer: r['answer'] as String?,
      archived: r['archived'] == 1,
      reminder: r['reminder'] as int?,
    );
  }

  List<Prayer> _query(String where, [List<Object?> args = const []]) =>
      db.select('$_select WHERE $where GROUP BY p.id', args).map(_prayer).toList();

  Prayer? prayer(int id) => _query('p.id = ?', [id]).firstOrNull;

  /// Still being prayed for, newest first, as the list shows them.
  List<Prayer> praying() =>
      _query('p.answered IS NULL AND p.archived = 0')
        ..sort((a, b) => b.created.compareTo(a.created));

  /// Answered and not archived, newest answer first.
  List<Prayer> answered() =>
      _query('p.answered IS NOT NULL AND p.archived = 0')
        ..sort((a, b) => b.answered!.compareTo(a.answered!));

  /// The Pray now order: never prayed first, then least recently prayed, oldest added first.
  List<Prayer> prayNowQueue() {
    final ps = _query('p.answered IS NULL AND p.archived = 0');
    int key(Prayer p) => p.lastPrayed == null ? 0 : prayerDay(p.lastPrayed!);
    return ps..sort((a, b) {
      final byDay = key(a).compareTo(key(b));
      return byDay != 0 ? byDay : a.created.compareTo(b.created);
    });
  }

  bool get isEmpty => db.select('SELECT 1 FROM prayers LIMIT 1').isEmpty;

  int add({required String title, String forWhom = '', String? verse, String note = ''}) {
    db.execute(
      'INSERT INTO prayers(title, for_whom, verse, note, created) VALUES (?, ?, ?, ?, ?)',
      [title.trim(), forWhom.trim(), verseLabel(verse), note.trim(), _nowMs()],
    );
    final id = db.lastInsertRowId;
    notifyListeners();
    return id;
  }

  void edit(int id, {required String title, String forWhom = '', String? verse, String note = ''}) {
    db.execute('UPDATE prayers SET title = ?, for_whom = ?, verse = ?, note = ? WHERE id = ?', [
      title.trim(),
      forWhom.trim(),
      verseLabel(verse),
      note.trim(),
      id,
    ]);
    notifyListeners();
  }

  /// Records today as a day [id] was prayed for. A second Amen on the same day changes nothing.
  void amen(int id) {
    db.execute('INSERT OR IGNORE INTO prayer_days(prayer_id, day) VALUES (?, ?)', [
      id,
      prayerDay(now()),
    ]);
    notifyListeners();
  }

  /// Marks [id] answered today with the person's own line, which may be empty.
  void markAnswered(int id, String answer) {
    db.execute('UPDATE prayers SET answered = ?, answer = ? WHERE id = ?', [
      _nowMs(),
      _blankToNull(answer),
      id,
    ]);
    notifyListeners();
  }

  /// Puts an answered prayer back on the list, for Undo.
  void unanswer(int id) {
    db.execute('UPDATE prayers SET answered = NULL, answer = NULL WHERE id = ?', [id]);
    notifyListeners();
  }

  /// Stop praying: kept, but out of the list and Pray now, and not called answered.
  void setArchived(int id, bool archived) {
    db.execute('UPDATE prayers SET archived = ? WHERE id = ?', [archived ? 1 : 0, id]);
    notifyListeners();
  }

  void delete(int id) {
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM prayer_days WHERE prayer_id = ?', [id]);
      db.execute('DELETE FROM prayers WHERE id = ?', [id]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    notifyListeners();
  }
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One request as plain text, for the share sheet.
String prayerShareText(Prayer p) {
  final b = StringBuffer(p.title);
  if (p.forWhom.isNotEmpty) b.write(' (for ${p.forWhom})');
  if (p.verse != null) b.write('\n${p.verse}');
  if (p.note.isNotEmpty) b.write('\n${p.note}');
  return b.toString();
}

/// An answered prayer as a testimony: the request, the person's own line and the verse.
String testimonyText(Prayer p) {
  final b = StringBuffer('${p.title}\n');
  if (p.answer != null) b.write('${p.answer}\n');
  b.write('Answered ${_ymd(p.answered ?? p.created)}');
  if (p.verse != null) b.write('\n${p.verse}');
  return b.toString();
}

/// The praying list as plain text, for a group chat.
String prayerListText(List<Prayer> praying) => [
  'Praying for',
  for (final p in praying) '- ${prayerShareText(p).replaceAll('\n', ' · ')}',
].join('\n');

/// Every prayer as Markdown for export, praying first, then answered, then stopped.
String prayersMarkdown(PrayerStore store) {
  final b = StringBuffer('# Prayer\n\n');
  void section(String title, List<Prayer> ps) {
    if (ps.isEmpty) return;
    b.writeln('## $title\n');
    for (final p in ps) {
      b.writeln('### ${p.title}\n');
      if (p.forWhom.isNotEmpty) b.writeln('For ${p.forWhom}  ');
      if (p.verse != null) b.writeln('${p.verse}  ');
      b.writeln(
        'Added ${_ymd(p.created)}, prayed on ${p.daysPrayed == 1 ? '1 day' : '${p.daysPrayed} days'}',
      );
      if (p.note.isNotEmpty) b.writeln('\n${p.note}');
      if (p.answered != null) {
        b.writeln('\nAnswered ${_ymd(p.answered!)}${p.answer == null ? '' : ': ${p.answer}'}');
      }
      b.writeln();
    }
  }

  section('Praying', store.praying());
  section('Answered', store.answered());
  section('No longer praying', store._query('p.archived = 1'));
  return b.toString();
}
