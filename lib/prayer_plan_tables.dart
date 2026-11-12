/// The prayer plan tables, kept so an older database and an older backup still open: Berea no
/// longer has prayer plans, and nothing reads or writes these rows. Study store migration 7: a prayer can be matched to a topic, prayer plans keep their runs and
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
    for (final column in ['started', 'finished']) {
      if (r[column] != null) _checkMs(r[column], 'prayer plan ${r['plan_id']} $column');
    }
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
  for (final table in const ['prayer_plan_days', 'plan_prayed']) {
    for (final r in tables[table] ?? const <Map<String, Object?>>[]) {
      if (table == 'prayer_plan_days' && !planIds.contains(r['plan_id'])) {
        throw FormatException('prayer plan day ${r['day']} has no plan');
      }
      _checkMs(r['done_at'], '$table ${r['plan_id']} ${r['day']}');
    }
  }
}

/// The latest instant a [DateTime] can hold, in milliseconds.
const _maxEpochMs = 8640000000000000;

void _checkMs(Object? v, String what) {
  if (v is! int || v < 0 || v > _maxEpochMs) throw FormatException('$what has a bad date');
}

