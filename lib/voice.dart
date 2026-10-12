import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'app_state.dart';

/// The longest spoken question Berea records; Gemma's audio input is meant for short clips.
const maxVoiceDuration = Duration(seconds: 30);

/// Shorter holds are taps or slips, not questions.
const minVoiceDuration = Duration(milliseconds: 600);

/// How often the visible timer and the cap are checked.
const voiceTick = Duration(milliseconds: 100);

/// A phone CPU can take a while on 30 seconds of audio, but not this long.
const voiceTranscribeTimeout = Duration(minutes: 2);

/// Gemma reads 16 kHz mono 16-bit PCM WAV.
const voiceSampleRate = 16000;
const voiceChannels = 1;
const voiceBitsPerSample = 16;

const _voiceDirName = 'berea-voice';

/// Older files are leftovers from a crash; a live recording is never this old.
const staleVoiceAge = Duration(minutes: 10);

const _wavPcmFormat = 1;
const _wavHeaderBytes = 12;
const _chunkHeaderBytes = 8;
const _fmtMinBytes = 16;

const micDeniedMessage =
    'Berea cannot use the microphone. Allow it for Berea in system Settings, then try again.';
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

/// Null when [wav] is the 16 kHz mono 16-bit PCM Gemma reads, otherwise why it is not.
String? wavProblem(Uint8List wav) {
  if (wav.length < _wavHeaderBytes ||
      String.fromCharCodes(wav, 0, 4) != 'RIFF' ||
      String.fromCharCodes(wav, 8, 12) != 'WAVE') {
    return 'not a WAV file';
  }
  final view = ByteData.sublistView(wav);
  var offset = _wavHeaderBytes;
  while (offset + _chunkHeaderBytes <= wav.length) {
    final id = String.fromCharCodes(wav, offset, offset + 4);
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + _chunkHeaderBytes;
    if (id == 'fmt ') {
      if (size < _fmtMinBytes || body + _fmtMinBytes > wav.length) return 'short format chunk';
      return _formatProblem(view, body);
    }
    offset = body + size + size % 2;
  }
  return 'no format chunk';
}

String? _formatProblem(ByteData view, int at) {
  final format = view.getUint16(at, Endian.little);
  final channels = view.getUint16(at + 2, Endian.little);
  final rate = view.getUint32(at + 4, Endian.little);
  final bits = view.getUint16(at + 14, Endian.little);
  if (format != _wavPcmFormat) return 'not PCM';
  if (channels != voiceChannels) return '$channels channels';
  if (rate != voiceSampleRate) return '$rate Hz';
  if (bits != voiceBitsPerSample) return '$bits-bit';
  return null;
}

/// Where recordings live while they are transcribed. Everything in it is temporary.
Future<Directory> voiceTempDir() async =>
    Directory('${(await getTemporaryDirectory()).path}/$_voiceDirName');

void _deleteFile(String? path) {
  if (path == null) return;
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } on FileSystemException catch (e) {
    debugPrint('Could not delete a voice recording: ${e.osError?.errorCode}');
  }
}

/// One voice session for the whole app; the recording is a temp file deleted on every path.
class VoiceInput extends ChangeNotifier {
  final AudioRecorder _recorder;
  final Future<String> Function(Uint8List wav) _transcribe;
  final Future<Directory> Function() _tempDir;
  final Stopwatch Function() newStopwatch;
  final Duration maxDuration;
  final Duration minDuration;
  final Duration transcribeTimeout;

  VoiceInput({
    required Future<String> Function(Uint8List wav) transcribe,
    AudioRecorder? recorder,
    Future<Directory> Function()? tempDir,
    this.newStopwatch = Stopwatch.new,
    this.maxDuration = maxVoiceDuration,
    this.minDuration = minVoiceDuration,
    this.transcribeTimeout = voiceTranscribeTimeout,
  }) : _transcribe = transcribe,
       _recorder = recorder ?? AudioRecorder(),
       _tempDir = tempDir ?? voiceTempDir {
    unawaited(_sweep());
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

  /// Bumped by cancel and dispose so a late result from an older session is dropped.
  int _session = 0;
  Stopwatch? _watch;
  Timer? _ticker;
  String? _path;
  bool _stopRequested = false;
  bool _cancelRequested = false;
  bool _disposed = false;
  Future<void>? _opening;

  Duration get elapsed {
    final e = _watch?.elapsed ?? Duration.zero;
    return e > maxDuration ? maxDuration : e;
  }

  bool get recording => phase == VoicePhase.starting || phase == VoicePhase.recording;

  /// Recording or transcribing: no other question may be sent meanwhile.
  bool get inUse => recording || phase == VoicePhase.transcribing;

  bool ownedBy(Object who) => owner == who;

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
      message = voiceFailedMessage;
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

  /// Null when permission was refused. Throws when the recorder cannot start.
  Future<String?> _open() async {
    if (!await _recorder.hasPermission()) {
      message = micDeniedMessage;
      return null;
    }
    final dir = await _tempDir();
    dir.createSync(recursive: true);
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
      rethrow;
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
    } catch (e) {
      debugPrint('Voice transcription failed: ${e.runtimeType}');
      if (session == _session) {
        message = e is TimeoutException ? voiceTimeoutMessage : voiceFailedMessage;
      }
    } finally {
      _deleteFile(path);
      if (session == _session && phase == VoicePhase.transcribing) phase = VoicePhase.idle;
      _notify();
    }
  }

  /// The file is deleted before the model sees the audio, so only memory holds it.
  Future<String> _heard(String path) async {
    final wav = File(path).readAsBytesSync();
    _deleteFile(path);
    final problem = wavProblem(wav);
    if (problem != null) throw FormatException('Recording is $problem');
    return (await _transcribe(wav).timeout(transcribeTimeout)).trim();
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
    _deleteFile(path);
  }

  Future<void> _sweep() async {
    try {
      final dir = await _tempDir();
      if (!dir.existsSync()) return;
      final now = DateTime.now();
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path != _path && now.difference(f.statSync().modified) > staleVoiceAge) {
          _deleteFile(f.path);
        }
      }
    } on Object catch (e) {
      debugPrint('Could not clear old voice recordings: ${e.runtimeType}');
    }
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
    }());
    super.dispose();
  }
}
