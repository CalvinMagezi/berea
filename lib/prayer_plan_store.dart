import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// Study store migration 7: a prayer can be matched to a topic, prayer plans keep their runs and
/// the days prayed, and a reading plan keeps the days whose prayer step is done. Only new tables
/// and a nullable column, so an older Berea opens the file and ignores them.
const prayerPlanSchema = '''
  ALTER TABLE prayers ADD COLUMN topic TEXT;
  CREATE TABLE IF NOT EXISTS prayer_plan_runs(plan_id TEXT PRIMARY KEY, started INTEGER NOT NULL,
    fasting INTEGER NOT NULL DEFAULT 0, prayer_id INTEGER, finished INTEGER) WITHOUT ROWID;
  CREATE TABLE IF NOT EXISTS prayer_plan_days(plan_id TEXT NOT NULL, day INTEGER NOT NULL,
    done_at INTEGER NOT NULL, PRIMARY KEY(plan_id, day)) WITHOUT ROWID;
  CREATE TABLE IF NOT EXISTS plan_prayed(plan_id TEXT NOT NULL, day INTEGER NOT NULL,
    done_at INTEGER NOT NULL, PRIMARY KEY(plan_id, day)) WITHOUT ROWID;
''';

/// The plan tables in backup order: a run before the days that belong to it.
const prayerPlanTables = ['prayer_plan_runs', 'prayer_plan_days', 'plan_prayed'];

const prayerPlanColumnTypes = <String, Map<String, Type>>{
  'prayer_plan_runs': {'plan_id': String, 'started': int, 'fasting': int},
  'prayer_plan_days': {'plan_id': String, 'day': int, 'done_at': int},
  'plan_prayed': {'plan_id': String, 'day': int, 'done_at': int},
};

/// Throws [FormatException] when a backed-up plan day belongs to no run or a flag or date is the
/// wrong type. A link to a prayer the backup lacks is not refused: an older Berea could delete a
/// linked prayer, and the restore drops the link.
void validatePrayerPlanTables(Map<String, List<Map<String, Object?>>> tables) {
  final runs = tables['prayer_plan_runs'] ?? const <Map<String, Object?>>[];
  final planIds = {for (final r in runs) r['plan_id']};
  for (final r in runs) {
    if (r['fasting'] != 0 && r['fasting'] != 1) {
      throw FormatException('prayer plan ${r['plan_id']} has a bad fasting flag');
    }
    final linked = r['prayer_id'];
    if (linked != null && linked is! int) {
      throw FormatException('prayer plan ${r['plan_id']} has a bad prayer link');
    }
    final finished = r['finished'];
    if (finished != null && finished is! int) {
      throw FormatException('prayer plan ${r['plan_id']} has a bad finished date');
    }
  }
  for (final r in tables['prayer_plan_days'] ?? const <Map<String, Object?>>[]) {
    if (!planIds.contains(r['plan_id'])) {
      throw FormatException('prayer plan day ${r['day']} has no plan');
    }
  }
}

/// A prayer plan the reader has started.
class PlanRun {
  final String planId;
  final DateTime started;
  final bool fasting;

  /// The reader's own prayer linked to this plan, or null.
  final int? prayerId;
  final DateTime? finished;
  const PlanRun({
    required this.planId,
    required this.started,
    required this.fasting,
    this.prayerId,
    this.finished,
  });
}

/// Progress through prayer plans, and the prayer step of reading plans. Counts days prayed,
/// never days in a row: a missed day is picked up where it was.
class PrayerPlanStore extends ChangeNotifier {
  final Database db;
  final DateTime Function() now;
  PrayerPlanStore(this.db, {DateTime Function()? now}) : now = now ?? DateTime.now;

  int _nowMs() => now().millisecondsSinceEpoch;

  /// Tells the screens to read again after a restore replaced the rows underneath.
  void refresh() => notifyListeners();

  PlanRun _run(Row r) => PlanRun(
    planId: r['plan_id'] as String,
    started: DateTime.fromMillisecondsSinceEpoch(r['started'] as int),
    fasting: r['fasting'] == 1,
    prayerId: r['prayer_id'] as int?,
    finished: r['finished'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['finished'] as int),
  );

