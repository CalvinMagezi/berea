import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'narration_packs.dart';
import 'pinned_download.dart';

part 'read_along_voices.dart';

/// Only Android, iOS and macOS have both a player and a speech engine here (see TECHDEBT.md).
final readAlongSupported = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Playback speeds offered in the player.
const readAlongSpeeds = [0.75, 1.0, 1.25, 1.5, 2.0];

/// How often the highlight checks the player's position; words last about 250 ms.
const readAlongTick = Duration(milliseconds: 30);

/// One AAC frame at 24 kHz: a player honouring the MP4 edit list reports the duration this close.
const aacFrameMs = 1024 * 1000 ~/ 24000;

/// Sets up the spoken-word audio session and lock-screen controls; must precede any AudioPlayer.
Future<void> initReadAlongAudio() async {
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.magezi.berea.narration',
      androidNotificationChannelName: 'Narration',
      androidNotificationOngoing: true,
    );
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  } on Object catch (e) {
    debugPrint('Background audio is unavailable: $e');
  }
}

/// The timing offset for a player: the priming only if its duration shows the priming untrimmed.
int primingOffsetMs({
  required Duration? reported,
  required int durationMs,
  required int primingMs,
}) {
  if (reported == null) return 0;
  return reported.inMilliseconds - durationMs > aacFrameMs ? primingMs : 0;
}

/// A playback failure as a sentence for the bar, never a raw exception.
String describeReadAlongFailure(Object e) => switch (e) {
  PlayerInterruptedException() => 'Playback was interrupted. Tap Play to try again.',
  PlayerException() => 'This device could not play the narration.',
  MissingPluginException() => 'Reading aloud is not available on this device.',
  PlatformException() => 'The device could not read this aloud.',
  _ => describeFailure(e),
};

enum ReadAlongVoice { narration, device }

enum ReadAlongStatus { loading, playing, paused, failed }

/// What the player bar shows.
@immutable
class ReadAlongState {
  final int book;
  final int chapter;
  final ReadAlongVoice voice;

  /// The translation shown when reading began; the device voice reads that text.
  final String translation;
  final ReadAlongStatus status;
  final double speed;
  final String? error;
  const ReadAlongState({
    required this.book,
    required this.chapter,
    required this.voice,
    required this.status,
    this.translation = defaultTranslation,
    this.speed = 1.0,
    this.error,
  });

  ReadAlongState copyWith({ReadAlongStatus? status, double? speed, String? error}) =>
      ReadAlongState(
        book: book,
        chapter: chapter,
        voice: voice,
        translation: translation,
        status: status ?? this.status,
        speed: speed ?? this.speed,
        error: error,
      );
}

/// The verse being read and, when the voice says, the word within it (as [wordRanges] counts).
typedef ReadAlongPosition = ({int verse, int? word});

/// Plays a chapter with the current word marked and the reader following along.
class ReadAlong {
  final NarrationShelf shelf;
  final AudioPlayer Function() _newPlayer;
  final FlutterTts Function() _newTts;
  final Future<void> Function() _prepareAudio;

  /// The engines are made on first use, after [prepareAudio]; tests pass fakes.
  ReadAlong(
    this.shelf, {
    AudioPlayer Function()? newPlayer,
    FlutterTts Function()? newTts,
    Future<void> Function()? prepareAudio,
  }) : _newPlayer = newPlayer ?? AudioPlayer.new,
       _newTts = newTts ?? FlutterTts.new,
       _prepareAudio = prepareAudio ?? initReadAlongAudio;

  /// Null while nothing is loaded.
  final state = ValueNotifier<ReadAlongState?>(null);

  /// Changes with every word, so it is kept apart from [state] and from the app's listeners.
  final position = ValueNotifier<ReadAlongPosition?>(null);

  /// Timed words of the narrated chapter; null for the device voice.
  ChapterTimings? timings;

  var _speed = 1.0;
  Future<void>? _audioReady;
  AudioPlayer? _player;
  FlutterTts? _tts;
  _Voice? _voice;

  /// Bumped by every start and stop, so a load that was superseded touches nothing shared.
  var _generation = 0;

  /// The generation that last gave the player a source.
  int? _playerOwner;

  /// The book whose download this read-along started, so Stop can cancel it.
  int? _downloading;

  @visibleForTesting
  AudioPlayer? get debugPlayer => _player;
  @visibleForTesting
  FlutterTts? get debugTts => _tts;

  /// Milliseconds added to every timing for this player; see [primingOffsetMs].
  int get offsetMs => switch (_voice) {
    _Narration(:final offsetMs) => offsetMs,
    _ => 0,
  };

  bool isOn(int book, int chapter) {
    final s = state.value;
    return s != null && s.book == book && s.chapter == chapter;
  }

  /// Whether the voice's word numbers fit [text]; narration counts the BSB's words only.
  bool wordsFit(int verse, String text, String translation) {
    final t = timings;
    if (t == null) return true;
    if (translation != defaultTranslation) return false;
    return t.wordsPerVerse[verse] == wordRanges(text).length;
  }

  /// The word to mark in [verse], or null to mark only the verse.
  int? wordToShow(int verse, String text, String translation) {
    final at = position.value;
    if (at == null || at.verse != verse) return null;
    return wordsFit(verse, text, translation) ? at.word : null;
  }

