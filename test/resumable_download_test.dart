import 'dart:async';
import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/edge_engine.dart';
import 'package:berea/models.dart';
import 'package:berea/pinned_download.dart';
import 'package:berea/voice.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _size = 4096;
const _dropAt = 1000;
const _timeout = Duration(seconds: 5);
const _name = 'm.litertlm';

/// A file server that answers Range requests, and can be told to misbehave as real ones do.
class _Server {
  final List<int> body;
  late final HttpServer _http;
  String etag = '"v1"';
  bool ignoreRange = false;

  /// Sends a 206 that starts at the beginning, whatever was asked.
  bool wrongStart = false;

  /// Hangs up after this many bytes of the next response.
  int? dropAfter;

  /// Serves these bytes in place of [body] for the next response.
  List<int>? servedOnce;

  final ranges = <String?>[];
  final ifRanges = <String?>[];
  final statuses = <int>[];

  _Server(this.body);

  Uri get url => Uri.parse('http://${_http.address.host}:${_http.port}/model');

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen(_serve);
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    final range = req.headers.value('range');
    final ifRange = req.headers.value('if-range');
    ranges.add(range);
    ifRanges.add(ifRange);
    final served = servedOnce ?? body;
    servedOnce = null;
    final asked = range == null
        ? null
        : RegExp(r'^bytes=(\d+)-$').firstMatch(range);
    final honour =
        asked != null && !ignoreRange && (ifRange == null || ifRange == etag);
    var start = honour ? int.parse(asked.group(1)!) : 0;
    if (honour && start >= served.length) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      statuses.add(res.statusCode);
      await res.close();
      return;
    }
    if (honour && wrongStart) start = 0;
    if (honour) {
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
        'content-range',
        'bytes $start-${served.length - 1}/${served.length}',
      );
    }
    statuses.add(res.statusCode);
    res.headers.set('etag', etag);
    final data = served.sublist(start);
    res.contentLength = data.length;
    if (dropAfter case final cut?) {
      dropAfter = null;
      final socket = await res.detachSocket();
      socket.add(data.sublist(0, cut));
      await socket.flush();
      socket.destroy();
      return;
    }
    res.add(data);
    await res.close();
  }

  Future<void> close() => _http.close(force: true);
}

class _NoRecorder implements AudioRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// How long a test waits before a download that lost its connection tries again.
const _retry = Duration(milliseconds: 40);

