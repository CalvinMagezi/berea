import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'narration_packs.dart';

/// just_audio and flutter_tts have no Linux implementation, and this feature is only checked on
/// these three; Windows waits until it is (see TECHDEBT.md).
final readAlongSupported = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Playback speeds offered in the player.
const readAlongSpeeds = [0.75, 1.0, 1.25, 1.5, 2.0];

/// How often the highlight checks the player's position. Words last about 250 ms.
const readAlongTick = Duration(milliseconds: 30);

/// One AAC frame at the packs' 24 kHz. A player that honours the MP4 edit list reports the
/// pack's duration to within a frame; one that ignores it reports the priming on top.
const aacFrameMs = 1024 * 1000 ~/ 24000;

/// Sets up the audio session for spoken word and the lock-screen controls, before the app runs.
/// A platform without them still starts; read-along is hidden there.
Future<void> initReadAlongAudio() async {
  if (!readAlongSupported) return;
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

/// Milliseconds to add to every timing for this player: 0 when it honours the edit list, the
/// pack's priming when the duration it reports shows the priming was not trimmed.
int primingOffsetMs({
  required Duration? reported,
  required int durationMs,
  required int primingMs,
}) {
  if (reported == null) return 0;
  return reported.inMilliseconds - durationMs > aacFrameMs ? primingMs : 0;
}

enum ReadAlongVoice { narration, device }

enum ReadAlongStatus { loading, playing, paused, failed }

/// What the player bar shows.
@immutable
class ReadAlongState {
  final int book;
  final int chapter;
  final ReadAlongVoice voice;
  final ReadAlongStatus status;
  final double speed;
  final String? error;
  const ReadAlongState({
    required this.book,
    required this.chapter,
    required this.voice,
    required this.status,
    this.speed = 1.0,
    this.error,
  });

  ReadAlongState copyWith({ReadAlongStatus? status, double? speed, String? error}) =>
      ReadAlongState(
        book: book,
        chapter: chapter,
        voice: voice,
        status: status ?? this.status,
        speed: speed ?? this.speed,
        error: error,
      );
}

/// The verse being read and, when the voice says, the word within it (as [wordRanges] counts).
typedef ReadAlongPosition = ({int verse, int? word});

/// A voice the read-along drives: the downloaded narration or the device's own speech.
abstract class _Voice {
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int verse, int word);
  Future<void> setSpeed(double speed);

  /// Stops listening to the engine without touching playback, for a load that was superseded.
  Future<void> release();
  Future<void> stop();
}

/// Plays a chapter with the current word highlighted and the reader following along. The
/// player and the speech engine are created only when first used, never at startup.
class ReadAlong {
  final NarrationShelf shelf;
  ReadAlong(this.shelf);

  /// Null while nothing is loaded.
  final state = ValueNotifier<ReadAlongState?>(null);

  /// Changes with every word, so it is kept apart from [state] and from the app's listeners.
  final position = ValueNotifier<ReadAlongPosition?>(null);

  /// Timed words of the narrated chapter; null for the device voice.
  ChapterTimings? timings;

  /// Milliseconds added to every timing for this player; see [primingOffsetMs].
  int offsetMs = 0;

  AudioPlayer? _player;
  FlutterTts? _tts;
  _Voice? _voice;

  /// Bumped by every start and stop, so a slow load that was superseded does not play.
  var _generation = 0;

  bool isOn(int book, int chapter) {
    final s = state.value;
    return s != null && s.book == book && s.chapter == chapter;
  }

  /// The word to highlight in [verse], or null to mark only the verse: narration timings match
  /// the Berean Standard Bible's words, so another translation follows verse by verse.
  int? wordToShow(int verse, String text, String translation) {
    final at = position.value;
    if (at == null || at.verse != verse) return null;
    final t = timings;
    if (t == null) return at.word;
    if (translation != defaultTranslation) return null;
    return t.wordsPerVerse[verse] == wordRanges(text).length ? at.word : null;
  }

