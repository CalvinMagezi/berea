import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:berea/narration_packs.dart';
import 'package:berea/read_along.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqlite3/sqlite3.dart';

const _durationMs = 5000;
final _m4a = Uint8List.fromList([0, 0, 0, 24, ...ascii.encode('ftypM4A '), 0, 0, 0, 0]);

/// A player that records what it is asked; a load can be held to model a slow file.
class FakePlayer extends Fake implements AudioPlayer {
  final calls = <String>[];
  final _states = StreamController<PlayerState>.broadcast();
  final holds = <Completer<void>>[];
  var _playing = false;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  @override
  bool get playing => _playing;

  @override
  Duration get position => Duration.zero;

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    calls.add('load ${(audioSource as UriAudioSource).uri.pathSegments.last.split('-')[1]}');
    if (holds.isNotEmpty) await holds.removeAt(0).future;
    return const Duration(milliseconds: _durationMs);
  }

  @override
  Future<void> play() async {
    _playing = true;
    calls.add('play');
    _states.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    calls.add('pause');
    _states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async =>
      calls.add('seek ${position?.inMilliseconds}');

  @override
  Future<void> setSpeed(double speed) async => calls.add('speed $speed');

  @override
  Future<void> stop() async {
    _playing = false;
    calls.add('stop');
  }
}

/// A speech engine that records utterances and lets a test fire its callbacks.
class FakeTts extends Fake implements FlutterTts {
  final spoken = <String>[];
  final calls = <String>[];
  var languages = {'en-US'};
  List<Object?> voices = const [];
  ProgressHandler? onProgress;
  VoidCallback? onDone;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> setSharedInstance(bool sharedSession) async => 1;

  @override
  Future<dynamic> setIosAudioCategory(
    IosTextToSpeechAudioCategory category,
    List<IosTextToSpeechAudioCategoryOptions> options, [
    IosTextToSpeechAudioMode mode = IosTextToSpeechAudioMode.defaultMode,
  ]) async => 1;

  @override
  Future<dynamic> setLanguage(String language) async => languages.contains(language) ? 1 : 0;

  @override
  Future<dynamic> get getVoices async => voices;

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async => calls.add('voice ${voice['name']}');

  @override
  void setProgressHandler(ProgressHandler callback) => onProgress = callback;

  @override
  void setCompletionHandler(VoidCallback callback) => onDone = callback;

  @override
  void setPauseHandler(VoidCallback callback) {}

  @override
  void setContinueHandler(VoidCallback callback) {}

  @override
  void setErrorHandler(ErrorHandler handler) {}

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async => spoken.add(text);

  @override
  Future<dynamic> stop() async => calls.add('stop');

  @override
  Future<SpeechRateValidRange> get getSpeechRateValidRange async =>
      SpeechRateValidRange(0, 0.5, 1, TextToSpeechPlatform.ios);

  @override
  Future<dynamic> setSpeechRate(double rate) async => calls.add('rate $rate');

  /// Reports that the utterance in progress reached character [start].
  void reach(int start) => onProgress!(spoken.last, start, start + 1, '');
}

/// A John pack whose chapters each have verse 1 (three words) and verse 3 (two words).
String writePack(Directory dir) {
  final path = '${dir.path}/pack.sqlite';
  final db = sqlite3.open(path)
    ..execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)')
    ..execute(
      'CREATE TABLE chapters(chapter INTEGER PRIMARY KEY, duration_ms INTEGER NOT NULL, '
      'audio BLOB NOT NULL, timings TEXT NOT NULL)',
    );
  for (final e in {'format': '1', 'pack': 'souer-43', 'book': '43', 'narrator': 'souer'}.entries) {
    db.execute('INSERT INTO meta VALUES (?, ?)', [e.key, e.value]);
  }
  for (final c in [1, 2]) {
    final words = [
      [1, 0, 100, 200],
      [1, 1, 200, 300],
      [1, 2, 300, 400],
      [3, 0, 1000, 1100],
      [3, 1, 1100, 1200],
    ];
    final timings = jsonEncode({'book': 43, 'chapter': c, 'words': words});
    db.execute('INSERT INTO chapters VALUES (?, ?, ?, ?)', [c, _durationMs, _m4a, timings]);
  }
  db.dispose();
  return path;
}

