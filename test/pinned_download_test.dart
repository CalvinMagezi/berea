import 'dart:io';

import 'package:berea/pinned_download.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

const _maxBytes = 64;
const _timeout = Duration(seconds: 5);

void main() {
  final body = List<int>.generate(48, (i) => i);
  late String pin;
  late HttpServer server;
  late Directory dir;

  setUpAll(() async => pin = hexOf((await Sha256().hash(body)).bytes));

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('pinned');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      // The client hangs up once the cap trips, so a late write here is expected to fail.
      try {
        switch (req.uri.path) {
          case '/ok':
            res.contentLength = body.length;
            res.add(body);
          case '/declared-too-big':
            res.contentLength = _maxBytes + 1;
            res.add(List.filled(_maxBytes + 1, 0));
          case '/streams-too-big':
            for (var i = 0; i < 4; i++) {
              res.add(List.filled(_maxBytes ~/ 2, 0));
              await res.flush();
            }
          default:
            res.statusCode = HttpStatus.notFound;
        }
        await res.close();
      } on IOException {
        return;
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  Future<void> fetch(String path, {String? sha, List<double>? progress}) => downloadPinned(
    Uri.parse('http://${server.address.host}:${server.port}$path'),
    File('${dir.path}/out.part'),
    sha256: sha ?? pin,
    maxBytes: _maxBytes,
    timeout: _timeout,
    onProgress: progress?.add,
  );

  test('writes the file when the hash matches, reporting progress up to 1', () async {
    final progress = <double>[];
    await fetch('/ok', progress: progress);
    expect(File('${dir.path}/out.part').readAsBytesSync(), body);
    expect(progress.last, 1.0);
  });

  test('refuses a file whose hash differs from the pin', () async {
    await expectLater(fetch('/ok', sha: '0' * 64), throwsFormatException);
  });

  test('refuses a file declared larger than the cap before reading it', () async {
    await expectLater(fetch('/declared-too-big'), throwsFormatException);
  });

  test('stops a file that grows past the cap with no declared length', () async {
    await expectLater(fetch('/streams-too-big'), throwsFormatException);
  });

  test('reports an HTTP error as such', () async {
    await expectLater(fetch('/missing'), throwsA(isA<HttpException>()));
  });

  group('a pinned model file', () {
    Uri url(String path) => Uri.parse('http://${server.address.host}:${server.port}$path');

    Future<File> fetchModel(String path, {String? sha, Uri? from}) => downloadModelFile(
      from ?? url(path),
      Directory('${dir.path}/models'),
      'm.litertlm',
      sha256: sha ?? pin,
      bytes: body.length,
      timeout: _timeout,
    );

    test('lands under its own name with no partial file left', () async {
      final file = await fetchModel('/ok');
      expect(file.readAsBytesSync(), body);
      expect(file.path, '${dir.path}/models/m.litertlm');
      expect(File('${file.path}.part').existsSync(), isFalse);
    });

    test('a failed check leaves neither the file nor the partial one', () async {
      await expectLater(fetchModel('/ok', sha: '0' * 64), throwsFormatException);
      expect(Directory('${dir.path}/models').listSync(), isEmpty);
    });

    test('a file already there at the right size is not fetched again', () async {
      await fetchModel('/ok');
      final unreachable = Uri.parse('http://127.0.0.1:1/never');
      final again = await fetchModel('/ok', from: unreachable);
      expect(again.readAsBytesSync(), body);
    });
  });
}