void main() {
  // The restart cases open the real app, which needs the binding; its stand-in HTTP client would
  // answer the local server with 400s, so the real one is put back.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final body = List<int>.generate(_size, (i) => (i * 31 + 7) % 256);
  late String pin;
  late _Server server;
  late Directory dir;

  setUpAll(() async => pin = hexOf((await Sha256().hash(body)).bytes));

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('resumable');
    server = _Server(body);
    await server.start();
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Directory models() => Directory('${dir.path}/models');

  Future<File> fetch({List<int>? progress, Future<void>? stop}) =>
      downloadModelFile(
        server.url,
        models(),
        _name,
        sha256: pin,
        bytes: _size,
        timeout: _timeout,
        stop: stop,
        onProgress: progress == null
            ? null
            : (received, _) => progress.add(received),
      );

  /// A first try that loses the connection after [_dropAt] bytes.
  Future<void> dropped() async {
    server.dropAfter = _dropAt;
    await expectLater(fetch(), throwsA(isA<http.ClientException>()));
  }

  test('a dropped connection keeps the bytes that arrived', () async {
    await dropped();
    expect(partialDownload(models(), _name), (bytes: _dropAt, total: _size));
  });

  test(
    'a resume asks for the rest only, against the same file, and finishes it',
    () async {
      await dropped();
      final progress = <int>[];
      final file = await fetch(progress: progress);
      expect(server.ranges.last, 'bytes=$_dropAt-');
      expect(server.ifRanges.last, '"v1"');
      expect(server.statuses.last, HttpStatus.partialContent);
      expect(
        progress.first,
        greaterThan(_dropAt),
        reason: 'counted from the bytes on disk',
      );
      expect(file.readAsBytesSync(), body);
      expect(partialDownload(models(), _name), isNull);
      expect(hostedModelCurrent(file, sha256: pin, bytes: _size), isTrue);
    },
  );

  test(
    'a server that ignores the Range starts the file again cleanly',
    () async {
      await dropped();
      server.ignoreRange = true;
      final file = await fetch();
      expect(server.ranges.last, 'bytes=$_dropAt-');
      expect(server.statuses.last, HttpStatus.ok);
      expect(file.readAsBytesSync(), body);
    },
  );

  test(
    'a file changed since the part began is fetched again from the start',
    () async {
      await dropped();
      server.etag = '"v2"';
      final file = await fetch();
      expect(server.ifRanges.last, '"v1"');
      expect(server.statuses.last, HttpStatus.ok);
      expect(file.readAsBytesSync(), body);
    },
  );

  test('a 206 that starts somewhere else is refused and the file is asked for whole', () async {
    await dropped();
    server.wrongStart = true;
    final file = await fetch();
    expect(
      server.ranges.last,
      isNull,
      reason: 'the second try asks for the whole file',
    );
    expect(file.readAsBytesSync(), body);
  });

  test(
    'a part complete before the app closed is checked without fetching again',
    () async {
      await dropped();
      File('${models().path}/$_name.part')
          .writeAsBytesSync(body.sublist(_dropAt), mode: FileMode.append);
      final file = await fetch();
      expect(server.statuses.last, HttpStatus.requestedRangeNotSatisfiable);
      expect(file.readAsBytesSync(), body);
    },
  );

  test('a stop keeps the part for the next try', () async {
    final stop = Completer<void>();
    server.dropAfter = null;
    await expectLater(
      downloadModelFile(
        server.url,
        models(),
        _name,
        sha256: pin,
        bytes: _size,
        timeout: _timeout,
        stop: stop.future,
        onProgress: (_, _) {
          if (!stop.isCompleted) stop.complete();
        },
      ),
      throwsA(isA<DownloadStopped>()),
    );
    expect(partialDownload(models(), _name)?.bytes, greaterThan(0));
  });

  test('Pause or Cancel while the last bytes are checked keeps it a part, not the model', () async {
    final stop = Completer<void>();
    final check = hashCheck;
    addTearDown(() => hashCheck = check);
    hashCheck = (file, sha) {
      stop.complete();
      return check(file, sha);
    };
    await expectLater(
      fetch(stop: stop.future),
      throwsA(isA<DownloadStopped>()),
    );
    expect(File('${models().path}/$_name').existsSync(), isFalse);
    expect(partialDownload(models(), _name)?.bytes, _size);
  });

  test('a wrong byte is refused and the part removed, so the next try starts fresh', () async {
    server.servedOnce = [...body]..[_size ~/ 2] ^= 0xff;
    await expectLater(fetch(), throwsA(isA<DownloadDamaged>()));
    expect(models().listSync(), isEmpty);
  });

  test('a file of the wrong size is refused and removed', () async {
    server.servedOnce = body.sublist(0, _size - 1);
    await expectLater(fetch(), throwsA(isA<DownloadDamaged>()));
    expect(models().listSync(), isEmpty);
  });

  test('Cancel removes the part', () async {
    await dropped();
    discardPartial(models(), _name);
    expect(models().listSync(), isEmpty);
  });

  test('the older copy goes only once a checked file is there to replace it', () {
    final copy = File('${dir.path}/plugin/$_name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(body);
    final verified = File('${models().path}/$_name');
    dropPluginCopy(copy, verified: verified);
    expect(copy.existsSync(), isTrue, reason: 'no replacement yet');

    verified
      ..createSync(recursive: true)
      ..writeAsBytesSync(body);
    dropPluginCopy(verified, verified: verified);
    expect(verified.existsSync(), isTrue, reason: 'never the file in use');

    dropPluginCopy(copy, verified: verified);
    expect(copy.existsSync(), isFalse);
    expect(verified.existsSync(), isTrue);
  });

  group('across a restart', () {
    final m = edgeModelById('gemma-4-e2b');
    late StreamController<bool> network;
    late int downloads;

    /// The device has no connection at all, so a download fails at once.
    var offline = false;

    /// Leaves a part of [_dropAt] bytes of [model] on disk, as a dropped connection does.
    Future<void> partOf(EdgeModel model) async {
      server.dropAfter = _dropAt;
      await downloadModelFile(
        server.url,
        models(),
        model.file,
        sha256: pin,
        bytes: _size,
        timeout: _timeout,
      ).then((_) {}, onError: (_) {});
    }

    /// The real start of the app over [dir], with a download of [m] left [how] and a part of
    /// [_dropAt] bytes of [_size] on disk.
    Future<AppState> relaunch(
      KeptDownload how, {
      required bool mobile,
      EdgeModel? kept,
    }) async {
      await partOf(m);
      SharedPreferences.setMockInitialValues({
        'engine': EngineKind.device.name,
        'deviceModelId': m.id,
        keptDownloadKey: [(kept ?? m).id, how.name],
      });
      network = StreamController<bool>();
      downloads = 0;
      final s = await AppState.bootstrap(
        supportDir: dir,
        prefs: await SharedPreferences.getInstance(),
      );
      s
        ..mobileDataNow = (() async => mobile)
        ..mobileDataChanges = (() => network.stream)
        ..voice = VoiceInput(
          transcribe: (_) async => '',
          recorder: _NoRecorder(),
          cacheDir: () async => dir,
        )
        ..modelInstalled = ((_, _) async => false)
        ..networkRetry = _retry
        ..modelDownload =
            (
              m, {
              required modelsDir,
              required onProgress,
              stop,
              recheck = false,
            }) async {
              downloads++;
              if (offline) throw const SocketException('No connection');
              await stop;
              throw const DownloadStopped();
            };
      await s.startHelper();
      await pumpEventQueue();
      return s;
    }

    setUp(() => offline = false);

    // Nothing listens to the network in a paused download, so its close is not awaited.
    tearDown(() => unawaited(network.close()));

    test('a download held for Wi-Fi comes back held with its bytes, and goes on with Wi-Fi', () async {
      final s = await relaunch(KeptDownload.waitingForWifi, mobile: true);
      final h = s.helperState as HelperDownloading;
      expect(h.waitingForWifi, isTrue);
      expect(h.bytes, _dropAt);
      expect(h.total, _size);
      expect(downloads, 0, reason: 'still on mobile data');

      s.mobileDataNow = () async => false;
      network.add(false);
      await pumpEventQueue();
      expect(downloads, 1);
      expect((s.helperState as HelperDownloading).moving, isTrue);
      expect(
        (s.helperState as HelperDownloading).bytes,
        _dropAt,
        reason: 'the ring starts here',
      );
      s.pauseDownload();
      await pumpEventQueue();
    });

    test(
      'a paused download comes back paused with its bytes and waits for Resume',
      () async {
        final s = await relaunch(KeptDownload.paused, mobile: false);
        final h = s.helperState as HelperDownloading;
        expect(h.paused, isTrue);
        expect(h.bytes, _dropAt);
        expect(downloads, 0);

        unawaited(s.resumeDownload());
        await pumpEventQueue();
        expect(downloads, 1);
        s.pauseDownload();
        await pumpEventQueue();
        expect(s.prefs.getStringList(keptDownloadKey), [
          m.id,
          KeptDownload.paused.name,
        ]);
        expect((s.helperState as HelperDownloading).bytes, _dropAt);
      },
    );

    test('a download the app closed on goes on by itself over Wi-Fi', () async {
      final s = await relaunch(KeptDownload.moving, mobile: false);
      expect(downloads, 1);
      s.pauseDownload();
      await pumpEventQueue();
    });

    test('opened with no connection, a download waits for it, not for Wi-Fi, and tries again', () async {
      offline = true;
      final s = await relaunch(KeptDownload.moving, mobile: false);
      await pumpEventQueue();
      expect(downloads, 1);
      final h = s.helperState as HelperDownloading;
      expect(
        h.waitingForNetwork,
        isTrue,
        reason: 'no failure the reader must answer',
      );
      expect(h.waitingForWifi, isFalse, reason: 'it is on Wi-Fi already');
      expect(h.bytes, _dropAt);
      expect(s.prefs.getStringList(keptDownloadKey), [
        m.id,
        KeptDownload.waitingForNetwork.name,
      ]);

      await Future<void>.delayed(_retry * 3);
      expect(downloads, 2, reason: 'tried again by itself');
      expect(s.networkRetry, _retry * 4, reason: 'each wait twice the last');

      offline = false;
      network.add(false);
      await pumpEventQueue();
      expect(downloads, 3);
      expect((s.helperState as HelperDownloading).moving, isTrue);
      s.pauseDownload();
      await pumpEventQueue();
    });

    test('a model chosen in settings mid-download leaves Pause and Cancel on the download', () async {
      final s = await relaunch(KeptDownload.paused, mobile: false);
      final other = edgeModelById('gemma-3-1b');
      await s.updateSettings(s.settings.copyWith(deviceModelId: other.id));
      unawaited(s.resumeDownload());
      await pumpEventQueue();
      expect(downloads, 1);
      expect((s.helperState as HelperDownloading).model.id, m.id);

      s.pauseDownload();
      await pumpEventQueue();
      expect(s.prefs.getStringList(keptDownloadKey), [
        m.id,
        KeptDownload.paused.name,
      ]);
      expect((s.helperState as HelperDownloading).bytes, _dropAt);

      s.cancelDownload();
      expect(
        partialDownload(models(), m.file),
        isNull,
        reason: 'no part left orphaned',
      );
    });

    test(
      'Cancel after a restart removes the part and forgets the download',
      () async {
        final s = await relaunch(KeptDownload.paused, mobile: false);
        s.cancelDownload();
        expect(s.helperState, isA<HelperNotInstalled>());
        expect(partialDownload(models(), m.file), isNull);
        expect(s.prefs.getStringList(keptDownloadKey), isNull);
      },
    );

    test('a part left by another model is removed once it is no longer the one wanted', () async {
      final other = edgeModelById('gemma-4-e4b');
      await partOf(other);
      final s = await relaunch(KeptDownload.paused, mobile: false, kept: other);
      expect(partialDownload(models(), other.file), isNull);
      expect(s.prefs.getStringList(keptDownloadKey), isNull);
      expect(s.helperState, isA<HelperNotInstalled>());
    });
  });
}
