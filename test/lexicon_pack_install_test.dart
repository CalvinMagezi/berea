import 'dart:io';
import 'dart:typed_data';

import 'package:berea/app_state.dart';
import 'package:berea/share_berea.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/bible.dart';

void main() {
  if (needsBibleText case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureBereaDbAssets();

  test('a lexicon pack passed by hand is checked against the published hash before it is installed', () async {
    final dir = Directory.systemTemp.createTempSync('berea-packs');
    addTearDown(() => dir.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});
    final s = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      prayerContent: PrayerContent.empty,
    );
    final notThePack = Uint8List.fromList(List.filled(64, 7));
    await expectLater(
      s.installMiddleLiddellPack(bytes: notThePack),
      throwsA(isA<ReaderMessage>()),
    );
    await expectLater(s.installLexiconPack(bytes: notThePack), throwsA(isA<ReaderMessage>()));
    expect(s.db.hasMiddleLiddell, isFalse);
    expect(s.db.hasFullLexicon, isFalse);
    expect(File(s.middleLiddellPackPath).existsSync(), isFalse);
  });

  test('the packs a reader holds are offered for sharing, and none when nothing is installed', () async {
    final dir = Directory.systemTemp.createTempSync('berea-share');
    addTearDown(() => dir.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});
    final s = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
      prayerContent: PrayerContent.empty,
    );
    expect(sharePacks(s), isEmpty);
    sqlite3.open(s.middleLiddellPackPath)
      ..execute('CREATE TABLE lexicon_ml(key TEXT PRIMARY KEY, base TEXT, definition TEXT)')
      ..dispose();
    s.db.attachMiddleLiddell(s.middleLiddellPackPath);
    expect(sharePacks(s).map((p) => p.label), ['Middle Liddell definitions']);
    expect(sharePacks(s).single.path, s.middleLiddellPackPath);
  });
}
