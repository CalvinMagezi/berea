import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'app_state.dart';
import 'voice_wav.dart';

export 'voice_wav.dart';

/// The longest spoken question Berea records; Gemma's audio input is meant for short clips.
const maxVoiceDuration = Duration(seconds: 30);

/// Shorter holds are taps or slips, not questions.
const minVoiceDuration = Duration(milliseconds: 600);

/// How often the visible timer and the cap are checked.
const voiceTick = Duration(milliseconds: 100);

/// A phone CPU can take a while on 30 seconds of audio, but not this long.
const voiceTranscribeTimeout = Duration(minutes: 2);

/// macOS finishes writing the file after stop returns; wait this long at most for it.
const voiceFinalizeLimit = Duration(seconds: 2);
const voiceFinalizePoll = Duration(milliseconds: 50);

/// A late writer can recreate a file just deleted, so it is deleted again after this.
const voiceLateWriteGrace = Duration(seconds: 2);

/// Each process records into its own private folder with this prefix in the app's cache.
const voiceDirPrefix = 'berea-voice-';

const micDeniedMessage =
    'Berea cannot use the microphone. Allow it for Berea in system Settings, then try again.';
const micUnavailableMessage =
    'No microphone could be opened. Check that one is connected and not in use. On Linux, '
    'voice needs parecord and ffmpeg installed.';
const tooShortMessage = 'Hold the microphone while you speak, or tap it to start and stop.';
const nothingHeardMessage = 'Nothing was heard. Try again, or type your question.';
const voiceFailedMessage = 'That recording could not be transcribed. Try again, or type it.';
const voiceTimeoutMessage = 'Transcribing took too long. Try a shorter question, or type it.';
const needsGemma4Message =
    'Voice questions need Gemma 4 on this device, which hears speech itself. Choose Gemma 4 E2B '
    'or E4B under Engine in Settings.';
const audioUnavailableMessage =
    'The audio part of Gemma 4 did not load on this device, so voice is off. Typed questions '
    'still work.';

String wrongRateMessage(int? rate) =>
    'The microphone recorded at ${rate ?? 'an unknown rate'} Hz instead of 16000 Hz, which Gemma '
    'cannot read. Choose another input in system Settings, or type your question.';

enum VoicePhase { idle, starting, recording, transcribing, confirm }

enum VoiceSupport { ready, notReady, needsGemma4, unavailable }

/// Voice needs the on-device engine with a Gemma 4 model that loaded with its audio encoder.
VoiceSupport voiceSupport(Settings settings, DeviceModelState state, {required bool hearsAudio}) {
  if (settings.engine != EngineKind.device || !settings.deviceModel.hearsAudio) {
    return VoiceSupport.needsGemma4;
  }
  if (state != DeviceModelState.ready) return VoiceSupport.notReady;
  return hearsAudio ? VoiceSupport.ready : VoiceSupport.unavailable;
}

final _labelPrefix = RegExp(r'^(transcript|transcription)\s*:\s*', caseSensitive: false);
final _noSpeech = RegExp(
  r'^[\s\p{P}\p{S}]*(no speech|silence|inaudible|no audio|nothing|music|noise|um+|uh+|hmm+|ah+)?'
  r'[\s\p{P}\p{S}]*$',
  caseSensitive: false,
  unicode: true,
);
const _openQuotes = '"\'“‘';
const _closeQuotes = '"\'”’';

/// The words alone: no label, no wrapping quotes, and empty when Gemma heard no speech.
String cleanTranscript(String raw) {
  var t = raw.trim().replaceFirst(_labelPrefix, '').trim();
  while (t.length >= 2 &&
      _openQuotes.contains(t[0]) &&
      _closeQuotes.contains(t[t.length - 1])) {
    t = t.substring(1, t.length - 1).trim();
  }
  return _noSpeech.hasMatch(t) ? '' : t;
}

String _messageFor(WavProblem problem, Uint8List wav) => switch (problem) {
  WavProblem.wrongRate => wrongRateMessage(wavSampleRate(wav)),
  WavProblem.tooShort => tooShortMessage,
  _ => voiceFailedMessage,
};

class _WavRejected implements Exception {
  final String message;
  const _WavRejected(this.message);
}

class _MicUnavailable implements Exception {
  const _MicUnavailable();
}

void _deleteFile(String? path) {
  if (path == null) return;
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } on FileSystemException catch (e) {
    debugPrint('Could not delete a voice recording: ${e.osError?.errorCode}');
  }
}

/// Folders already swept in this process; a folder from an earlier run has no owner left.
final _sweptBases = <String>{};

