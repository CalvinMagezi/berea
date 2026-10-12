import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'narration_packs.dart';
import 'pinned_download.dart';

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

  /// Takes over the engine's callbacks; done only once this voice is the current one.
  void attach();

  /// Stops listening to the engine without touching playback, for a load that was superseded.
  Future<void> release();
  Future<void> stop();
}

/// Plays a chapter with the current word highlighted and the reader following along. The
/// player and the speech engine are created only when first used; the lock-screen service is
/// bound at startup by [initReadAlongAudio].
class ReadAlong {
  final NarrationShelf shelf;
  ReadAlong(this.shelf);

  /// Null while nothing is loaded.
  final state = ValueNotifier<ReadAlongState?>(null);

  /// Changes with every word, so it is kept apart from [state] and from the app's listeners.
  final position = ValueNotifier<ReadAlongPosition?>(null);

  /// Timed words of the narrated chapter; null for the device voice.
  ChapterTimings? timings;

  /// Kept across chapters and voices.
  var _speed = 1.0;

  AudioPlayer? _player;
  FlutterTts? _tts;
  _Voice? _voice;

  /// For the integration test, which mutes playback and reads the player's own clock.
  @visibleForTesting
  AudioPlayer? get debugPlayer => _player;
  @visibleForTesting
  FlutterTts? get debugTts => _tts;

  /// Milliseconds added to every timing for this player; see [primingOffsetMs].
  int get offsetMs => switch (_voice) {
    _Narration(:final offsetMs) => offsetMs,
    _ => 0,
  };

  /// Bumped by every start and stop, so a slow load that was superseded touches nothing.
  var _generation = 0;

  bool isOn(int book, int chapter) {
    final s = state.value;
    return s != null && s.book == book && s.chapter == chapter;
  }

  /// Whether the voice's word numbers fit [text]: narration timings count the Berean Standard
  /// Bible's words, so another translation, or a verse worded differently, follows by verse.
  bool wordsFit(int verse, String text, String translation) {
    final t = timings;
    if (t == null) return true;
    if (translation != defaultTranslation) return false;
    return t.wordsPerVerse[verse] == wordRanges(text).length;
  }

  /// The word to highlight in [verse], or null to mark only the verse.
  int? wordToShow(int verse, String text, String translation) {
    final at = position.value;
    if (at == null || at.verse != verse) return null;
    return wordsFit(verse, text, translation) ? at.word : null;
  }

  /// Starts [voice] on [book] [chapter]. Narration downloads its pack first if it must.
  /// [verses] is the chapter as shown, which the device voice reads.
  Future<void> start({
    required Book book,
    required int chapter,
    required ReadAlongVoice voice,
    required List<Verse> verses,
  }) async {
    final previous = _reset();
    final generation = _generation;
    state.value = ReadAlongState(
      book: book.id,
      chapter: chapter,
      voice: voice,
      status: ReadAlongStatus.loading,
      speed: _speed,
    );
    try {
      await previous?.stop();
      final v = voice == ReadAlongVoice.narration
          ? await _loadNarration(book, chapter, generation)
          : await _loadDeviceVoice(verses);
      if (v == null || generation != _generation) return await v?.release();
      _voice = v;
      if (v is _Narration) {
        timings = v.timings;
        shelf.prunePlayed(keep: v.file);
      }
      v.attach();
      await v.setSpeed(_speed);
      await v.play();
    } on Object catch (e) {
      if (generation == _generation) _fail(e);
    }
  }

  void _fail(Object e) => state.value = state.value?.copyWith(
    status: ReadAlongStatus.failed,
    error: describeFailure(e),
  );

  /// Null when a newer start or a stop came first; nothing shared is touched after that.
  Future<_Narration?> _loadNarration(Book book, int chapter, int generation) async {
    if (!shelf.isInstalled(book.id)) await shelf.download(book.id);
    if (generation != _generation) return null;
    final track = await shelf.track(book.id, chapter);
    if (generation != _generation) return null;
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
    final offset = primingOffsetMs(
      reported: reported,
      durationMs: track.durationMs,
      primingMs: track.primingMs,
    );
    debugPrint(
      'Narration ${book.name} $chapter: player reports ${reported?.inMilliseconds} ms, '
      'pack ${track.durationMs} ms, timing offset $offset ms',
    );
    return _Narration(this, player, track.timings, offset, track.file);
  }

  Future<_Voice> _loadDeviceVoice(List<Verse> verses) async {
    final tts = _tts ??= FlutterTts();
    await _DeviceVoice.prepare(tts);
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

  /// The next verse with words after the current one, skipping empty verses.
  Future<void> nextVerse() async {
    final at = position.value?.verse;
    final next = _verseNumbers().where((v) => at == null || v > at).firstOrNull;
    if (next != null) await seek(next);
  }

  Future<void> previousVerse() async {
    final at = position.value?.verse;
    final verses = _verseNumbers();
    final previous = at == null ? verses.firstOrNull : verses.where((v) => v < at).lastOrNull;
    await seek(previous ?? verses.firstOrNull ?? 1);
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
    _speed = speed;
    state.value = state.value?.copyWith(speed: speed);
    await _voice?.setSpeed(speed);
  }

  /// Stops and clears the player; the bar goes away.
  Future<void> stop() async => _reset()?.stop();

  /// Clears everything at once, before any await, so a start or stop racing this one sees it.
  _Voice? _reset() {
    _generation++;
    final v = _voice;
    _voice = null;
    state.value = null;
    position.value = null;
    timings = null;
    return v;
  }
}

/// The downloaded narration through just_audio, with the lock-screen controls.
class _Narration implements _Voice {
  final ReadAlong owner;
  final AudioPlayer player;
  final ChapterTimings timings;

  /// Milliseconds added to every timing for this player; see [primingOffsetMs].
  final int offsetMs;

  /// The extracted chapter this player has open.
  final File file;
  Timer? _tick;
  StreamSubscription<PlayerState>? _states;

  /// Whether the app is on screen; with the screen locked nobody sees the highlight.
  var _visible = true;
  AppLifecycleListener? _lifecycle;

  _Narration(this.owner, this.player, this.timings, this.offsetMs, this.file);

  @override
  void attach() {
    _states = player.playerStateStream.listen(_onState);
    _lifecycle = AppLifecycleListener(
      onShow: () => _setVisible(true),
      onHide: () => _setVisible(false),
    );
  }

  void _setVisible(bool visible) {
    _visible = visible;
    _retick();
    if (visible) _follow();
  }

  /// Polls the position only while playing and on screen.
  void _retick() {
    if (player.playing && _visible) {
      _tick ??= Timer.periodic(readAlongTick, (_) => _follow());
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _onState(PlayerState s) {
    if (s.processingState == ProcessingState.completed) {
      unawaited(_rewind());
      return;
    }
    _retick();
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
    final i = timings.indexAt(player.position.inMilliseconds - offsetMs);
    owner._moved(i == null ? null : (verse: timings.words[i].verse, word: timings.words[i].word));
  }

  /// just_audio's play() completes only when playback stops, so it is not awaited.
  @override
  Future<void> play() async => unawaited(player.play().catchError(owner._fail));

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(int verse, int word) async {
    final i = timings.indexOf(verse, word);
    if (i == null) return;
    await player.seek(Duration(milliseconds: timings.words[i].startMs + offsetMs));
    _follow();
  }

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);

  @override
  Future<void> release() async {
    _tick?.cancel();
    _tick = null;
    _lifecycle?.dispose();
    await _states?.cancel();
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

  _DeviceVoice(this.owner, this.tts, this.verses);

  @override
  void attach() {
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