  /// Starts [voice] on [book] [chapter]. Narration downloads its pack first if it must.
  /// [verses] is the chapter as shown, which the device voice reads.
  Future<void> start({
    required Book book,
    required int chapter,
    required ReadAlongVoice voice,
    required List<Verse> verses,
  }) async {
    await stop();
    final generation = _generation;
    final speed = state.value?.speed ?? 1.0;
    state.value = ReadAlongState(
      book: book.id,
      chapter: chapter,
      voice: voice,
      status: ReadAlongStatus.loading,
      speed: speed,
    );
    try {
      final v = voice == ReadAlongVoice.narration
          ? await _loadNarration(book, chapter)
          : await _loadDeviceVoice(verses);
      if (generation != _generation) return await v.release();
      _voice = v;
      await v.setSpeed(speed);
      await v.play();
    } on Object catch (e) {
      if (generation != _generation) return;
      state.value = state.value?.copyWith(status: ReadAlongStatus.failed, error: _describe(e));
    }
  }

  String _describe(Object e) => switch (e) {
    FormatException(:final message) => message,
    HttpException(:final message) => message,
    _ => '$e',
  };

  Future<_Voice> _loadNarration(Book book, int chapter) async {
    if (!shelf.isInstalled(book.id)) await shelf.download(book.id);
    final track = await shelf.track(book.id, chapter);
    final player = _player ??= AudioPlayer();
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
    timings = track.timings;
    offsetMs = primingOffsetMs(
      reported: reported,
      durationMs: track.durationMs,
      primingMs: track.primingMs,
    );
    debugPrint(
      'Narration ${book.name} $chapter: player reports ${reported?.inMilliseconds} ms, '
      'pack ${track.durationMs} ms, timing offset $offsetMs ms',
    );
    return _Narration(this, player, track.timings);
  }

  Future<_Voice> _loadDeviceVoice(List<Verse> verses) async {
    final tts = _tts ??= FlutterTts();
    await _DeviceVoice.prepare(tts);
    timings = null;
    offsetMs = 0;
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

  Future<void> nextVerse() => _stepVerse(1);

  Future<void> previousVerse() => _stepVerse(-1);

  Future<void> _stepVerse(int step) async {
    final at = position.value;
    final verses = _verseNumbers();
    if (verses.isEmpty) return;
    final i = at == null ? -1 : verses.indexOf(at.verse);
    final next = (i + step).clamp(0, verses.length - 1);
    await seek(verses[next]);
  }

  /// Verses the voice can move to, in order: for narration, those with timed words.
  List<int> _verseNumbers() => switch (_voice) {
    _DeviceVoice(:final verses) => [
      for (final v in verses)
        if (wordRanges(v.text).isNotEmpty) v.verse,
    ],
    _ => timings?.wordsPerVerse.keys.toList() ?? const [],
  };

  Future<void> setSpeed(double speed) async {
    state.value = state.value?.copyWith(speed: speed);
    await _voice?.setSpeed(speed);
  }

  /// Stops and clears the player; the bar goes away.
  Future<void> stop() async {
    _generation++;
    final v = _voice;
    _voice = null;
    state.value = null;
    position.value = null;
    timings = null;
    await v?.stop();
  }
}

/// The downloaded narration through just_audio, with the lock-screen controls.
class _Narration implements _Voice {
  final ReadAlong owner;
  final AudioPlayer player;
  final ChapterTimings timings;
  Timer? _tick;
  late final StreamSubscription<PlayerState> _states;

  _Narration(this.owner, this.player, this.timings) {
    _states = player.playerStateStream.listen(_onState);
  }

  void _onState(PlayerState s) {
    if (s.processingState == ProcessingState.completed) {
      unawaited(_rewind());
      return;
    }
    if (s.playing) {
      _tick ??= Timer.periodic(readAlongTick, (_) => _follow());
    } else {
      _tick?.cancel();
      _tick = null;
    }
    final loading =
        s.processingState == ProcessingState.loading ||
        s.processingState == ProcessingState.buffering;
    owner._status(
      loading
          ? ReadAlongStatus.loading
          : (s.playing ? ReadAlongStatus.playing : ReadAlongStatus.paused),
    );
  }

  /// At the end of the chapter, wait at its start.
  Future<void> _rewind() async {
    await player.pause();
    await player.seek(Duration.zero);
    owner._moved(null);
  }

  void _follow() {
    final i = timings.indexAt(player.position.inMilliseconds - owner.offsetMs);
    owner._moved(i == null ? null : (verse: timings.words[i].verse, word: timings.words[i].word));
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(int verse, int word) async {
    final i = timings.indexOf(verse, word);
    if (i == null) return;
    await player.seek(Duration(milliseconds: timings.words[i].startMs + owner.offsetMs));
    _follow();
  }

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);