  /// Starts [voice] on [book] [chapter], downloading the narration first if needed.
  Future<void> start({
    required Book book,
    required int chapter,
    required ReadAlongVoice voice,
    required List<Verse> verses,
    String translation = defaultTranslation,
  }) async {
    final previous = _reset();
    final generation = _generation;
    state.value = ReadAlongState(
      book: book.id,
      chapter: chapter,
      voice: voice,
      translation: translation,
      status: ReadAlongStatus.loading,
      speed: _speed,
    );
    try {
      await previous?.stop();
      final v = voice == ReadAlongVoice.narration
          ? await _loadNarration(book, chapter, generation)
          : await _loadDeviceVoice(verses, generation);
      if (v == null || generation != _generation) return await v?.release();
      _use(v);
      await v.setSpeed(_speed);
      if (generation != _generation) return;
      await v.play();
    } on Object catch (e) {
      if (generation == _generation) _fail(e);
    }
  }

  void _use(_Voice v) {
    _voice = v;
    if (v is _Narration) {
      timings = v.timings;
      shelf.prunePlayed(keep: v.file);
    }
    v.attach();
  }

  void _fail(Object e) {
    debugPrint('Read along failed: $e');
    state.value = state.value?.copyWith(
      status: ReadAlongStatus.failed,
      error: describeReadAlongFailure(e),
    );
  }

  Future<AudioPlayer> _ensurePlayer() async {
    await (_audioReady ??= _prepareAudio());
    return _player ??= _newPlayer();
  }

  /// Null when a newer start or a stop came first.
  Future<_Narration?> _loadNarration(Book book, int chapter, int generation) async {
    if (!shelf.isInstalled(book.id)) {
      if (!shelf.isDownloading(book.id)) _downloading = book.id;
      await shelf.download(book.id);
    }
    if (generation != _generation) return null;
    _downloading = null;
    final track = await shelf.track(book.id, chapter);
    final player = await _ensurePlayer();
    if (generation != _generation) return null;
    _playerOwner = generation;
    final reported = await player.setAudioSource(
      AudioSource.file(
        track.file.path,
        // No artUri: audio_service would fetch it over the network.
        tag: MediaItem(
          id: '$narrationNarrator-${book.id}-$chapter',
          title: '${book.name} $chapter',
          artist: narrationCredit,
          album: 'Berean Standard Bible',
        ),
      ),
    );
    if (generation != _generation) {
      // Stopped while loading, and no newer start has the player: leave it silent.
      if (_playerOwner == generation) await player.stop();
      return null;
    }
    final offset = primingOffsetMs(
      reported: reported,
      durationMs: track.durationMs,
      primingMs: track.primingMs,
    );
    debugPrint('Narration ${book.name} $chapter: ${reported?.inMilliseconds} ms, offset $offset');
    return _Narration(this, player, track.timings, offset, track.file);
  }

  Future<_Voice?> _loadDeviceVoice(List<Verse> verses, int generation) async {
    final tts = _tts ??= _newTts();
    await _DeviceVoice.prepare(tts);
    if (generation != _generation) return null;
    return _DeviceVoice(this, tts, verses);
  }

  void _moved(ReadAlongPosition? at) {
    if (at != position.value) position.value = at;
  }

  void _status(ReadAlongStatus status) {
    final s = state.value;
    if (s != null && s.status != status) state.value = s.copyWith(status: status);
  }

  Future<void> togglePlay() async {
    final v = _voice;
    if (v == null) return;
    if (state.value?.status == ReadAlongStatus.playing) {
      await v.pause();
    } else {
      await v.play();
    }
  }

  /// Moves to [verse], at [word] when given.
  Future<void> seek(int verse, [int word = 0]) async => _voice?.seek(verse, word);

  /// The next verse with words, skipping empty ones.
  Future<void> nextVerse() async {
    final at = position.value?.verse;
    final next = _verseNumbers().where((v) => at == null || v > at).firstOrNull;
    if (next != null) await seek(next);
  }

  /// The previous verse with words, or the first verse.
  Future<void> previousVerse() async {
    final at = position.value?.verse;
    final verses = _verseNumbers();
    if (verses.isEmpty) return;
    final previous = at == null ? null : verses.where((v) => v < at).lastOrNull;
    await seek(previous ?? verses.first);
  }

  List<int> _verseNumbers() => switch (_voice) {
    _DeviceVoice(:final verses) => [
      for (final v in verses)
        if (wordRanges(v.text).isNotEmpty) v.verse,
    ],
    _ => timings?.wordsPerVerse.keys.toList() ?? const [],
  };

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    state.value = state.value?.copyWith(speed: speed);
    await _voice?.setSpeed(speed);
  }

  /// Stops and clears the player, and cancels a download this read-along started.
  Future<void> stop() async {
    final book = _downloading;
    if (book != null) shelf.cancelDownload(book);
    await _reset()?.stop();
  }

  /// Clears everything before any await, so a racing start or stop sees it at once.
  _Voice? _reset() {
    _generation++;
    _downloading = null;
    final v = _voice;
    _voice = null;
    state.value = null;
    position.value = null;
    timings = null;
    return v;
  }
}
