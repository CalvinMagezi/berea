import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea/app_state.dart';
import 'package:berea/chat_screen.dart';
import 'package:berea/edge_engine.dart';
import 'package:berea/models.dart';
import 'package:berea/voice.dart';
import 'package:berea/voice_composer.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:sqlite3/sqlite3.dart';

/// A WAV file, optionally with an extra chunk first as Core Audio writes them.
Uint8List wav({
  int rate = voiceSampleRate,
  int channels = voiceChannels,
  int bits = voiceBitsPerSample,
  int pcmBytes = voiceBytesPerSecond,
  bool extraChunk = false,
  bool extensible = false,
  bool withData = true,
  int? riffSize,
  int? dataSize,
}) {
  final b = BytesBuilder();
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  if (extraChunk) {
    b.add('FLLR'.codeUnits);
    u32(3);
    b.add([0, 0, 0, 0]);
  }
  b.add('fmt '.codeUnits);
  u32(extensible ? 40 : 16);
  u16(extensible ? 0xFFFE : 1);
  u16(channels);
  u32(rate);
  u32(rate * channels * bits ~/ 8);
  u16(channels * bits ~/ 8);
  u16(bits);
  if (extensible) {
    u16(22);
    u16(bits);
    u32(4);
    u16(1);
    b.add(Uint8List(14));
  }
  if (withData) {
    b.add('data'.codeUnits);
    u32(dataSize ?? pcmBytes);
    b.add(Uint8List(pcmBytes));
  }
  final body = b.toBytes();
  final out = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add((ByteData(4)..setUint32(0, riffSize ?? body.length + 4, Endian.little)).buffer.asUint8List())
    ..add('WAVE'.codeUnits)
    ..add(body);
  return out.toBytes();
}

class FakeRecorder implements AudioRecorder {
  bool permission = true;
  Completer<bool>? permissionGate;
  Object? permissionError;
  Object? startError;
  Uint8List bytes = wav();
  RecordConfig? config;
  String? path;
  int starts = 0;
  int cancels = 0;
  bool disposed = false;

  @override
  Future<bool> hasPermission({bool request = true}) async {
    if (permissionError != null) throw permissionError!;
    return permissionGate?.future ?? permission;
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    starts++;
    this.config = config;
    this.path = path;
    File(path).writeAsBytesSync(bytes);
    if (startError != null) throw startError!;
  }

  @override
  Future<String?> stop() async => path;

  @override
  Future<void> cancel() async {
    cancels++;
    final f = File(path!);
    if (f.existsSync()) f.deleteSync();
  }

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ThrowingModel implements InferenceModel {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('model closed');
}

/// Late deletes leave a timer behind; let it fire before the test ends.
void voiceWidgets(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pump(voiceLateWriteGrace);
    });

