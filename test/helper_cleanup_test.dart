import 'dart:io';

import 'package:berea/helper_cleanup.dart';
import 'package:berea/study_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('berea_cleanup'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the helper\'s folders and settings go, by name, and nothing else does', () async {
    SharedPreferences.setMockInitialValues({
      'helperWifiOnly': true,
      'termsAccepted': 2,
      'translation': 'KJV',
    });
    final prefs = await SharedPreferences.getInstance();
    File('${dir.path}/models/gemma/m.bin')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(1000, 1));
    File('${dir.path}/models/supertonic-3/v.onnx')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(500, 1));
    File('${dir.path}/listen/1/audio.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(250, 1));
    File('${dir.path}/study.sqlite').writeAsStringSync('notes');
    Directory('${dir.path}/imports').createSync();

    expect(await removeHelperFiles(dir, prefs), 1750);
    expect(Directory('${dir.path}/models').existsSync(), isFalse);
    expect(Directory('${dir.path}/listen').existsSync(), isFalse);
    expect(File('${dir.path}/study.sqlite').readAsStringSync(), 'notes');
    expect(Directory('${dir.path}/imports').existsSync(), isTrue);
    expect(prefs.containsKey('helperWifiOnly'), isFalse);
    expect(prefs.containsKey('termsAccepted'), isFalse);
    expect(prefs.getString('translation'), 'KJV');
    expect(await removeHelperFiles(dir, prefs), 0, reason: 'a second launch finds nothing');
  });

  test('the notice names only what was removed', () {
    expect(upgradeNoticeText(freedBytes: 0, chatsDeleted: 0), isNull);
    expect(
      upgradeNoticeText(freedBytes: 3 * 1024 * 1024 * 1024, chatsDeleted: 0),
      'The helper was removed. 3.0 GB freed.',
    );
    expect(
      upgradeNoticeText(freedBytes: 0, chatsDeleted: 4),
      'Saved questions and answers were deleted. Notes you kept from them are still in Notes.',
    );
    expect(upgradeNoticeText(freedBytes: 1073741824, chatsDeleted: 1), contains('1.0 GB freed. Saved'));
  });

  test('the store counts the conversations it deletes', () {
    final store = StudyStore(sqlite3.openInMemory());
    store.db.execute("INSERT INTO conversations(id, title, created, updated) VALUES (1, 'a', 1, 1), (2, 'b', 1, 1)");
    store.deleteChatTranscripts();
    expect(store.chatsDeleted, 2);
    expect(store.conversations(), isEmpty);
  });
}