/// Removes every recording folder an earlier run left behind, without following links.
void _sweepBase(Directory base) {
  if (!_sweptBases.add(base.path) || !base.existsSync()) return;
  for (final e in base.listSync(followLinks: false)) {
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final isDir = FileSystemEntity.typeSync(e.path, followLinks: false) ==
        FileSystemEntityType.directory;
    if (!isDir || !name.startsWith(voiceDirPrefix)) continue;
    try {
      e.deleteSync(recursive: true);
    } on FileSystemException catch (err) {
      debugPrint('Could not clear old voice recordings: ${err.osError?.errorCode}');
    }
  }
}

/// One voice session for the whole app; the recording is a temp file deleted on every path.
class VoiceInput extends ChangeNotifier {
  final AudioRecorder _recorder;
  final Future<String> Function(Uint8List wav) _transcribe;
  final Future<Directory> Function() _cacheDir;
  final Stopwatch Function() newStopwatch;
  final Duration maxDuration;
  final Duration minDuration;
  final Duration transcribeTimeout;

  VoiceInput({
    required Future<String> Function(Uint8List wav) transcribe,
    AudioRecorder? recorder,
    Future<Directory> Function()? cacheDir,
    this.newStopwatch = Stopwatch.new,
    this.maxDuration = maxVoiceDuration,
    this.minDuration = minVoiceDuration,
    this.transcribeTimeout = voiceTranscribeTimeout,
  }) : _transcribe = transcribe,
       _recorder = recorder ?? AudioRecorder(),
       _cacheDir = cacheDir ?? getApplicationCacheDirectory {
    _folder = _prepareFolder();
    unawaited(_folder.then((_) {}, onError: (_) {}));
  }

  VoicePhase phase = VoicePhase.idle;

  /// The composer that started the session; only it shows the status and takes the transcript.
  Object? owner;

  /// True while the press that started this recording is still held, for the status hint.
  bool held = false;

  /// The last problem, for the composer to show. Cleared when a new recording starts.
  String? message;

  /// What Gemma heard, set when [phase] is [VoicePhase.confirm].
  String transcript = '';

  /// This process's private recordings folder, created after old ones are swept.
  late final Future<Directory> _folder;

  /// Bumped by cancel and dispose so a late result from an older session is dropped.
  int _session = 0;
  Stopwatch? _watch;
  Timer? _ticker;
  String? _path;
  bool _stopRequested = false;
  bool _cancelRequested = false;
  bool _disposed = false;
  Future<void>? _opening;
  final _lateDeletes = <Timer>[];

  Duration get elapsed {
    final e = _watch?.elapsed ?? Duration.zero;
    return e > maxDuration ? maxDuration : e;
  }

  bool get recording => phase == VoicePhase.starting || phase == VoicePhase.recording;

  /// Recording or transcribing: no other question may be sent meanwhile.
  bool get inUse => recording || phase == VoicePhase.transcribing;

  bool ownedBy(Object who) => owner == who;

  /// A per-user cache folder, and inside it a fresh folder only this user can open.
  Future<Directory> _prepareFolder() async {
    final base = await _cacheDir();
    base.createSync(recursive: true);
    _sweepBase(base);
    return base.createTempSync(voiceDirPrefix);
  }

  Future<void> start(Object who) async {
    if (inUse || _disposed) return;
    owner = who;
    held = true;
    phase = VoicePhase.starting;
    _stopRequested = false;
    _cancelRequested = false;
    message = null;
    transcript = '';
    final session = ++_session;
    _notify();
    final opening = _open();
    _opening = opening.then((_) {}, onError: (_) {});
    String? path;
    try {
      path = await opening;
    } catch (e) {
      debugPrint('Voice recording did not start: ${e.runtimeType}');
      message = e is _MicUnavailable ? micUnavailableMessage : voiceFailedMessage;
    }
    if (path == null || session != _session || _cancelRequested || _stopRequested) {
      // A release before recording began is a slip, never a zero-length question.
      if (path != null && _stopRequested && !_cancelRequested) message = tooShortMessage;
      await _discard(path);
      if (session == _session) _settle(VoicePhase.idle);
      return;
    }
    _path = path;
    phase = VoicePhase.recording;
    _watch = newStopwatch()..start();
    _ticker = Timer.periodic(voiceTick, (_) => _onTick());
    _notify();
  }

