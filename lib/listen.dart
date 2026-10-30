import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'reminder_platform.dart';

/// Raised when the beat plan or instructions change, so deep dives made before are made again.
const listenScriptVersion = 1;

/// How often a deep dive checks whether the helper is free, when nothing tells it.
const listenModelPoll = Duration(milliseconds: 250);

const listenNeedsVoice = 'Download the voice first.';
const listenNeedsHelper =
    'A deep dive is written by the helper, which is not set up. Set it up in Study, then try again.';
const listenNothing =
    'Nothing to listen to yet. Add a Bible passage to this notebook, or keep a note or a study page '
    'on a passage in it.';
const listenFailed =
    'The deep dive could not be made. Try again, and it continues where it stopped.';
const deepDiveReadyTitle = 'Your deep dive is ready';
const voiceNeedsWifi =
    'The voice downloads over Wi-Fi only. Connect to Wi-Fi, or turn off Wi-Fi only in Settings.';
const voiceDownloadFailed = 'The voice did not download. Check the connection and try again.';
const voiceDamaged = 'The voice arrived damaged and was removed. Try again.';
const listenSettingsChanged =
    'The helper changed while the deep dive was written. Make it again to write it for the new one.';

/// A beat that came back empty is written once more before it is kept as it is.
const listenBeatTries = 2;

const _fnvOffset = 0x811c9dc5;
const _fnvPrime = 0x01000193;
const _mask32 = 0xffffffff;

/// A stable 32-bit hash of [s]: String.hashCode may differ between runs, and a key must not.
int fnv1a(String s) {
  var h = _fnvOffset;
  for (final u in s.codeUnits) {
    h = ((h ^ u) * _fnvPrime) & _mask32;
  }
  return h;
}

const _scriptFile = 'script.json';
const _doneFile = 'done.json';
const _audioFile = 'deep-dive.wav';

/// A notebook's deep dive on disk: the script beat by beat as it is written, each beat's audio
/// as it is spoken, and the joined recording. All of it is made from the notebook again, so none
/// of it goes into a backup, and a packet that changed makes it stale.
class ListenStore {
  final Directory dir;
  ListenStore(this.dir);

  File get _script => File('${dir.path}/$_scriptFile');
  File get _done => File('${dir.path}/$_doneFile');
  File get audio => File('${dir.path}/$_audioFile');

  /// A damaged or foreign file reads as none, so the screen offers to make the deep dive again.
  Map<String, Object?>? _read(File f) {
    try {
      return f.existsSync() ? jsonDecode(f.readAsStringSync()) as Map<String, Object?> : null;
    } catch (_) {
      return null;
    }
  }

  List<ScriptBeat>? _beatsOf(Map<String, Object?>? json, String? fingerprint) {
    if (json == null || (fingerprint != null && json['fingerprint'] != fingerprint)) return null;
    try {
      return [
        for (final b in json['beats']! as List) ScriptBeat.fromJson(b as Map<String, Object?>),
      ];
    } catch (_) {
      return null;
    }
  }

  void _write(File f, Map<String, Object?> json) {
    dir.createSync(recursive: true);
    File('${f.path}.part')
      ..writeAsStringSync(jsonEncode(json))
      ..renameSync(f.path);
  }

  /// The beats written for [fingerprint] so far; none when they were written for another packet.
  List<ScriptBeat> beats(String fingerprint) => _beatsOf(_read(_script), fingerprint) ?? [];

  void saveBeats(String fingerprint, List<ScriptBeat> beats) => _write(_script, {
    'fingerprint': fingerprint,
    'beats': [for (final b in beats) b.toJson()],
  });

  /// The finished recording, with [current] false when it was made before the notebook changed:
  /// it still plays until a new one replaces it.
  ({File audio, Duration length, List<ScriptBeat> script, bool current})? finished(
    String fingerprint,
  ) {
    final done = _read(_done);
    final script = _beatsOf(done, null);
    final millis = done?['millis'];
    if (done == null || script == null || millis is! int || !audio.existsSync()) return null;
    return (
      audio: audio,
      length: Duration(milliseconds: millis),
      script: script,
      current: done['fingerprint'] == fingerprint,
    );
  }

  /// Whether a deep dive for [fingerprint] was started and not finished.
  bool unfinished(String fingerprint) => beats(fingerprint).isNotEmpty;

  /// Gets ready to make the deep dive for [fingerprint], from the start when [again]. Parts made
  /// for another packet go; a finished recording stays until [finish] replaces it.
  void startFor(String fingerprint, {bool again = false}) {
    final script = _read(_script);
    if (again || (script != null && script['fingerprint'] != fingerprint)) _dropWork();
  }

  /// Keeps [beats] as the script of the recording just joined, and drops the parts it was made of.
  void finish(String fingerprint, Duration length, List<ScriptBeat> beats) {
    _write(_done, {
      'fingerprint': fingerprint,
      'millis': length.inMilliseconds,
      'beats': [for (final b in beats) b.toJson()],
    });
    _dropWork();
  }

  void _dropWork() {
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.startsWith('beat-') || name.startsWith(_scriptFile)) f.deleteSync();
    }
  }

  void clear() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

enum ListenStage { writing, speaking, ready, stopped, failed }

/// One deep dive being made, for the screens to follow. Only one runs at a time: it holds the
/// helper while it writes and the device's memory while it speaks.
class ListenJob extends ChangeNotifier {
  final int notebookId;
  final String notebookTitle;
  ListenStage stage = ListenStage.writing;

