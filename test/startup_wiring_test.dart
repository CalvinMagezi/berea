import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('berea-startup-test');
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a notes safety copy that cannot be written stops the start in plain words', () async {
    final path = '${dir.path}/study.sqlite';
    // Notes from before the merge, at schema version 0.
    sqlite3.open(path)
      ..execute(
        'CREATE TABLE notes(id INTEGER PRIMARY KEY, book INTEGER, chapter INTEGER, '
        'verse_start INTEGER, verse_end INTEGER, text TEXT, created INTEGER, updated INTEGER)',
      )
      ..execute("INSERT INTO notes VALUES (1, 43, 3, 16, 16, 'Love given.', 1, 1)")
      ..dispose();
    // A directory where the copy goes makes it fail.
    Directory('$path$preNotesMergeSuffix.partial').createSync();

    await expectLater(
      AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance()),
      throwsA(isA<StartupFailure>().having((f) => f.message, 'message', notesCopyFailed)),
    );
    final raw = sqlite3.open(path);
    expect(raw.select('PRAGMA user_version').first.values.first, 0, reason: 'nothing migrated');
    raw.dispose();
  });

  test('a first note on a verse shows its notebook to anyone listening', () async {
    final s = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
    );
    var heard = 0;
    s.notebooks.addListener(() => heard++);
    s.study.addNote(RefParser.parse('John 3:16').single, 'Love given.');
    s.touch();
    expect(heard, 1);
    expect(s.notebooks.notebooks().map((n) => n.title), contains(notesOnVersesTitle));
  });
}
