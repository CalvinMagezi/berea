import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'edge_engine.dart' show modelDownloadTimeout;
import 'pinned_download.dart';

/// Supertonic 3 in sherpa-onnx's int8 build (2026-05-11), re-hosted unchanged on Berea's data
/// release so each file can be fetched, resumed and checked on its own.
const _voiceRelease = 'https://github.com/CalvinMagezi/berea/releases/download/voice-supertonic3-1';

/// The voice's files, each pinned to the size and hash measured on the A32 bake-off copy.
const voiceFiles = {
  'duration_predictor.int8.onnx': (
    sha256: 'c3eb91414d5ff8a7a239b7fe9e34e7e2bf8a8140d8375ffb14718b1c639325db',
    bytes: 3700147,
  ),
  'text_encoder.int8.onnx': (
    sha256: 'c7befd5ea8c3119769e8a6c1486c4edc6a3bc8365c67621c881bbb774b9902ff',
    bytes: 36416150,
  ),
  'vector_estimator.int8.onnx': (
    sha256: '20cd86fa5c6effedfda0e7cffe5b0569ca401c440a0c3a1d72bf39286c0db3fd',
    bytes: 78400833,
  ),
  'vocoder.int8.onnx': (
    sha256: 'e923d60f53f95eb1ce235f1dc33ec56d9c057823c96fa6f8acf98f32b0da6152',
    bytes: 25991073,
  ),
  'tts.json': (
    sha256: '42078d3aef1cd43ab43021f3c54f47d2d75ceb4e75f627f118890128b06a0d09',
    bytes: 8253,
  ),
  'unicode_indexer.bin': (
    sha256: '8402ca48e5189a8950138580b0fff64db6f072f24ac07cd54ba8b2fbb9883b30',
    bytes: 262144,
  ),
  'voice.bin': (
    sha256: '67d5209b0ee8ce6c74105ffbe12fe6a7628aea3b4ba2fcb308a4a67938a93ce8',
    bytes: 517168,
  ),
};

int get voiceBytes => voiceFiles.values.fold(0, (n, f) => n + f.bytes);

/// Flow steps per sentence: 5 read every name right in the A32 bake-off, 3 slurred a few.
const voiceSteps = 5;

/// Four threads measured fastest on the A32's eight cores; more fought the UI for the big cores.
const voiceThreads = 4;

/// Quiet between paragraphs, and longer between beats, so the narration breathes.
const paragraphPause = Duration(milliseconds: 600);
const beatPause = Duration(milliseconds: 1200);

const _pcmMax = 32767;
const _wavHeaderBytes = 44;
const _bytesPerSample = 2;
const _microsPerSecond = 1000000;

/// Whether every voice file is in [dir] with the size and hash it was pinned to.
bool voiceInstalled(Directory dir) => voiceFiles.entries.every(
  (f) => hostedModelCurrent(
    File('${dir.path}/${f.key}'),
    sha256: f.value.sha256,
    bytes: f.value.bytes,
  ),
);

/// Fetches the voice into [dir] file by file; a stopped download continues where it left off.
Future<void> downloadVoice(
  Directory dir, {
  required void Function(int received, int total) onProgress,
  Future<void>? stop,
}) async {
  var before = 0;
  for (final MapEntry(key: name, value: pin) in voiceFiles.entries) {
    final start = before;
    await downloadModelFile(
      Uri.parse('$_voiceRelease/$name'),
      dir,
      name,
      sha256: pin.sha256,
      bytes: pin.bytes,
      timeout: modelDownloadTimeout,
      onProgress: (received, _) => onProgress(start + received, voiceBytes),
      stop: stop,
    );
    before += pin.bytes;
    onProgress(before, voiceBytes);
  }
}

/// Speaks each beat's paragraphs into `beat-N.wav` in [out], skipping beats already there, so a
/// render that was stopped picks up at its first unspoken beat. [onProgress] hears paragraphs
/// spoken of all paragraphs.
typedef SpeakBeats = Future<void> Function({
  required Directory voice,
  required List<List<String>> beats,
  required Directory out,
  required void Function(int done, int total) onProgress,
  Future<void>? stop,
});

/// The beat file [i] of a render in [dir].
File beatAudio(Directory dir, int i) => File('${dir.path}/beat-$i.wav');

/// [SpeakBeats] with Supertonic in its own isolate: each sentence blocks for seconds in native
/// code, which would freeze the app on the UI isolate.
Future<void> speakWithSupertonic({
  required Directory voice,
  required List<List<String>> beats,
  required Directory out,
  required void Function(int done, int total) onProgress,
  Future<void>? stop,
}) async {
  final total = beats.fold(0, (n, b) => n + b.length);
  final todo = [
    for (var i = 0; i < beats.length; i++)
      if (!beatAudio(out, i).existsSync()) i,
  ];
  var done = [
    for (var i = 0; i < beats.length; i++)
      if (!todo.contains(i)) beats[i].length,
  ].fold(0, (n, b) => n + b);
  onProgress(done, total);
  if (todo.isEmpty) return;
  // Exit arrives as null and an uncaught error as a list, on the same port as the progress.
  final events = ReceivePort();
  await Isolate.spawn(
    _speakIsolate,
    _SpeakJob(voice.path, out.path, {for (final i in todo) i: beats[i]}, events.sendPort),
    onExit: events.sendPort,
    onError: events.sendPort,
  );
  SendPort? control;
  var stopped = false;
  unawaited(
    stop?.then((_) {
      stopped = true;
      control?.send(true);
    }),
  );
  // An error is held until the isolate has exited, so the voice is freed before the helper
  // loads again.
  Object? failure;
  try {
    await for (final e in events) {
      switch (e) {
        case SendPort p:
          control = p;
          if (stopped) p.send(true);
        case int _:
          onProgress(++done, total);
        case String message:
          failure = message;
        case List error:
          failure = error.first;
        case null:
          if (failure != null) throw StateError('$failure');
          return;
      }
    }
  } finally {
    events.close();
  }
}

