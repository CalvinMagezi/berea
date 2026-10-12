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
}
