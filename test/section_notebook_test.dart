import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/section_notebook.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