  /// Beats written, or paragraphs spoken, of [total].
  int done = 0;
  int total = 1;
  String? error;
  final _stop = Completer<void>();

  ListenJob(this.notebookId, this.notebookTitle);

  bool get running => stage == ListenStage.writing || stage == ListenStage.speaking;
  Future<void> get stopRequested => _stop.future;
  bool get stopping => _stop.isCompleted && running;

  /// Writing takes about half the time and speaking the other half on the A32, so each fills
  /// half of the bar.
  double get fraction {
    final part = total == 0 ? 0.0 : done / total;
    return switch (stage) {
      ListenStage.writing => part / 2,
      ListenStage.speaking => 0.5 + part / 2,
      ListenStage.ready => 1,
      ListenStage.stopped || ListenStage.failed => 0,
    };
  }

  String get status => switch (stage) {
    ListenStage.writing when stopping => 'Stopping after this part',
    ListenStage.speaking when stopping => 'Stopping',
    ListenStage.writing => 'Writing part ${done + 1} of $total',
    ListenStage.speaking => 'Recording, ${(done * 100 / total).floor()} percent',
    ListenStage.ready => 'Ready to listen',
    ListenStage.stopped => 'Stopped',
    ListenStage.failed => error ?? 'The deep dive could not be made',
  };

  void writing(int beat, int beats) => _set(ListenStage.writing, beat, beats);
  void speaking(int paragraph, int paragraphs) => _set(ListenStage.speaking, paragraph, paragraphs);
  void ready() => _set(ListenStage.ready, total, total);
  void stopped() => _set(ListenStage.stopped, done, total);

  void failed(String why) {
    error = why;
    _set(ListenStage.failed, done, total);
  }

  void _set(ListenStage s, int d, int t) {
    stage = s;
    done = d;
    total = t;
    notifyListeners();
  }

  /// Stops at the next part or paragraph; what was made so far is kept for Continue.
  void stop() {
    if (!_stop.isCompleted && running) _stop.complete();
    notifyListeners();
  }
}

/// Keeps a deep dive going while Berea is in the background, and says when it is ready.
abstract class ListenNotice {
  Future<void> working(String title, String body);
  Future<void> idle();
  Future<void> ready(String title, String body);
}

/// For tests and platforms without notifications.
class QuietListenNotice implements ListenNotice {
  const QuietListenNotice();
  @override
  Future<void> working(String title, String body) async {}
  @override
  Future<void> idle() async {}
  @override
  Future<void> ready(String title, String body) async {}
}

const _channelId = 'listen';
const _channelName = 'Deep dive progress';
const _channelDescription = 'Shows how far along a deep dive is while it is made.';

/// Its own channel: Android keeps a channel's first importance, and progress is quiet.
const _readyChannelId = 'listen_ready';
const _readyChannelName = 'Deep dive ready';
const _readyChannelDescription = 'Says when a deep dive is ready to listen to.';

/// Ids clear of the reminders, which are dates such as 20261030.
const _workingId = 9001;
const _readyId = 9002;

/// An Android foreground service with a progress notification while a deep dive is made, so the
/// system keeps Berea's process while the reader uses other apps; everywhere, the ready notice.
class LocalListenNotice implements ListenNotice {
  final _plugin = FlutterLocalNotificationsPlugin();
  var _asked = false;

  /// Calls run in order, so a stop never overtakes the start it follows.
  Future<void> _queue = Future.value();

  Future<void> _run(Future<void> Function() call) {
    final next = _queue.then((_) => call());
    _queue = next.catchError((Object e) => debugPrint('The deep dive notice failed: $e'));
    return next;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android => Platform.isAndroid
      ? FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      : null;

  Future<void> _init() async {
    await initLocalNotifications(_plugin);
    // The reader started this, so this is the moment to ask; a refusal still makes the dive.
    if (_asked) return;
    _asked = true;
    try {
      await LocalNotificationsPlatform().requestPermission();
    } catch (e) {
      debugPrint('Notification permission was not asked: ${e.runtimeType}');
    }
  }

  static const _details = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDescription,
    importance: Importance.low,
    onlyAlertOnce: true,
    ongoing: true,
  );

  /// Whether the service runs. Android refuses to start one while the app is in the background,
  /// so later progress posts to the service's notification instead.
  var _serving = false;

  @override
  Future<void> working(String title, String body) => _run(() async {
    if (!LocalNotificationsPlatform.supported) return;
    await _init();
    final android = _android;
    if (android == null) return;
    if (_serving) {
      return _plugin.show(
        id: _workingId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _details),
      );
    }
    _serving = true;
    await android.startForegroundService(
      id: _workingId,
      title: title,
      body: body,
      notificationDetails: _details,
      startType: AndroidServiceStartType.startNotSticky,
      foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
    );
  });

  @override
  Future<void> idle() => _run(() async {
    if (!_serving) return;
    _serving = false;
    await _android?.stopForegroundService();
  });

  @override
  Future<void> ready(String title, String body) => _run(() async {
    if (!LocalNotificationsPlatform.supported) return;
    await _init();
    await _plugin.show(
      id: _readyId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _readyChannelId,
          _readyChannelName,
          channelDescription: _readyChannelDescription,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
    );
  });
}