  @override
  Future<void> release() async {
    _tick?.cancel();
    await _states.cancel();
  }

  @override
  Future<void> stop() async {
    await release();
    await player.stop();
  }
}

/// The device's own offline voice through flutter_tts, one verse per utterance, so the word
/// offsets it reports index into that verse.
class _DeviceVoice implements _Voice {
  final ReadAlong owner;
  final FlutterTts tts;
  final List<Verse> verses;
  var _index = 0;
  var _word = 0;
  var _speaking = false;

  /// Text of the utterance in progress, to ignore callbacks from one that was replaced.
  String? _utterance;
  int _base = 0;

  _DeviceVoice(this.owner, this.tts, this.verses) {
    tts.setProgressHandler(_onProgress);
    tts.setCompletionHandler(_onDone);
    tts.setErrorHandler((message) {
      _speaking = false;
      owner.state.value = owner.state.value?.copyWith(
        status: ReadAlongStatus.failed,
        error: 'The device voice stopped: $message',
      );
    });
  }

  /// Chooses an English voice that runs offline. Android lists whether each voice needs the
  /// network; Apple's voices are all on the device.
  static Future<void> prepare(FlutterTts tts) async {
    await tts.awaitSpeakCompletion(false);
    if (Platform.isIOS) {
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        const [],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    }
    if (!Platform.isAndroid) {
      await tts.setLanguage('en-US');
      return;
    }
    final voices = [
      for (final v in (await tts.getVoices as List? ?? const []))
        if (v is Map &&
            v['network_required'] == '0' &&
            '${v['locale']}'.toLowerCase().startsWith('en'))
          {'name': '${v['name']}', 'locale': '${v['locale']}'},
    ];
    if (voices.isEmpty) {
      throw const FormatException(
        'No offline English voice is installed. Add one in the system text-to-speech settings.',
      );
    }
    final us = voices.where((v) => v['locale']!.toLowerCase() == 'en-us').firstOrNull;
    await tts.setVoice(us ?? voices.first);
  }

  void _onProgress(String text, int start, int end, String word) {
    if (!_speaking || text != _utterance) return;
    final v = verses[_index];
    _word = wordAtOffset(wordRanges(v.text), _base + start) ?? 0;
    owner._moved((verse: v.verse, word: _word));
  }

  void _onDone() {
    if (!_speaking) return;
    _word = 0;
    if (_index + 1 >= verses.length) {
      _speaking = false;
      _index = 0;
      owner._moved(null);
      owner._status(ReadAlongStatus.paused);
      return;
    }
    _index++;
    unawaited(_speak());
  }

  /// Speaks the current verse from the current word, skipping verses with no words.
  Future<void> _speak() async {
    while (_index < verses.length && wordRanges(verses[_index].text).isEmpty) {
      _index++;
    }
    if (_index >= verses.length) return _onDone();
    final v = verses[_index];
    final ranges = wordRanges(v.text);
    final word = _word < ranges.length ? _word : 0;
    _base = ranges[word].start;
    _utterance = v.text.substring(_base);
    owner._moved((verse: v.verse, word: word));
    await tts.speak(_utterance!);
  }

  @override
  Future<void> play() async {
    _speaking = true;
    owner._status(ReadAlongStatus.playing);
    await _speak();
  }

  @override
  Future<void> pause() async {
    _speaking = false;
    owner._status(ReadAlongStatus.paused);
    await tts.stop();
  }

  @override
  Future<void> seek(int verse, int word) async {
    final i = verses.indexWhere((v) => v.verse == verse);
    if (i < 0) return;
    _index = i;
    _word = word;
    owner._moved((verse: verse, word: word));
    if (!_speaking) return;
    await tts.stop();
    await _speak();
  }

  /// Apple and Android scale speech differently; each reports its normal rate.
  @override
  Future<void> setSpeed(double speed) async {
    final range = await tts.getSpeechRateValidRange;
    await tts.setSpeechRate((range.normal * speed).clamp(range.min, range.max));
  }

  @override
  Future<void> release() async => _speaking = false;

  @override
  Future<void> stop() async {
    await release();
    await tts.stop();
  }
}
