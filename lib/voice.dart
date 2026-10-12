import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'app_state.dart';

/// The longest spoken question Berea records; Gemma's audio input is meant for short clips.
const maxVoiceDuration = Duration(seconds: 30);

/// Shorter holds are taps or slips, not questions.
const minVoiceDuration = Duration(milliseconds: 600);

/// How often the visible timer and the cap are checked.
const voiceTick = Duration(milliseconds: 250);

/// Gemma reads 16 kHz mono 16-bit PCM WAV.
const voiceSampleRate = 16000;
const voiceChannels = 1;
const voiceBitsPerSample = 16;

const _voiceDirName = 'berea-voice';
const _wavPcmFormat = 1;
const _wavHeaderBytes = 12;
const _chunkHeaderBytes = 8;
const _fmtMinBytes = 16;

const micDeniedMessage =
    'Berea cannot use the microphone. Allow it for Berea in system Settings, then try again.';
const tooShortMessage = 'Hold the microphone while you speak, or tap it to start and stop.';
const nothingHeardMessage = 'Nothing was heard. Try again, or type your question.';
const voiceFailedMessage = 'That recording could not be transcribed. Try again, or type it.';
const needsGemma4Message =
    'Voice questions need Gemma 4 on this device, which hears speech itself. Choose Gemma 4 E2B '
    'or E4B under Engine in Settings.';

enum VoicePhase { idle, recording, transcribing, confirm }

enum VoiceSupport { ready, notReady, needsGemma4 }

/// Voice needs the on-device engine with a Gemma 4 model that has finished loading.
VoiceSupport voiceSupport(Settings settings, DeviceModelState state) {
  if (settings.engine != EngineKind.device || !settings.deviceModel.hearsAudio) {
    return VoiceSupport.needsGemma4;
  }
  return state == DeviceModelState.ready ? VoiceSupport.ready : VoiceSupport.notReady;
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

/// Hold-to-talk state: idle, recording, transcribing, then confirm with the transcript in the
/// input. The recording is a temporary file that is deleted on every path and never sent.
class VoiceInput extends ChangeNotifier {
  final AudioRecorder _recorder;
  final Future<String> Function(Uint8List wav) _transcribe;
  final Future<Directory> Function() _tempDir;
  final Duration maxDuration;
  final Duration minDuration;

  VoiceInput({
    required Future<String> Function(Uint8List wav) transcribe,
    AudioRecorder? recorder,
    Future<Directory> Function()? tempDir,
    this.maxDuration = maxVoiceDuration,
    this.minDuration = minVoiceDuration,
  }) : _transcribe = transcribe,
       _recorder = recorder ?? AudioRecorder(),
       _tempDir = tempDir ?? voiceTempDir {
    // A crash mid-recording can strand a file; nothing in the folder is worth keeping.
    unawaited(_sweep());
  }

  VoicePhase phase = VoicePhase.idle;
  Duration elapsed = Duration.zero;

  /// The last problem, for the composer to show. Cleared when a new recording starts.
  String? message;

  /// What Gemma heard, set when [phase] is [VoicePhase.confirm].
  String transcript = '';

  Timer? _timer;
  String? _path;
  bool _starting = false;
  bool _stopRequested = false;
  bool _cancelRequested = false;
  bool _disposed = false;

  bool get active => _starting || phase == VoicePhase.recording;

  Future<void> start() async {
    if (_starting || phase == VoicePhase.recording || phase == VoicePhase.transcribing) return;
    _starting = true;
    _stopRequested = false;
    _cancelRequested = false;
    message = null;
    phase = VoicePhase.idle;
    _notify();
    try {
      await _begin();
    } finally {
      _starting = false;
    }
    if (phase != VoicePhase.recording) return;
    if (_cancelRequested) {
      await cancel();
    } else if (_stopRequested) {
      await stop();
    }
  }

  Future<void> _begin() async {
    if (!await _recorder.hasPermission()) {
      message = micDeniedMessage;
      _notify();
      return;
    }
    if (_disposed) return;
    final dir = await _tempDir();
    await dir.create(recursive: true);
    final path = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.wav';
    _path = path;
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: voiceSampleRate,
          numChannels: voiceChannels,
        ),
        path: path,
      );
    } catch (e) {
      debugPrint('Voice recording did not start: ${e.runtimeType}');
      message = voiceFailedMessage;
      await _deleteRecording();
      _notify();
      return;
    }
    if (_disposed) {
      await _recorder.cancel();
      await _deleteRecording();
      return;
    }
    phase = VoicePhase.recording;
    elapsed = Duration.zero;
    _timer = Timer.periodic(voiceTick, (_) => _onTick());
    _notify();
  }

  void _onTick() {
    elapsed += voiceTick;
    _notify();
    if (elapsed >= maxDuration) unawaited(stop());
  }

  /// Ends the recording and transcribes it. A stop during start is held until recording begins.
  Future<void> stop() async {
    if (_starting) {
      _stopRequested = true;
      return;
    }
    if (phase != VoicePhase.recording) return;
    _timer?.cancel();
    final tooShort = elapsed < minDuration;
    phase = VoicePhase.transcribing;
    _notify();
    try {
      await _recorder.stop();
      if (tooShort) {
        message = tooShortMessage;
        return;
      }
      final heard = await _transcribeFile();
      if (heard.isEmpty) {
        message = nothingHeardMessage;
        return;
      }
      transcript = heard;
      phase = VoicePhase.confirm;
    } catch (e) {
      debugPrint('Voice transcription failed: ${e.runtimeType}');
      message = voiceFailedMessage;
    } finally {
      await _deleteRecording();
      if (phase == VoicePhase.transcribing) phase = VoicePhase.idle;
      _notify();
    }
  }

  Future<String> _transcribeFile() async {
    final wav = await File(_path!).readAsBytes();
    final problem = wavProblem(wav);
    if (problem != null) throw FormatException('Recording is $problem');
    return (await _transcribe(wav)).trim();
  }

  /// Throws the recording away without transcribing it.
  Future<void> cancel() async {
    if (_starting) {
      _cancelRequested = true;
      return;
    }
    _timer?.cancel();
    if (phase == VoicePhase.recording) {
      phase = VoicePhase.idle;
      await _recorder.cancel();
    }
    await _deleteRecording();
    _notify();
  }

  /// The user sent or cleared the transcript.
  void accept() {
    if (phase != VoicePhase.confirm) return;
    phase = VoicePhase.idle;
    transcript = '';
    _notify();
  }

  Future<void> _deleteRecording() async {
    final path = _path;
    _path = null;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (e) {
      debugPrint('Could not delete a voice recording: ${e.osError?.errorCode}');
    }
  }

  Future<void> _sweep() async {
    try {
      final dir = await _tempDir();
      if (!await dir.exists()) return;
      await for (final f in dir.list()) {
        if (f is File && f.path != _path) await f.delete();
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
    _timer?.cancel();
    final recording = phase == VoicePhase.recording;
    unawaited(() async {
      if (recording) await _recorder.cancel();
      await _deleteRecording();
      await _recorder.dispose();
    }());
    super.dispose();
  }
}
