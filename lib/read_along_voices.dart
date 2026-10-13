part of 'read_along.dart';

/// Android's mark on a voice whose data still has to be downloaded.
const _voiceNotInstalled = 'notInstalled';

/// Android's mark on a voice synthesised on the device.
const _voiceEmbedded = 'embeddedTts';

/// Android's mark on a voice synthesised on a server.
const _voiceNetwork = 'networkTts';

/// flutter_tts reports success as 1.
const _ttsOk = 1;

/// A voice the read-along drives: the downloaded narration or the device's own speech.
abstract class _Voice {
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int verse, int word);
  Future<void> setSpeed(double speed);

  /// Takes over the engine's callbacks; done only once this voice is the current one.
  void attach();

  /// Stops listening to the engine without touching playback, for a superseded load.
  Future<void> release();
  Future<void> stop();
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

  /// Also resyncs the bar after the notification's own play, pause or stop.
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

  /// Not awaited: just_audio's play() completes only when playback stops.
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

/// The device's offline voice through flutter_tts, one utterance per verse.
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
    // Apple pauses and resumes speech itself, for a call for example.
    tts.setPauseHandler(() => owner._status(ReadAlongStatus.paused));
    tts.setContinueHandler(() => owner._status(ReadAlongStatus.playing));
    tts.setErrorHandler((message) {
      _speaking = false;
      debugPrint('Device voice error: $message');
      owner.state.value = owner.state.value?.copyWith(
        status: ReadAlongStatus.failed,
        error: 'The device voice stopped. Tap Listen to try again.',
      );
    });
  }

  /// Chooses an English voice that needs no download and no network, or says there is none.
  static Future<void> prepare(FlutterTts tts) async {
    await tts.awaitSpeakCompletion(false);
    if (defaultTargetPlatform == TargetPlatform.android) return _chooseAndroidVoice(tts);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        const [],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    }
    // Apple's voices are all on the device; the language may still be missing.
    for (final language in const ['en-US', 'en']) {
      if (await tts.setLanguage(language) == _ttsOk) return;
    }
    throw const FormatException(
      'No English voice is installed. Add one in the system spoken content settings.',
    );
  }

  /// Android says which voices need the network or a download; those are never used.
  static Future<void> _chooseAndroidVoice(FlutterTts tts) async {
    final local = <Map<String, String>>[];
    for (final v in (await tts.getVoices as List? ?? const [])) {
      if (v is! Map) continue;
      final features = '${v['features'] ?? ''}'.split('\t');
      final english = '${v['locale']}'.toLowerCase().startsWith('en');
      final offline =
          v['network_required'] == '0' &&
          !features.contains(_voiceNotInstalled) &&
          !features.contains(_voiceNetwork);
      if (english && offline) {
        local.add({
          'name': '${v['name']}',
          'locale': '${v['locale']}',
          'embedded': '${features.contains(_voiceEmbedded)}',
        });
      }
    }
    if (local.isEmpty) {
      throw const FormatException(
        'No offline English voice is installed. Add one in the system text-to-speech settings.',
      );
    }
    int rank(Map<String, String> v) =>
        (v['embedded'] == 'true' ? 0 : 2) + (v['locale']!.toLowerCase() == 'en-us' ? 0 : 1);
    local.sort((a, b) => rank(a).compareTo(rank(b)));
    final best = local.first;
    await tts.setVoice({'name': best['name']!, 'locale': best['locale']!});
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

  /// Starts afresh from the current word, which also clears anything the system paused.
  @override
  Future<void> play() async {
    _speaking = false;
    await tts.stop();
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
    if (_speaking) await play();
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