/// Waits until the player has been given a source; extraction runs on another isolate.
Future<void> loaded(FakePlayer player) async {
  while (player.calls.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final john = bookById(43);
const verses = [
  Verse(Book(43, 'John', 'Jhn', []), 1, 1, 'In the beginning'),
  Verse(Book(43, 'John', 'Jhn', []), 1, 2, ''),
  Verse(Book(43, 'John', 'Jhn', []), 1, 3, 'And God'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late NarrationShelf shelf;
  late FakePlayer player;
  late FakeTts tts;
  late ReadAlong r;

  setUp(() async {
    // Apple's path by default; the Android cases say so.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    dir = Directory.systemTemp.createTempSync('berea_read_along_state');
    shelf = NarrationShelf(Directory('${dir.path}/narration'), () {}, chapterCount: (_) => 2);
    await shelf.installFromFile(writePack(dir));
    player = FakePlayer();
    tts = FakeTts();
    r = ReadAlong(shelf, newPlayer: () => player, newTts: () => tts, prepareAudio: () async {});
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await r.stop();
    dir.deleteSync(recursive: true);
  });

  Future<void> narrate(int chapter) =>
      r.start(book: john, chapter: chapter, voice: ReadAlongVoice.narration, verses: verses);

  Future<void> speakAloud() =>
      r.start(book: john, chapter: 1, voice: ReadAlongVoice.device, verses: verses);

  group('narration', () {
    test('plays the chapter, keeps the speed and stops cleanly', () async {
      await r.setSpeed(1.5);
      await narrate(1);
      await pumpEventQueue();
      expect(player.calls, ['load 1', 'speed 1.5', 'play']);
      expect(r.state.value?.status, ReadAlongStatus.playing);
      expect(r.timings?.wordsPerVerse, {1: 3, 3: 2});
      expect(r.offsetMs, 0);
      await r.stop();
      expect(player.calls.last, 'stop');
      expect(r.state.value, isNull);
      expect(r.timings, isNull);
    });

    test('a stop during a slow load leaves the player silent', () async {
      final hold = Completer<void>();
      player.holds.add(hold);
      final started = narrate(1);
      await loaded(player);
      await r.stop();
      hold.complete();
      await started;
      expect(player.calls, ['load 1', 'stop']);
      expect(r.state.value, isNull);
    });

    test('a newer start wins and the older load does not stop it', () async {
      final hold = Completer<void>();
      player.holds.add(hold);
      final first = narrate(1);
      await loaded(player);
      await narrate(2);
      hold.complete();
      await first;
      expect(player.calls, ['load 1', 'load 2', 'speed 1.0', 'play']);
      expect(r.state.value?.chapter, 2);
      expect(r.state.value?.status, ReadAlongStatus.playing);
    });

    test('next and previous move between timed verses', () async {
      await narrate(1);
      await r.nextVerse();
      expect(player.calls.last, 'seek 100', reason: 'from no position, the first verse');
      r.position.value = (verse: 1, word: 2);
      await r.nextVerse();
      expect(player.calls.last, 'seek 1000', reason: 'verse 2 has no words');
      r.position.value = (verse: 3, word: 0);
      await r.previousVerse();
      expect(player.calls.last, 'seek 100');
    });
  });

  group('device voice', () {
    test('reads verse by verse, skipping empty verses, and marks each word', () async {
      await speakAloud();
      expect(tts.spoken, ['In the beginning']);
      expect(r.position.value, (verse: 1, word: 0));
      tts.reach('In the '.length);
      expect(r.position.value, (verse: 1, word: 2));
      tts.onDone!();
      await pumpEventQueue();
      expect(tts.spoken.last, 'And God', reason: 'verse 2 is empty');
      expect(r.position.value, (verse: 3, word: 0));
    });

    test('pause, a seek to a word and play resume from that word', () async {
      await speakAloud();
      await r.togglePlay();
      expect(r.state.value?.status, ReadAlongStatus.paused);
      await r.seek(1, 1);
      expect(tts.spoken, hasLength(1), reason: 'a paused voice stays quiet');
      await r.togglePlay();
      expect(tts.spoken.last, 'the beginning');
      tts.reach('the '.length);
      expect(r.position.value, (verse: 1, word: 2), reason: 'offsets count from the word');
    });

    test('an empty verse steps to its neighbours', () async {
      await speakAloud();
      await r.togglePlay();
      await r.seek(2);
      await r.nextVerse();
      expect(r.position.value?.verse, 3);
      await r.seek(2);
      await r.previousVerse();
      expect(r.position.value?.verse, 1);
    });

    test('Android uses only an installed offline voice, preferring one on the device', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tts.voices = [
        {'name': 'net', 'locale': 'en-US', 'network_required': '1', 'features': 'networkTts'},
        {'name': 'pending', 'locale': 'en-US', 'network_required': '0', 'features': 'notInstalled'},
        {'name': 'plain', 'locale': 'en-US', 'network_required': '0', 'features': ''},
        {'name': 'local', 'locale': 'en-GB', 'network_required': '0', 'features': 'embeddedTts'},
        {'name': 'french', 'locale': 'fr-FR', 'network_required': '0', 'features': 'embeddedTts'},
      ];
      await speakAloud();
      expect(tts.calls, contains('voice local'));
      expect(r.state.value?.status, ReadAlongStatus.playing);
    });

    test('no offline English voice is a clear failure, on Android and Apple', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tts.voices = [
        {'name': 'net', 'locale': 'en-US', 'network_required': '1', 'features': 'networkTts'},
      ];
      await speakAloud();
      expect(r.state.value?.status, ReadAlongStatus.failed);
      expect(r.state.value?.error, contains('No offline English voice'));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tts.languages = {};
      await speakAloud();
      expect(r.state.value?.error, contains('No English voice'));
      expect(tts.spoken, isEmpty);
    });
  });

  test('failures read as sentences', () {
    expect(describeReadAlongFailure(PlayerException(1, 'boom', null)), isNot(contains('boom')));
    expect(describeReadAlongFailure(const FormatException('Bad pack.')), 'Bad pack.');
    expect(describeReadAlongFailure(StateError('x')), isNot(contains('StateError')));
  });
}