  /// Plans being prayed, oldest start first. A finished plan is kept but not listed.
  List<PlanRun> running() => [
    for (final r in db.select(
      'SELECT * FROM prayer_plan_runs WHERE finished IS NULL ORDER BY started, plan_id',
    ))
      _run(r),
  ];

  /// Every run, finished ones too, oldest start first.
  List<PlanRun> all() => [
    for (final r in db.select('SELECT * FROM prayer_plan_runs ORDER BY started, plan_id')) _run(r),
  ];

  /// Days whose Pray what you read step is done, for each reading plan that has any.
  Map<String, int> readingCounts() => {
    for (final r in db.select(
      'SELECT plan_id, COUNT(*) AS n FROM plan_prayed GROUP BY plan_id ORDER BY plan_id',
    ))
      r['plan_id'] as String: r['n'] as int,
  };

  PlanRun? run(String planId) => [
    for (final r in db.select('SELECT * FROM prayer_plan_runs WHERE plan_id = ?', [planId]))
      _run(r),
  ].firstOrNull;

  Set<int> daysPrayed(String planId) => {
    for (final r in db.select('SELECT day FROM prayer_plan_days WHERE plan_id = ?', [planId]))
      r['day'] as int,
  };

  /// The first day not yet prayed, from 1, or null when every day of [days] is done.
  int? currentDay(String planId, int days) {
    final done = daysPrayed(planId);
    for (var d = 1; d <= days; d++) {
      if (!done.contains(d)) return d;
    }
    return null;
  }

  /// Begins [planId] from day 1. A plan already run starts again with no days.
  void start(String planId) {
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM prayer_plan_days WHERE plan_id = ?', [planId]);
      db.execute('DELETE FROM prayer_plan_runs WHERE plan_id = ?', [planId]);
      db.execute('INSERT INTO prayer_plan_runs(plan_id, started) VALUES (?, ?)', [
        planId,
        _nowMs(),
      ]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    notifyListeners();
  }

  /// Stop praying the plan: the run and its days go. Nothing else is touched.
  void stop(String planId) {
    db.execute('DELETE FROM prayer_plan_days WHERE plan_id = ?', [planId]);
    db.execute('DELETE FROM prayer_plan_runs WHERE plan_id = ?', [planId]);
    notifyListeners();
  }

  /// Amen on [day] of a plan of [days] days. The last day finishes the plan.
  void pray(String planId, int day, int days) {
    db.execute('INSERT OR IGNORE INTO prayer_plan_days(plan_id, day, done_at) VALUES (?, ?, ?)', [
      planId,
      day,
      _nowMs(),
    ]);
    if (currentDay(planId, days) == null) {
      db.execute('UPDATE prayer_plan_runs SET finished = ? WHERE plan_id = ?', [_nowMs(), planId]);
    }
    notifyListeners();
  }

  void setFasting(String planId, bool on) {
    db.execute('UPDATE prayer_plan_runs SET fasting = ? WHERE plan_id = ?', [on ? 1 : 0, planId]);
    notifyListeners();
  }

  void linkPrayer(String planId, int? prayerId) {
    db.execute('UPDATE prayer_plan_runs SET prayer_id = ? WHERE plan_id = ?', [prayerId, planId]);
    notifyListeners();
  }

  /// Days of a reading plan whose Pray what you read step is done.
  Set<int> readingPrayed(String planId) => {
    for (final r in db.select('SELECT day FROM plan_prayed WHERE plan_id = ?', [planId]))
      r['day'] as int,
  };

  void prayReading(String planId, int day) {
    db.execute('INSERT OR IGNORE INTO plan_prayed(plan_id, day, done_at) VALUES (?, ?, ?)', [
      planId,
      day,
      _nowMs(),
    ]);
    notifyListeners();
  }

  /// A reading plan started again begins with no prayer steps done.
  void clearReading(String planId) {
    db.execute('DELETE FROM plan_prayed WHERE plan_id = ?', [planId]);
    notifyListeners();
  }
}