void main() {
  late Directory dir;
  late FakeRecorder recorder;
  late List<Uint8List> heard;
  late String reply;
  const owner = 'composer';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('berea-voice-test');
    recorder = FakeRecorder();
    heard = [];
    reply = '  What does John 3:16 mean?  ';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  VoiceInput make({
    Duration min = Duration.zero,
    Future<String> Function(Uint8List)? transcribe,
    Future<Directory> Function()? cacheDir,
  }) => VoiceInput(
    transcribe:
        transcribe ??
        (w) async {
          heard.add(w);
          return reply;
        },
    recorder: recorder,
    cacheDir: cacheDir ?? () async => dir,
    newStopwatch: () => clock.stopwatch(),
    minDuration: min,
  );

  bool recordingLeft() => dir.listSync(recursive: true).whereType<File>().isNotEmpty;

  group('WAV checks', () {
    WavProblem? check(Uint8List w) => wavProblem(w, maxDuration: maxVoiceDuration);

    test('accepts 16 kHz mono 16-bit PCM, plain, with extra chunks or extensible', () {
      expect(check(wav()), isNull);
      expect(check(wav(extraChunk: true)), isNull);
      expect(check(wav(extensible: true)), isNull);
    });
    test('names what is wrong', () {
      expect(check(wav(rate: 44100)), WavProblem.wrongRate);
      expect(wavSampleRate(wav(rate: 44100)), 44100);
      expect(check(wav(channels: 2)), WavProblem.wrongChannels);
      expect(check(wav(bits: 8)), WavProblem.wrongBits);
      expect(check(Uint8List.fromList('hello world!'.codeUnits)), WavProblem.notWav);
      expect(check(wav(withData: false)), WavProblem.noData);
      expect(check(wav(pcmBytes: 0)), WavProblem.tooShort, reason: 'a header-only file');
      expect(check(wav(riffSize: 7)), WavProblem.sizeMismatch);
      expect(check(wav(dataSize: voiceBytesPerSecond * 2)), WavProblem.sizeMismatch);
      expect(
        check(wav(pcmBytes: voiceBytesPerSecond * 40)),
        WavProblem.tooLong,
      );
    });
    test('a header-only 44-byte file is rejected', () {
      final header = wav(pcmBytes: 0);
      expect(header.length, 44);
      expect(check(header), WavProblem.tooShort);
    });
    test('sizes left unset by a streaming writer are repaired', () {
      final unset = wav(riffSize: 0, dataSize: 0xFFFFFFFF);
      expect(wavSizesConsistent(unset), isFalse);
      final fixed = repairWavSizes(unset);
      expect(wavSizesConsistent(fixed), isTrue);
      expect(check(fixed), isNull);
      expect(repairWavSizes(wav()), wav(), reason: 'a finished file is left alone');
    });
  });

  group('cleanTranscript', () {
    test('keeps the words and their punctuation as spoken', () {
      expect(cleanTranscript('  Tell me about grace.  '), 'Tell me about grace.');
      expect(cleanTranscript('Who were the Bereans?'), 'Who were the Bereans?');
    });
    test('drops labels and wrapping quotes', () {
      expect(cleanTranscript('Transcript: "Who wrote Romans?"'), 'Who wrote Romans?');
      expect(cleanTranscript('\u201cPray for me.\u201d'), 'Pray for me.');
    });
    test('no speech or filler alone is nothing heard', () {
      for (final empty in ['', '  ', '...', '[silence]', '(no speech)', 'Um.', '*inaudible*']) {
        expect(cleanTranscript(empty), isEmpty, reason: empty);
      }
    });
  });

  group('voiceSupport', () {
    test('needs the on-device engine with Gemma 4', () {
      final ollama = Settings(engine: EngineKind.ollama, deviceModelId: 'gemma-4-e2b');
      final small = Settings(engine: EngineKind.device, deviceModelId: 'gemma-3-1b');
      for (final s in [ollama, small]) {
        expect(
          voiceSupport(s, DeviceModelState.ready, hearsAudio: true),
          VoiceSupport.needsGemma4,
        );
      }
    });
    test('waits for Gemma 4 to load, and needs its audio encoder', () {
      for (final id in ['gemma-4-e2b', 'gemma-4-e4b']) {
        final s = Settings(engine: EngineKind.device, deviceModelId: id);
        expect(voiceSupport(s, DeviceModelState.ready, hearsAudio: true), VoiceSupport.ready);
        expect(
          voiceSupport(s, DeviceModelState.ready, hearsAudio: false),
          VoiceSupport.unavailable,
        );
        expect(
          voiceSupport(s, DeviceModelState.loading, hearsAudio: false),
          VoiceSupport.notReady,
        );
      }
    });
  });

  group('VoiceInput', () {
    test('the cap is 30 seconds', () => expect(maxVoiceDuration, const Duration(seconds: 30)));

    test('records 16 kHz mono WAV, transcribes it, then waits for the user', () {
      fakeAsync((a) {
        final v = make();
        v.start(owner);
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.recording);
        expect(recorder.config!.encoder, AudioEncoder.wav);
        expect(recorder.config!.sampleRate, voiceSampleRate);
        expect(recorder.config!.numChannels, voiceChannels);
        a.elapse(const Duration(seconds: 2));
        expect(v.elapsed, const Duration(seconds: 2));
        v.stop();
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.confirm);
        expect(v.transcript, 'What does John 3:16 mean?');
        expect(heard.single, recorder.bytes);
        expect(recordingLeft(), isFalse);
        v.accept();
        expect(v.phase, VoicePhase.idle);
      });
    });

    test('stops itself at the cap', () {
      fakeAsync((a) {
        final v = make();
        v.start(owner);
        a.elapse(maxVoiceDuration + const Duration(seconds: 5));
        expect(v.phase, VoicePhase.confirm);
        expect(heard, hasLength(1));
        expect(v.elapsed, maxVoiceDuration);
        expect(recordingLeft(), isFalse);
      });
    });

    test('a slip shorter than the minimum is discarded', () {
      fakeAsync((a) {
        final v = make(min: minVoiceDuration);
        v.start(owner);
        a.elapse(const Duration(milliseconds: 200));
        v.stop();
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(v.message, tooShortMessage);
        expect(heard, isEmpty);
        expect(recordingLeft(), isFalse);
      });
    });

    test('denied microphone explains and records nothing', () {
      fakeAsync((a) {
        recorder.permission = false;
        final v = make();
        v.start(owner);
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(v.message, micDeniedMessage);
        expect(recorder.starts, 0);
      });
    });

    test('a failure anywhere in starting surfaces a message and leaves no file', () {
      for (final setUpFailure in <void Function()>[
        () => recorder.permissionError = StateError('no audio session'),
        () => recorder.startError = StateError('device busy'),
      ]) {
        recorder = FakeRecorder();
        setUpFailure();
        fakeAsync((a) {
          final v = make();
          v.start(owner);
          a.flushMicrotasks();
          expect(v.phase, VoicePhase.idle);
          expect(v.message, micUnavailableMessage);
          expect(recordingLeft(), isFalse);
        });
      }
      fakeAsync((a) {
        final v = make(cacheDir: () async => throw const FileSystemException('no cache'));
        v.start(owner);
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(v.message, voiceFailedMessage);
      });
    });

    test('failed, empty and slow transcriptions return to idle with no file left', () {
      fakeAsync((a) {
        final failing = make(transcribe: (_) async => throw StateError('model closed'));
        failing.start(owner);
        a.elapse(const Duration(seconds: 1));
        failing.stop();
        a.flushMicrotasks();
        expect(failing.phase, VoicePhase.idle);
        expect(failing.message, voiceFailedMessage);

        reply = '   ';
        final empty = make();
        empty.start(owner);
        a.elapse(const Duration(seconds: 1));
        empty.stop();
        a.flushMicrotasks();
        expect(empty.message, nothingHeardMessage);

        final slow = make(transcribe: (_) => Completer<String>().future);
        slow.start(owner);
        a.elapse(const Duration(seconds: 1));
        slow.stop();
        a.elapse(voiceTranscribeTimeout + const Duration(seconds: 1));
        expect(slow.phase, VoicePhase.idle);
        expect(slow.message, voiceTimeoutMessage);
        expect(recordingLeft(), isFalse);
      });
    });

    test('audio in the wrong format is never sent to the model', () {
      fakeAsync((a) {
        recorder.bytes = wav(channels: 2);
        final v = make();
        v.start(owner);
        a.elapse(const Duration(seconds: 1));
        v.stop();
        a.flushMicrotasks();
        expect(v.message, voiceFailedMessage);
        expect(heard, isEmpty);
        expect(recordingLeft(), isFalse);
      });
    });

    test('cancel throws a recording away', () {
      fakeAsync((a) {
        final v = make();
        v.start(owner);
        a.elapse(const Duration(seconds: 1));
        v.cancel();
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(recorder.cancels, 1);
        expect(heard, isEmpty);
        expect(recordingLeft(), isFalse);
      });
    });

    test('cancel during transcription drops the late result', () {
      fakeAsync((a) {
        final pending = Completer<String>();
        final v = make(transcribe: (_) => pending.future);
        v.start(owner);
        a.elapse(const Duration(seconds: 1));
        v.stop();
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.transcribing);
        expect(recordingLeft(), isFalse, reason: 'only memory holds the audio now');
        v.cancel();
        expect(v.phase, VoicePhase.idle);
        pending.complete('too late');
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(v.transcript, isEmpty);
      });
    });

    test('a release while starting is a slip, never a zero-length question', () {
      fakeAsync((a) {
        recorder.permissionGate = Completer();
        final v = make();
        v.start(owner);
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.starting);
        v.stop();
        recorder.permissionGate!.complete(true);
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(v.message, tooShortMessage);
        expect(heard, isEmpty);
        expect(recordingLeft(), isFalse);
      });
    });

    test('a cancel while starting never records', () {
      fakeAsync((a) {
        recorder.permissionGate = Completer();
        final v = make();
        v.start(owner);
        a.flushMicrotasks();
        v.cancel();
        recorder.permissionGate!.complete(true);
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(v.message, isNull);
        expect(heard, isEmpty);
        expect(recordingLeft(), isFalse);
      });
    });

    test('dispose in any phase leaves the folder empty and closes the recorder', () {
      for (final phase in [VoicePhase.starting, VoicePhase.recording, VoicePhase.transcribing]) {
        recorder = FakeRecorder();
        fakeAsync((a) {
          final pending = Completer<String>();
          if (phase == VoicePhase.starting) recorder.permissionGate = Completer();
          final v = make(transcribe: (_) => pending.future);
          v.start(owner);
          a.elapse(const Duration(seconds: 1));
          if (phase == VoicePhase.transcribing) {
            v.stop();
            a.flushMicrotasks();
          }
          expect(v.phase, phase);
          v.dispose();
          recorder.permissionGate?.complete(true);
          pending.complete('late');
          a.flushMicrotasks();
          expect(recordingLeft(), isFalse, reason: '$phase');
          expect(recorder.disposed, isTrue, reason: '$phase');
        });
      }
    });

    test('one session at a time, owned by the composer that started it', () {
      fakeAsync((a) {
        final v = make();
        v.start('tab');
        a.flushMicrotasks();
        v.start('sheet');
        a.flushMicrotasks();
        expect(v.ownedBy('tab'), isTrue);
        expect(recorder.starts, 1);
        v.release('sheet');
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.recording);
        v.release('tab');
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(recordingLeft(), isFalse);
      });
    });

    test('leaving the app stops listening', () {
      fakeAsync((a) {
        final v = make();
        v.start(owner);
        a.elapse(const Duration(seconds: 1));
        v.onLifecycle(AppLifecycleState.resumed);
        expect(v.phase, VoicePhase.recording);
        v.onLifecycle(AppLifecycleState.inactive);
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(heard, isEmpty);
        expect(recordingLeft(), isFalse);
      });
    });

    test("an earlier run's folders are swept once, links and other files left alone", () {
      fakeAsync((a) {
        final old = Directory('${dir.path}/${voiceDirPrefix}old')..createSync();
        File('${old.path}/1.wav').writeAsBytesSync(wav());
        final elsewhere = Directory.systemTemp.createTempSync('berea-voice-elsewhere');
        final kept = File('${elsewhere.path}/keep.wav')..writeAsBytesSync(wav());
        Link('${dir.path}/${voiceDirPrefix}link').createSync(elsewhere.path);
        final other = File('${dir.path}/notes.txt')..writeAsStringSync('mine');
        final first = make();
        first.start(owner);
        a.flushMicrotasks();
        expect(old.existsSync(), isFalse);
        expect(kept.existsSync(), isTrue);
        expect(other.existsSync(), isTrue);

        make();
        a.flushMicrotasks();
        expect(first.phase, VoicePhase.recording);
        expect(File(recorder.path!).existsSync(), isTrue, reason: 'a second session sweeps nothing');
        first.cancel();
        a.flushMicrotasks();
        elsewhere.deleteSync(recursive: true);
      });
    });

    test('recordings go in a folder only this user can open', () {
      fakeAsync((a) {
        make().start(owner);
        a.flushMicrotasks();
        final folder = File(recorder.path!).parent;
        expect(folder.parent.path, dir.path);
        expect(folder.path.split('/').last, startsWith(voiceDirPrefix));
        if (!Platform.isWindows) expect(folder.statSync().modeString(), 'rwx------');
      });
    });

    test('waits for the recorder to finish the file, then repairs unset sizes', () {
      fakeAsync((a) {
        recorder.bytes = wav(riffSize: 0, dataSize: 0);
        final v = make();
        v.start(owner);
        a.elapse(const Duration(seconds: 1));
        v.stop();
        a.elapse(voiceFinalizePoll * 2);
        expect(v.phase, VoicePhase.transcribing, reason: 'still waiting for a finished header');
        a.elapse(voiceFinalizeLimit);
        expect(v.phase, VoicePhase.confirm);
        expect(wavSizesConsistent(heard.single), isTrue);
      });
    });

    test('a file a late writer recreates is deleted again', () {
      fakeAsync((a) {
        final v = make();
        v.start(owner);
        a.elapse(const Duration(seconds: 1));
        final path = recorder.path!;
        v.cancel();
        a.flushMicrotasks();
        File(path).writeAsBytesSync(wav());
        a.elapse(voiceLateWriteGrace);
        expect(File(path).existsSync(), isFalse);
      });
    });

    test('a microphone at the wrong rate says so', () {
      fakeAsync((a) {
        recorder.bytes = wav(rate: 48000);
        final v = make();
        v.start(owner);
        a.elapse(const Duration(seconds: 1));
        v.stop();
        a.flushMicrotasks();
        expect(v.message, wrongRateMessage(48000));
        expect(heard, isEmpty);
      });
    });

    test('a transcript of no speech is nothing heard', () {
      fakeAsync((a) {
        reply = 'Transcript: [silence]';
        final v = make();
        v.start(owner);
        a.elapse(const Duration(seconds: 1));
        v.stop();
        a.flushMicrotasks();
        expect(v.phase, VoicePhase.idle);
        expect(v.message, nothingHeardMessage);
      });
    });
  });

  group('AppState', () {
    test('a failed transcription releases the model', () async {
      final s = AppState()
        ..debugEdge = EdgeAiEngine(ThrowingModel(), edgeModelById('gemma-4-e2b'), hearsAudio: true);
      await expectLater(s.transcribeVoice(wav()), throwsStateError);
      expect(s.busy, isFalse);
    });

    test('a model loaded without audio is never asked to transcribe', () async {
      final s = AppState()..debugEdge = EdgeAiEngine(ThrowingModel(), edgeModelById('gemma-4-e2b'));
      await expectLater(s.transcribeVoice(wav()), throwsStateError);
      expect(s.busy, isFalse);
    });

    test('only one piece of work uses the model at a time', () async {
      final s = AppState();
      final gate = Completer<void>();
      final first = s.useModel(() => gate.future);
      expect(s.busy, isTrue);
      await expectLater(s.useModel(() async {}), throwsStateError);
      gate.complete();
      await first;
      expect(s.busy, isFalse);
    });
  });

  group('composer', () {
    Future<void> pumpComposer(
      WidgetTester tester,
      VoiceInput voice, {
      VoiceSupport support = VoiceSupport.ready,
      Object me = owner,
      VoidCallback? onOpenSettings,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: voice,
            builder: (_, _) => Column(
              children: [
                VoiceStatusLine(voice, owner: me),
                VoiceMicButton(
                  voice: voice,
                  owner: me,
                  support: support,
                  modelFree: !voice.inUse,
                  onOpenSettings: onOpenSettings ?? () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final mic = find.byIcon(Icons.mic_none);
    final stopIcon = find.byIcon(Icons.stop_circle_outlined);

    voiceWidgets('tap to start, tap to stop: recording, transcribing, confirm', (tester) async {
      final pending = Completer<String>();
      final v = make(transcribe: (_) => pending.future);
      await pumpComposer(tester, v);
      await tester.tap(mic);
      await tester.pump(const Duration(seconds: 2));
      expect(v.phase, VoicePhase.recording);
      expect(find.text('Listening. $tapAgainHint'), findsOneWidget);
      expect(find.text('0:02 of 0:30'), findsOneWidget);

      await tester.tap(stopIcon);
      await tester.pump();
      expect(v.phase, VoicePhase.transcribing);
      expect(find.text('Transcribing on this device…'), findsOneWidget);

      pending.complete('Who were the Bereans?');
      await tester.pump();
      expect(v.phase, VoicePhase.confirm);
      expect(find.text('Check the words, edit them if needed, then send.'), findsOneWidget);
    });

    voiceWidgets('recording starts on press and stops on release', (tester) async {
      final v = make();
      await pumpComposer(tester, v);
      final hold = await tester.startGesture(tester.getCenter(mic));
      await tester.pump();
      expect(v.phase, VoicePhase.recording);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining(releaseHint), findsOneWidget);
      await hold.up();
      await tester.pump();
      expect(v.phase, VoicePhase.confirm);
      expect(heard, hasLength(1));
    });

    voiceWidgets('a pointer cancel or a slide away throws the recording away', (tester) async {
      final v = make();
      await pumpComposer(tester, v);
      final taken = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(seconds: 1));
      await taken.cancel();
      await tester.pump();
      expect(v.phase, VoicePhase.idle);

      final slid = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(seconds: 1));
      await slid.moveBy(const Offset(0, -(slideToCancelDistance + 20)));
      await tester.pump();
      await slid.up();
      await tester.pump();
      expect(v.phase, VoicePhase.idle);
      expect(heard, isEmpty);
      expect(recorder.cancels, 2);
      expect(recordingLeft(), isFalse);
    });

    voiceWidgets('a screen reader tap toggles recording', (tester) async {
      final semantics = tester.ensureSemantics();
      final v = make();
      await pumpComposer(tester, v);
      tester.semantics.tap(find.semantics.byLabel(holdHint));
      await tester.pump(const Duration(seconds: 1));
      expect(v.phase, VoicePhase.recording);
      tester.semantics.tap(find.semantics.byLabel(stopHint));
      await tester.pump();
      expect(v.phase, VoicePhase.confirm);
      semantics.dispose();
    });

    voiceWidgets("another composer's session leaves this button and status alone", (tester) async {
      final v = make();
      await pumpComposer(tester, v, me: 'sheet');
      unawaited(v.start('tab'));
      await tester.pump(const Duration(seconds: 1));
      expect(v.phase, VoicePhase.recording);
      expect(find.textContaining('Listening'), findsNothing);
      await tester.tap(mic);
      await tester.pump();
      expect(v.phase, VoicePhase.recording);
      expect(v.ownedBy('tab'), isTrue);
      await v.cancel();
      await tester.pump();
    });

    voiceWidgets('without Gemma 4 the button points to Engine settings', (tester) async {
      var opened = false;
      final v = make();
      await pumpComposer(
        tester,
        v,
        support: VoiceSupport.needsGemma4,
        onOpenSettings: () => opened = true,
      );
      await tester.tap(find.byIcon(Icons.mic_off_outlined));
      await tester.pumpAndSettle();
      expect(find.text(needsGemma4Message), findsOneWidget);
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      expect(recorder.starts, 0);
    });

    voiceWidgets('a Gemma 4 load without audio explains that voice is off', (tester) async {
      final v = make();
      await pumpComposer(tester, v, support: VoiceSupport.unavailable);
      await tester.tap(find.byIcon(Icons.mic_off_outlined));
      await tester.pumpAndSettle();
      expect(find.text(audioUnavailableMessage), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
    });

    voiceWidgets('a model that is still loading does not record', (tester) async {
      final v = make();
      await pumpComposer(tester, v, support: VoiceSupport.notReady);
      await tester.tap(mic);
      await tester.pump();
      expect(recorder.starts, 0);
    });
  });

  group('chat screen', () {
    Future<AppState> pumpChat(WidgetTester tester, VoiceInput voice) async {
      final s = AppState()
        ..db = BibleDb(sqlite3.openInMemory())
        ..settings = Settings(engine: EngineKind.device)
        ..voice = voice
        // With no helper at all Study shows the helper choice, which has no composer.
        ..helperState = const HelperLoading()
        ..turns.add(
          ChatTurn('Earlier question')
            ..answer = 'Earlier answer'
            ..done = true,
        );
      await tester.pumpWidget(MaterialApp(home: ChatScreen(state: s)));
      return s;
    }

    voiceWidgets('a question from the reader waits for a voice question', (tester) async {
      final v = make();
      final s = await pumpChat(tester, v);
      unawaited(v.start(tester.state(find.byType(ChatScreen))));
      await tester.pump(const Duration(seconds: 1));
      s.pendingQuestion.value = 'Study John 1:1.';
      await tester.pump();
      expect(s.pendingQuestion.value, 'Study John 1:1.');
      expect(find.text('Study John 1:1.'), findsNothing);

      await v.cancel();
      await tester.pump();
      expect(s.pendingQuestion.value, isNull);
      expect(find.text('Study John 1:1.'), findsOneWidget);
    });

    voiceWidgets('a transcript joins what was typed instead of replacing it', (tester) async {
      final v = make();
      await pumpChat(tester, v);
      await tester.enterText(find.byType(TextField), 'About grace,');
      unawaited(v.start(tester.state(find.byType(ChatScreen))));
      await tester.pump(const Duration(seconds: 1));
      unawaited(v.stop());
      await tester.pump();
      expect(find.text('About grace, What does John 3:16 mean?'), findsOneWidget);
    });
  });
}
