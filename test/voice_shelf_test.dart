import 'dart:convert';
import 'dart:io';

import 'package:berea/voice.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:berea/pinned_download.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Future<VoicePackFile> _pin(String name, List<int> bytes) async => VoicePackFile(
  name: name,
  role: VoiceFileRole.voice,
  sha256: hexOf((await Sha256().hash(bytes)).bytes),
  bytes: bytes.length,
  upstream: 'https://example.invalid/$name',
  licence: 'test',
);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('voice_shelf'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String name, List<int> bytes) => File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  test('installs picked files only when size and SHA-256 match a pin', () async {
    final a = utf8.encode('first voice');
    final b = utf8.encode('other voice');
    final shelf = VoiceShelf(
      Directory('${tmp.path}/shelf'),
      () {},
      files: [await _pin('a.bin', a), await _pin('b.bin', b)],
    );
    expect(shelf.installed, isFalse);
    final added = await shelf.installFromFiles([
      write('renamed.bin', b).path,
      // Same size as both pins but different bytes: ignored.
      write('forged.bin', utf8.encode('third voice')).path,
      write('unrelated.txt', utf8.encode('nothing')).path,
    ]);
    expect(added, ['b.bin']);
    expect(shelf.missing.map((f) => f.name), ['a.bin']);
    expect(File('${tmp.path}/shelf/b.bin').readAsBytesSync(), b);
    expect(Directory('${tmp.path}/shelf').listSync().map((e) => e.uri.pathSegments.last), [
      'b.bin',
    ]);

    await shelf.installFromFiles([write('a-copy.bin', a).path]);
    expect(shelf.installed, isTrue);
    shelf.delete();
    expect(shelf.installed, isFalse);
  });

  test('clears half-finished files left by an earlier run', () {
    final dir = Directory('${tmp.path}/shelf')..createSync();
    File('${dir.path}/model.onnx.part').writeAsStringSync('partial');
    VoiceShelf(dir, () {}, files: const []);
    expect(dir.listSync(), isEmpty);
  });
}
