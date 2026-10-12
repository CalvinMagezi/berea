import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:berea_harness/berea_harness.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'pinned_download.dart';

const voiceDownloadTimeout = Duration(minutes: 10);

/// Progress is reported in whole percents, so a download redraws the app at most this often.
const _progressSteps = 100;
const _bytesPerFloat = 4;

/// The optional voice pack on the device: the pinned files in one folder. Downloads happen
/// only when the user asks.
class VoiceShelf {
  final Directory dir;
  final void Function() onChange;

  /// The pinned files this shelf keeps; tests pass small ones.
  final List<VoicePackFile> files;

  /// Download progress from 0 to 1 while the pack is being fetched.
  double? progress;

  VoiceShelf(this.dir, this.onChange, {Iterable<VoicePackFile>? files})
    : files = List.unmodifiable(files ?? voicePackDeviceFiles) {
    dir.createSync(recursive: true);
    // Anything else here is a download cut short or a file from an older pack.
    final names = {for (final f in this.files) f.name};
    for (final f in dir.listSync().whereType<File>()) {
      if (!names.contains(f.uri.pathSegments.last)) f.deleteSync();
    }
  }

  String path(String name) => '${dir.path}/$name';

  /// Present at its pinned size. The hash was checked when the file arrived.
  bool has(VoicePackFile f) {
    final file = File(path(f.name));
    return file.existsSync() && file.lengthSync() == f.bytes;
  }

  bool get installed => files.every(has);

  List<VoicePackFile> get missing => [
    for (final f in files)
      if (!has(f)) f,
  ];

  Future<void> download() async {
    if (progress != null) return;
    final todo = missing;
    final total = todo.fold(0, (sum, f) => sum + f.bytes);
    var done = 0;
    var shownStep = 0;
    progress = 0;
    onChange();
    try {
      for (final f in todo) {
        final part = File('${path(f.name)}.part');
        try {
          await downloadPinned(
            Uri.parse('$voicePackReleaseUrl/${f.name}'),
            part,
            sha256: f.sha256,
            maxBytes: f.bytes,
            timeout: voiceDownloadTimeout,
            onProgress: (x) {
              progress = (done + x * f.bytes) / total;
              final step = (progress! * _progressSteps).floor();
              if (step == shownStep) return;
              shownStep = step;
              onChange();
            },
          );
          part.renameSync(path(f.name));
        } finally {
          if (part.existsSync()) part.deleteSync();
        }
        done += f.bytes;
      }
    } finally {
      progress = null;
      onChange();
    }
  }

  /// Installs voice pack files the user picked. Each is copied in, then must match a pinned
  /// file's size and SHA-256, so a file from anywhere is as trusted as a download. Returns the
  /// names installed; files that are not part of the pack are ignored.
  Future<List<String>> installFromFiles(List<String> paths) async {
    final installed = <String>[];
    try {
      for (final p in paths) {
        final size = File(p).lengthSync();
        if (!files.any((f) => f.bytes == size)) continue;
        final part = File(path('incoming-${installed.length}.part'));
        try {
          // Hash the copy, not the original, so what is checked is exactly what is kept.
          await File(p).copy(part.path);
          final hash = await _hashOffIsolate(part.path);
          final match = files.where((f) => f.sha256 == hash).firstOrNull;
          if (match == null || match.bytes != size) continue;
          part.renameSync(path(match.name));
          installed.add(match.name);
        } finally {
          if (part.existsSync()) part.deleteSync();
        }
      }
    } finally {
      onChange();
    }
    return installed;
  }

  void delete() {
    for (final f in dir.listSync().whereType<File>()) {
      f.deleteSync();
    }
    onChange();
  }
}

/// Top level, so the isolate closure captures only [path] and never the shelf's callbacks.
Future<String> _hashOffIsolate(String path) => Isolate.run(() => _sha256Of(path));

Future<String> _sha256Of(String path) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in File(path).openRead()) {
    sink.add(chunk);
  }
  sink.close();
  return hexOf((await sink.hash()).bytes);
}