class _SpeakJob {
  final String voice;
  final String out;
  final Map<int, List<String>> beats;
  final SendPort events;
  const _SpeakJob(this.voice, this.out, this.beats, this.events);
}

/// Loads the voice once, speaks beat after beat, and reads the stop flag between paragraphs:
/// native generation cannot be interrupted, so a stop waits for the paragraph in hand.
Future<void> _speakIsolate(_SpeakJob job) async {
  final control = ReceivePort();
  var stopped = false;
  control.listen((_) => stopped = true);
  job.events.send(control.sendPort);
  so.OfflineTts? tts;
  try {
    so.initBindings();
    tts = so.OfflineTts(_config(job.voice));
    for (final MapEntry(key: i, value: paragraphs) in job.beats.entries) {
      final part = File('${job.out}/beat-$i.wav.part');
      final sink = WavSink(part, tts.sampleRate);
      for (final p in paragraphs) {
        await Future<void>.delayed(Duration.zero);
        if (stopped) break;
        final audio = tts.generateWithConfig(
          text: p,
          config: const so.OfflineTtsGenerationConfig(numSteps: voiceSteps),
        );
        sink
          ..add(audio.samples)
          ..silence(paragraphPause);
        job.events.send(0);
      }
      await sink.close();
      if (stopped) {
        part.deleteSync();
        break;
      }
      part.renameSync('${job.out}/beat-$i.wav');
    }
  } catch (e) {
    job.events.send('$e');
  } finally {
    tts?.free();
    control.close();
  }
}

so.OfflineTtsConfig _config(String d) => so.OfflineTtsConfig(
  model: so.OfflineTtsModelConfig(
    supertonic: so.OfflineTtsSupertonicModelConfig(
      durationPredictor: '$d/duration_predictor.int8.onnx',
      textEncoder: '$d/text_encoder.int8.onnx',
      vectorEstimator: '$d/vector_estimator.int8.onnx',
      vocoder: '$d/vocoder.int8.onnx',
      ttsJson: '$d/tts.json',
      unicodeIndexer: '$d/unicode_indexer.bin',
      voiceStyle: '$d/voice.bin',
    ),
    numThreads: voiceThreads,
  ),
);

/// 16-bit mono WAV written as it is spoken; the sizes in the header are filled in at [close].
class WavSink {
  final File file;
  final int sampleRate;
  final RandomAccessFile _raf;
  var _dataBytes = 0;

  WavSink(this.file, this.sampleRate) : _raf = file.openSync(mode: FileMode.write) {
    _raf.writeFromSync(wavHeader(sampleRate, 0));
  }

  void add(Float32List samples) {
    final pcm = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      pcm[i] = (samples[i].clamp(-1.0, 1.0) * _pcmMax).round();
    }
    _raf.writeFromSync(pcm.buffer.asUint8List());
    _dataBytes += pcm.lengthInBytes;
  }

  void silence(Duration d) {
    final n = sampleRate * d.inMicroseconds ~/ _microsPerSecond;
    _raf.writeFromSync(Uint8List(n * _bytesPerSample));
    _dataBytes += n * _bytesPerSample;
  }

  /// Appends the samples of [wav], a file this class wrote, after its header.
  void addFile(File wav) {
    final bytes = wav.readAsBytesSync();
    _raf.writeFromSync(bytes, _wavHeaderBytes);
    _dataBytes += bytes.length - _wavHeaderBytes;
  }

  Future<void> close() async {
    _raf
      ..setPositionSync(0)
      ..writeFromSync(wavHeader(sampleRate, _dataBytes));
    await _raf.close();
  }
}

/// A canonical 44-byte header for 16-bit mono PCM holding [dataBytes] of samples.
Uint8List wavHeader(int sampleRate, int dataBytes) {
  final h = ByteData(_wavHeaderBytes);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, _wavHeaderBytes - 8 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * _bytesPerSample, Endian.little)
    ..setUint16(32, _bytesPerSample, Endian.little)
    ..setUint16(34, _bytesPerSample * 8, Endian.little);
  tag(36, 'data');
  h.setUint32(40, dataBytes, Endian.little);
  return h.buffer.asUint8List();
}

/// The sample rate in a header [wavHeader] wrote.
int wavRate(File wav) {
  final raf = wav.openSync();
  try {
    return ByteData.sublistView(raf.readSync(_wavHeaderBytes)).getUint32(24, Endian.little);
  } finally {
    raf.closeSync();
  }
}

/// Joins the beat files of [dir] into [into] with a pause between beats, and returns its length.
Future<Duration> joinBeats(Directory dir, int count, File into) async {
  final rate = wavRate(beatAudio(dir, 0));
  final sink = WavSink(File('${into.path}.part'), rate);
  for (var i = 0; i < count; i++) {
    if (i > 0) sink.silence(beatPause);
    sink.addFile(beatAudio(dir, i));
  }
  final bytes = sink._dataBytes;
  await sink.close();
  await sink.file.rename(into.path);
  return Duration(microseconds: bytes ~/ _bytesPerSample * _microsPerSecond ~/ rate);
}

/// [joinBeats] on another isolate, so tens of megabytes of copying never stall a frame. Top level,
/// so the closure carries only these three values across.
Future<Duration> joinBeatsAway(String dir, int count, String into) =>
    Isolate.run(() => joinBeats(Directory(dir), count, File(into)));
