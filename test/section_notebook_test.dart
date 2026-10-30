import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/section_notebook.dart';
import 'package:berea/study_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'commentary_test.dart' show writePack;
import 'support/bible.dart';

void main() {
  if (needsBuiltBible case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppState s;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('berea-section');
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
    s = await AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final james = Ref(bookById(59), 3, 1, 12);

  test(
    'a section becomes a notebook with its passage and key words kept as word studies',
    () async {
      final id = await makeSectionNotebook(s, james, 'Taming the Tongue');
      final notebook = s.notebooks.notebook(id)!;
      expect(notebook.title, 'Taming the Tongue (James 3:1-12)');
      expect(s.notebooks.sources(id).single.title, 'James 3:1-12 (${s.settings.translation})');
      final words = s.study.notebookNotes(id).where((n) => n.isKeptWord).toList();
      expect(words.length, s.studyPacket(id).keyWords.length);
      expect(words, isNotEmpty);
      expect(words.first.text, contains('From James 3:'));
      expect(words.first.verse, isNotNull);
    },
  );

  test('tapping it again opens the same notebook instead of making a copy', () async {
    final first = await makeSectionNotebook(s, james, 'Taming the Tongue');
    final again = await makeSectionNotebook(s, james, 'Taming the Tongue');
    expect(again, first);
    expect(s.notebooks.notebooks(), hasLength(1));
  });

  test('deleting it removes the word studies it added and keeps what the reader wrote', () async {
    final id = await makeSectionNotebook(s, james, 'Taming the Tongue');
    final added = s.study.notebookNotes(id).where((n) => n.isKeptWord).toList();
    expect(added.every((n) => n.kind == studyWordKind), isTrue);
    expect(s.notebooks.addedWords(id), added.length);
    final edited = added.first;
    s.study.updateNote(edited.id, '${edited.text}\nMy own thought.');
    final mine = s.study.addNotebookNote(id, 'The tongue is a fire.', title: 'Mine');
    s.notebooks.deleteNotebook(id);
    final home = StudyStore.notesOnVersesNotebook(s.study.db);
    final left = {for (final n in s.study.notebookNotes(home)) n.id: n};
    expect(left.keys, containsAll([edited.id, mine]));
    expect(left[edited.id]!.kind, keptWordKind, reason: 'edited, so it is the reader\'s');
    expect(left.values.where((n) => n.kind == studyWordKind), isEmpty);
  });

  test('tapping it again adds the commentaries installed since', () async {
    final id = await makeSectionNotebook(s, james, 'Taming the Tongue');
    expect(s.notebooks.sources(id), hasLength(1));
    final pack = writePack(dir, 'core', [
      ['MHCC', 59, 3, 1, 12, 'The tongue is a little member.'],
    ]);
    s.commentary.library.open('core', pack);
    await makeSectionNotebook(s, james, 'Taming the Tongue');
    final titles = [for (final r in s.notebooks.sources(id)) r.title];
    expect(titles, hasLength(2));
    expect(titles.last, contains('on James 3:1-12'));
    await makeSectionNotebook(s, james, 'Taming the Tongue');
    expect(s.notebooks.sources(id), hasLength(2), reason: 'never added twice');
  });
}
