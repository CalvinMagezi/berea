import 'package:berea/practice_store.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late StudyStore study;
  late PracticeStore practice;
  setUp(() {
    study = StudyStore(sqlite3.openInMemory());
    practice = PracticeStore(study.db);
  });

  test('a set keeps its references in order, and is shown by its title or its references', () {
    final refs = RefParser.parse('John 3:16-18; Psalm 23; Romans 8:28');
    final id = practice.saveSet(refs)!;
    final set = practice.set(id)!;
    expect(set.refs.map((r) => r.label), ['John 3:16-18', 'Psalms 23', 'Romans 8:28']);
    expect(set.label, 'John 3:16-18; Psalms 23; Romans 8:28');
    practice.rename(id, '  Favourites ');
    expect(practice.set(id)!.label, 'Favourites');
    practice.rename(id, '');
    expect(practice.set(id)!.title, isNull);
    expect(practice.saveSet(const []), isNull);
    expect(practice.sets(), hasLength(1));
    practice.delete(id);
    expect(practice.sets(), isEmpty);
    expect(study.db.select('SELECT 1 FROM practice_set_refs'), isEmpty);
  });

  test('sets and items round trip in a backup', () {
    practice.saveSet(RefParser.parse('John 3:16').first.let((r) => [r]), title: 'One');
    study.db.execute(
      "INSERT INTO practice_items(book, chapter, verse_start, verse_end, translation, due_day) "
      "VALUES (43, 3, 16, 16, 'BSB', 20000)",
    );
    final tables = study.exportTables();
    expect(tables.keys, containsAll(practiceTables));
    final other = StudyStore(sqlite3.openInMemory());
    other.importTables(tables);
    expect(PracticeStore(other.db).sets().single.title, 'One');
    expect(other.db.select('SELECT rung FROM practice_items').single['rung'], 0);
  });

  test('restoring a backup from before Practice leaves the sets and items alone', () {
    practice.saveSet(RefParser.parse('Psalm 23').toList(), title: 'Keep');
    study.importTables({
      'notes': [
        {'id': 1, 'text': 'x', 'updated': 1},
      ],
    });
    expect(practice.sets().single.title, 'Keep');
  });

  test('a backup with a set that cannot be shown is refused before anything changes', () {
    practice.saveSet(RefParser.parse('Psalm 23').toList(), title: 'Keep');
    for (final bad in [
      {
        'practice_sets': [
          {'id': 1, 'made_by': 'robot', 'created': 1, 'archived': 0},
        ],
      },
      {
        'practice_set_refs': [
          {'set_id': 9, 'pos': 0, 'book': 19, 'chapter': 23},
        ],
      },
      {
        'practice_sets': [
          {'id': 1, 'made_by': 'person', 'created': 1, 'archived': 0},
        ],
        'practice_set_refs': [
          {'set_id': 1, 'pos': 0, 'book': 99, 'chapter': 1},
        ],
      },
    ]) {
      expect(() => study.importTables(bad), throwsFormatException);
    }
    expect(practice.sets().single.title, 'Keep');
  });
}

extension on Ref {
  T let<T>(T Function(Ref) f) => f(this);
}
