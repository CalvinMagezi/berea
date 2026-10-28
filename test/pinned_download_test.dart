import 'dart:async';
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
          case '/stalls':
            res.bufferOutput = false;
            res.add(body.sublist(0, 8));
            await res.flush();
            await Future<void>.delayed(_timeout);
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
    onProgress: progress == null ? null : (received, total) => progress.add(received / total!),
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

    test('a stopped download ends at once and leaves neither file behind', () async {
      final stop = Completer<void>();
      final bytes = <int>[];
      final fetching = downloadModelFile(
        url('/stalls'),
        Directory('${dir.path}/models'),
        'm.litertlm',
        sha256: pin,
        bytes: body.length,
        timeout: _timeout,
        stop: stop.future,
        onProgress: (received, total) {
          bytes.add(received);
          if (!stop.isCompleted) stop.complete();
        },
      );
      await expectLater(fetching, throwsA(isA<DownloadStopped>()));
      expect(bytes, [8], reason: 'progress is in bytes received');
      expect(Directory('${dir.path}/models').listSync(), isEmpty);
    });

    test('a failed check leaves neither the file nor the partial one', () async {
      await expectLater(fetchModel('/ok', sha: '0' * 64), throwsFormatException);
      expect(Directory('${dir.path}/models').listSync(), isEmpty);
    });

    test('a file already there with the pinned hash is not fetched again', () async {
      await fetchModel('/ok');
      final unreachable = Uri.parse('http://127.0.0.1:1/never');
      final again = await fetchModel('/ok', from: unreachable);
      expect(again.readAsBytesSync(), body);
    });

    test('a file of the same size under another pin is fetched again', () async {
      final file = await fetchModel('/ok');
      file.writeAsBytesSync(List.filled(body.length, 7));
      File('${file.path}.sha256').writeAsStringSync('f' * 64);
      expect(hostedModelCurrent(file, sha256: pin, bytes: body.length), isFalse);
      final again = await fetchModel('/ok');
      expect(again.readAsBytesSync(), body);
      expect(hostedModelCurrent(again, sha256: pin, bytes: body.length), isTrue);
    });

    test('a recheck replaces a stamped file that no longer matches its hash', () async {
      final file = await fetchModel('/ok');
      file.writeAsBytesSync(List.filled(body.length, 7));
      expect(hostedModelCurrent(file, sha256: pin, bytes: body.length), isTrue);

      final untouched = await downloadModelFile(
        url('/missing'),
        Directory('${dir.path}/models'),
        'm.litertlm',
        sha256: pin,
        bytes: body.length,
        timeout: _timeout,
      );
      expect(untouched.readAsBytesSync(), List.filled(body.length, 7));

      final repaired = await downloadModelFile(
        url('/ok'),
        Directory('${dir.path}/models'),
        'm.litertlm',
        sha256: pin,
        bytes: body.length,
        timeout: _timeout,
        recheck: true,
      );
      expect(repaired.readAsBytesSync(), body);
    });

    test('a recheck leaves a file that still matches alone', () async {
      await fetchModel('/ok');
      final again = await downloadModelFile(
        Uri.parse('http://127.0.0.1:1/never'),
        Directory('${dir.path}/models'),
        'm.litertlm',
        sha256: pin,
        bytes: body.length,
        timeout: _timeout,
        recheck: true,
      );
      expect(again.readAsBytesSync(), body);
    });

    test('the notice is written beside the models, and only once', () {
      final models = Directory('${dir.path}/models');
      writeModelNotice(models, 'Gemma is provided under terms.');
      final file = File('${models.path}/NOTICE');
      expect(file.readAsStringSync(), 'Gemma is provided under terms.\n');
      final stamp = file.lastModifiedSync();
      writeModelNotice(models, 'Gemma is provided under terms.');
      expect(file.lastModifiedSync(), stamp);
    });

    test('a file with no stamp is not trusted, whatever its size', () async {
      final file = File('${dir.path}/models/m.litertlm')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(body.length, 7));
      expect(hostedModelCurrent(file, sha256: pin, bytes: body.length), isFalse);
    });
  });
}