/// Synthesised audio and when each word is spoken in it.
class Speech {
  final Float32List samples;
  final List<WordTiming> words;
  final Duration synthesis;
  const Speech(this.samples, this.words, this.synthesis);

  Duration get duration =>
      Duration(microseconds: samples.length * Duration.microsecondsPerSecond ~/ kokoroSampleRate);

  /// Seconds of compute per second of audio; below 1 is faster than real time.
  double get realTimeFactor =>
      duration == Duration.zero ? 0 : synthesis.inMicroseconds / duration.inMicroseconds;
}

/// Kokoro loaded through ONNX Runtime with its lexicon and voices. Load it for a job and close
/// it after: it holds a few hundred MB that a phone also needs for the language model.
class KokoroVoice {
  final OrtSession _session;
  final Phonemizer _phonemizer;
  final Map<String, Float32List> _styles;
  KokoroVoice._(this._session, this._phonemizer, this._styles);

  static Future<KokoroVoice> load(VoiceShelf shelf) async {
    if (!shelf.installed) throw StateError('The voice pack is not installed.');
    final lexiconPath = shelf.path(cmudictFile);
    // Parsing 135,000 dictionary lines stays off the UI isolate.
    final lexicon = await Isolate.run(
      () => Lexicon.parseCmudict(File(lexiconPath).readAsStringSync()),
    );
    final styles = {for (final s in kokoroSpeakers) s.id: _readVoice(shelf.path(s.fileName))};
    final session = await OnnxRuntime().createSession(shelf.path(kokoroModelFile));
    if (!session.outputNames.contains(_durations)) {
      await session.close();
      throw const FormatException('This voice model does not report word durations.');
    }
    return KokoroVoice._(session, Phonemizer(lexicon), styles);
  }

  static Float32List _readVoice(String path) {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length % (kokoroStyleDim * _bytesPerFloat) != 0) {
      throw FormatException('$path is not a Kokoro voice file.');
    }
    return bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.length ~/ _bytesPerFloat);
  }

  /// Speaks [text] in [speaker]'s voice, one model run per chunk that fits the context.
  Future<Speech> speak(String text, KokoroSpeaker speaker) async {
    final style = _styles[speaker.id];
    if (style == null) throw ArgumentError('Unknown voice ${speaker.id}');
    final clock = Stopwatch()..start();
    final audio = BytesBuilder(copy: false);
    final words = <WordTiming>[];
    var offset = 0;
    for (final u in _phonemizer.utterances(text)) {
      final (wave, durations) = await _run(u, style);
      words.addAll(wordTimings(u, durations, offsetSamples: offset, totalSamples: wave.length));
      audio.add(wave.buffer.asUint8List(wave.offsetInBytes, wave.lengthInBytes));
      offset += wave.length;
    }
    final bytes = audio.takeBytes();
    return Speech(
      bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.length ~/ _bytesPerFloat),
      words,
      clock.elapsed,
    );
  }

  Future<(Float32List, List<double>)> _run(Utterance u, Float32List voice) async {
    final ids = u.inputIds;
    final inputs = {
      'input_ids': await OrtValue.fromList(ids, [1, ids.length]),
      'style': await OrtValue.fromList(Float32List.fromList(styleFor(voice, u.phonemes.length)), [
        1,
        kokoroStyleDim,
      ]),
      'speed': await OrtValue.fromList(Float32List.fromList([1]), [1]),
    };
    Map<String, OrtValue> outputs = const {};
    try {
      outputs = await _session.run(inputs);
      final wave = await outputs[_waveform]!.asFlattenedList();
      final durations = await outputs[_durations]!.asFlattenedList();
      return (
        wave is Float32List ? wave : Float32List.fromList(wave.cast<double>()),
        durations.cast<double>().toList(),
      );
    } finally {
      for (final v in [...inputs.values, ...outputs.values]) {
        await v.dispose();
      }
    }
  }

  Future<void> close() => _session.close();
}

const _waveform = 'waveform';
const _durations = 'durations';
