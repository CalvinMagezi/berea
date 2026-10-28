import 'dart:io';
import 'dart:typed_data';

import 'package:berea/app_state.dart';
import 'package:berea/backup.dart';
import 'package:berea/plans.dart';
import 'package:berea/study_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/bible.dart';

/// The version before chapter ticks: every migration up to Prayer.
const _beforeChapters = 4;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final plan = planById('nt-90')!;
  final days = plan.schedule();

  test('migration 4 turns each ticked day into its chapters and keeps the rest', () {
    final dir = Directory.systemTemp.createTempSync('berea-plan-chapters');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/study.sqlite';
    // A study.sqlite as Prayer left it, with two ticked days and a day of a retired plan.
    StudyStore(sqlite3.open(path)).db
      ..execute('DROP TABLE plan_chapters')
      // Migration 5 came later; take its columns off too.
      ..execute('DROP INDEX notebooks_system_key')
      ..execute('ALTER TABLE notebooks DROP COLUMN system_key')
      ..execute('ALTER TABLE notes DROP COLUMN kind')
      ..execute('PRAGMA user_version = $_beforeChapters')
      ..execute('''
        INSERT INTO plan_progress VALUES ('nt-90', 1, 100);
        INSERT INTO plan_progress VALUES ('nt-90', 3, 300);
        INSERT INTO plan_progress VALUES ('retired-plan', 2, 200);
      ''')
      ..dispose();

    final store = StudyStore(sqlite3.open(path));
    expect(store.db.select('PRAGMA user_version').single.values.single, StudyStore.schemaVersion);
    expect(store.planChaptersDone('nt-90'), {...days[0], ...days[2]});
    expect(store.planDaysDone('nt-90'), {1, 3});
    final kept = store.db.select('SELECT plan_id, day FROM plan_progress');
    expect([for (final r in kept) (r['plan_id'], r['day'])], [('retired-plan', 2)]);
    final stamps = store.db.select(
      'SELECT DISTINCT done_at FROM plan_chapters WHERE book = ? AND chapter = ?',
      [days[2].first.book.id, days[2].first.chapter],
    );
    expect(stamps.single['done_at'], 300, reason: 'the day\'s date carries over');
  });

  test('chapter ticks round trip in a backup, and an unticked chapter stays unticked', () async {
    final source = StudyStore(sqlite3.openInMemory());
    source.setPlanDay('nt-90', 1, true);
    source.setPlanChapter('nt-90', days[0].first, false);
    source.setPlanChapter('nt-90', days[1].first, true);

    final bytes = await createBackup(source, const {}, 'correct horse');
    final target = StudyStore(sqlite3.openInMemory());
    target.importTables((await readBackup(bytes, 'correct horse')).tables);

    expect(target.planChaptersDone('nt-90'), {...days[0].skip(1), days[1].first});
    expect(target.planDaysDone('nt-90'), isEmpty);
  });

  test('a backup from before chapter ticks restores its day ticks as chapters', () {
    final target = StudyStore(sqlite3.openInMemory());
    target.setPlanChapter('nt-90', days[5].first, true);
    target.importTables({
      'plan_progress': [
        {'plan_id': 'nt-90', 'day': 2, 'done_at': 20},
      ],
    });
    expect(target.planChaptersDone('nt-90'), days[1].toSet(), reason: 'replaced, not merged');
    expect(target.db.select('SELECT * FROM plan_progress'), isEmpty);
  });

  test('the shipped version 2 backup still restores', () async {
    final target = StudyStore(sqlite3.openInMemory());
    final old = await readBackup(
      File('test/fixtures/backup-v2.berea').readAsBytesSync(),
      'correct horse',
    );
    expect(old.tables.containsKey('plan_chapters'), isFalse);
    target.importTables(old.tables);
    final ticked = {for (final r in old.tables['plan_progress'] ?? const []) r['day'] as int};
    expect(target.planDaysDone('nt-90'), ticked);
  });

  test('chapter rows that do not fit are rejected before anything changes', () {
    final store = StudyStore(sqlite3.openInMemory());
    store.setPlanChapter('nt-90', days[0].first, true);
    for (final bad in [
      {'plan_id': 'nt-90', 'book': 99, 'chapter': 1},
      {'plan_id': 'nt-90', 'book': 40, 'chapter': 'one'},
      {'plan_id': 7, 'book': 40, 'chapter': 1},
    ]) {
      expect(
        () => store.importTables({
          'plan_chapters': [bad],
        }),
        throwsFormatException,
      );
    }
    expect(store.planChaptersDone('nt-90'), {days[0].first});
  });

  group('on a new phone', skip: needsBuiltBible, () {
    late Directory dir;
    late AppState s;
    final started = DateTime(2026, 10, 1, 7);

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('berea-plan-restore');
      SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
      s = await AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
      s.startPlan(plan);
      s.prefs.setString('activePlanStart', started.toIso8601String());
      s.study.setPlanDay(plan.id, 1, true);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    /// What a phone with nothing on it is left with once [backup] is restored.
    Future<void> restoreOnEmptyPhone(Uint8List backup) async {
      s.stopPlan();
      s.study.clearPlan(plan.id);
      s.applyBackup(await s.openBackup(backup, 'correct horse'));
    }

    test('a restore brings back the running plan, its start and its ticks', () async {
      await restoreOnEmptyPhone(await s.backup('correct horse'));
      expect(s.activePlan?.id, plan.id);
      expect(s.planStart, started);
      expect(s.study.planChaptersDone(plan.id), days[0].toSet());
    });

    test('starting the plan again after an older restore keeps its ticks', () async {
      final older = await createBackup(s.study, const {}, 'correct horse');
      await restoreOnEmptyPhone(older);
      expect(s.activePlan, isNull);
      s.startPlan(plan);
      expect(s.study.planChaptersDone(plan.id), days[0].toSet());
    });

    test('switching from a running plan still starts the new one afresh', () {
      final other = planById('gospels-30')!;
      s.study.setPlanDay(other.id, 1, true);
      s.startPlan(other);
      expect(s.study.planChaptersDone(other.id), isEmpty);
    });
  });
}