  /// Null when permission was refused. Throws when there is no usable microphone.
  Future<String?> _open() async {
    final bool allowed;
    try {
      allowed = await _recorder.hasPermission();
    } catch (_) {
      throw const _MicUnavailable();
    }
    if (!allowed) {
      message = micDeniedMessage;
      return null;
    }
    final dir = await _folder;
    final path = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: voiceSampleRate,
          numChannels: voiceChannels,
        ),
        path: path,
      );
    } catch (_) {
      _deleteFile(path);
      throw const _MicUnavailable();
    }
    return path;
  }

  void _onTick() {
    _notify();
    if (elapsed >= maxDuration) unawaited(stop());
  }

  Duration _stopClock() {
    _ticker?.cancel();
    _ticker = null;
    final took = _watch?.elapsed ?? Duration.zero;
    _watch?.stop();
    return took;
  }

  /// Ends the recording and transcribes it. A stop while starting discards it as a slip.
  Future<void> stop() async {
    if (phase == VoicePhase.starting) {
      _stopRequested = true;
      return;
    }
    if (phase != VoicePhase.recording) return;
    final took = _stopClock();
    final path = _path!;
    _path = null;
    final session = _session;
    held = false;
    phase = VoicePhase.transcribing;
    _notify();
    try {
      await _recorder.stop();
      if (took < minDuration) {
        message = tooShortMessage;
        return;
      }
      final heard = await _heard(path);
      if (session != _session) return;
      if (heard.isEmpty) {
        message = nothingHeardMessage;
        return;
      }
      transcript = heard;
      phase = VoicePhase.confirm;
    } on _WavRejected catch (e) {
      if (session == _session) message = e.message;
    } catch (e) {
      debugPrint('Voice transcription failed: ${e.runtimeType}');
      if (session == _session) {
        message = e is TimeoutException ? voiceTimeoutMessage : voiceFailedMessage;
      }
    } finally {
      _deleteNowAndLater(path);
      if (session == _session && phase == VoicePhase.transcribing) phase = VoicePhase.idle;
      _notify();
    }
  }

  /// The file is deleted before the model hears the audio, so from then on only memory holds it.
  Future<String> _heard(String path) async {
    final wav = repairWavSizes(await _readFinished(path));
    _deleteNowAndLater(path);
    final problem = wavProblem(wav, maxDuration: maxDuration);
    if (problem != null) {
      debugPrint('Voice recording rejected: ${problem.name}');
      throw _WavRejected(_messageFor(problem, wav));
    }
    return cleanTranscript(await _transcribe(wav).timeout(transcribeTimeout));
  }

  /// macOS replies to stop before the file is finalised, so wait for a consistent header.
  Future<Uint8List> _readFinished(String path) async {
    for (var waited = Duration.zero; ; waited += voiceFinalizePoll) {
      final file = File(path);
      final bytes = file.existsSync() ? file.readAsBytesSync() : Uint8List(0);
      if (wavSizesConsistent(bytes) || waited >= voiceFinalizeLimit) return bytes;
      await Future<void>.delayed(voiceFinalizePoll);
    }
  }

  void _deleteNowAndLater(String? path) {
    if (path == null) return;
    _deleteFile(path);
    _lateDeletes.add(Timer(voiceLateWriteGrace, () => _deleteFile(path)));
    _lateDeletes.removeWhere((t) => !t.isActive);
  }

  /// Throws away a recording or a transcription in progress.
  Future<void> cancel() async {
    switch (phase) {
      case VoicePhase.starting:
        _cancelRequested = true;
      case VoicePhase.recording:
        await cancelRecording();
      case VoicePhase.transcribing:
        _session++;
        _settle(VoicePhase.idle);
      case VoicePhase.idle || VoicePhase.confirm:
        return;
    }
  }

  /// Stops listening without transcribing; for an app sent to the background or a hidden tab.
  Future<void> cancelRecording() async {
    if (phase == VoicePhase.starting) {
      _cancelRequested = true;
      return;
    }
    if (phase != VoicePhase.recording) return;
    _stopClock();
    final path = _path;
    _path = null;
    _session++;
    _settle(VoicePhase.idle);
    await _discard(path);
  }

  void onLifecycle(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(cancelRecording());
  }

  /// A composer that goes away takes its session with it.
  Future<void> release(Object who) async {
    if (!ownedBy(who)) return;
    if (phase == VoicePhase.confirm) accept();
    await cancel();
    owner = null;
  }

  /// A quick tap started this recording, so the composer now stops it on the next tap.
  void switchToTapMode() {
    if (!held) return;
    held = false;
    _notify();
  }

  /// The user sent or cleared the transcript.
  void accept() {
    if (phase != VoicePhase.confirm) return;
    transcript = '';
    _settle(VoicePhase.idle);
  }

  void _settle(VoicePhase next) {
    phase = next;
    held = false;
    _notify();
  }

  Future<void> _discard(String? path) async {
    if (path == null) return;
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('Voice recorder did not cancel: ${e.runtimeType}');
    }
    _deleteNowAndLater(path);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _stopClock();
    final path = _path;
    _path = null;
    final opening = _opening;
    unawaited(() async {
      // An in-flight start sees the bumped session and discards its own file.
      await opening;
      await _discard(path);
      try {
        await _recorder.dispose();
      } catch (e) {
        debugPrint('Voice recorder did not close: ${e.runtimeType}');
      }
      for (final t in _lateDeletes) {
        t.cancel();
      }
      try {
        (await _folder).deleteSync(recursive: true);
      } on Object catch (e) {
        debugPrint('Could not remove the voice folder: ${e.runtimeType}');
      }
    }());
    super.dispose();
  }
}
