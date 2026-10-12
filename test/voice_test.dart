import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea/app_state.dart';
import 'package:berea/voice.dart';
import 'package:berea/voice_composer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

/// A WAV file with [extraChunk] before the format chunk, as Core Audio writes them.
Uint8List wav({
  int rate = voiceSampleRate,
  int channels = voiceChannels,
  int bits = voiceBitsPerSample,
  bool extraChunk = false,
}) {
  const pcmBytes = 3200;
  final b = BytesBuilder();
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  b.add('RIFF'.codeUnits);
  u32(0);
  b.add('WAVE'.codeUnits);
  if (extraChunk) {
    b.add('FLLR'.codeUnits);
    u32(3);
    b.add([0, 0, 0, 0]);
  }
  b.add('fmt '.codeUnits);
  u32(16);
  u16(1);
  u16(channels);
  u32(rate);
  u32(rate * channels * bits ~/ 8);
  u16(channels * bits ~/ 8);
  u16(bits);
  b.add('data'.codeUnits);
  u32(pcmBytes);
  b.add(Uint8List(pcmBytes));
  return b.toBytes();
}

class FakeRecorder implements AudioRecorder {
  bool permission = true;
  Completer<bool>? permissionGate;
  Uint8List bytes = wav();
  RecordConfig? config;
  String? path;
  int starts = 0;
  int cancels = 0;

  @override
  Future<bool> hasPermission({bool request = true}) =>
      permissionGate?.future ?? Future.value(permission);

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    starts++;
    this.config = config;
    this.path = path;
    File(path).writeAsBytesSync(bytes);
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
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late FakeRecorder recorder;
  late List<Uint8List> heard;
  late String reply;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('berea-voice-test');
    recorder = FakeRecorder();
    heard = [];
    reply = '  What does John 3:16 mean?  ';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  VoiceInput make({
    Duration max = maxVoiceDuration,
    Duration min = Duration.zero,
    Future<String> Function(Uint8List)? transcribe,
  }) => VoiceInput(
    transcribe:
        transcribe ??
        (w) async {
          heard.add(w);
          return reply;
        },
    recorder: recorder,
    tempDir: () async => dir,
    maxDuration: max,
    minDuration: min,
  );

  bool recordingLeft() => dir.listSync().isNotEmpty;

  group('wavProblem', () {
    test('accepts 16 kHz mono 16-bit PCM, with or without extra chunks', () {
      expect(wavProblem(wav()), isNull);
      expect(wavProblem(wav(extraChunk: true)), isNull);
    });
    test('names what is wrong', () {
      expect(wavProblem(wav(rate: 44100)), '44100 Hz');
      expect(wavProblem(wav(channels: 2)), '2 channels');
      expect(wavProblem(wav(bits: 8)), '8-bit');
      expect(wavProblem(Uint8List.fromList('hello world!'.codeUnits)), 'not a WAV file');
    });
  });

  group('voiceSupport', () {
    test('needs the on-device engine with Gemma 4', () {
      final ollama = Settings(engine: EngineKind.ollama, deviceModelId: 'gemma-4-e2b');
      final small = Settings(engine: EngineKind.device, deviceModelId: 'gemma-3-1b');
      expect(voiceSupport(ollama, DeviceModelState.ready), VoiceSupport.needsGemma4);
      expect(voiceSupport(small, DeviceModelState.ready), VoiceSupport.needsGemma4);
    });
    test('waits for Gemma 4 to load', () {
      for (final id in ['gemma-4-e2b', 'gemma-4-e4b']) {
        final s = Settings(engine: EngineKind.device, deviceModelId: id);
        expect(voiceSupport(s, DeviceModelState.ready), VoiceSupport.ready);
        expect(voiceSupport(s, DeviceModelState.loading), VoiceSupport.notReady);
        expect(voiceSupport(s, DeviceModelState.notInstalled), VoiceSupport.notReady);
      }
    });
  });

  group('VoiceInput', () {
    test('the cap is 30 seconds', () => expect(maxVoiceDuration, const Duration(seconds: 30)));

    test('records 16 kHz mono WAV, transcribes it, then waits for the user', () async {
      final v = make();
      await v.start();
      expect(v.phase, VoicePhase.recording);
      expect(recorder.config!.encoder, AudioEncoder.wav);
      expect(recorder.config!.sampleRate, voiceSampleRate);
      expect(recorder.config!.numChannels, voiceChannels);
      await v.stop();
      expect(v.phase, VoicePhase.confirm);
      expect(v.transcript, 'What does John 3:16 mean?');
      expect(heard.single, recorder.bytes);
      expect(recordingLeft(), isFalse);
      v.accept();
      expect(v.phase, VoicePhase.idle);
      v.dispose();
    });

    test('stops itself at the cap', () async {
      final v = make(max: const Duration(milliseconds: 600));
      await v.start();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(v.phase, VoicePhase.confirm);
      expect(heard, hasLength(1));
      expect(v.elapsed, lessThan(const Duration(milliseconds: 600) + voiceTick));
      expect(recordingLeft(), isFalse);
      v.dispose();
    });

    test('a slip shorter than the minimum is discarded', () async {
      final v = make(min: const Duration(seconds: 5));
      await v.start();
      await v.stop();
      expect(v.phase, VoicePhase.idle);
      expect(v.message, tooShortMessage);
      expect(heard, isEmpty);
      expect(recordingLeft(), isFalse);
    });

    test('denied microphone explains and records nothing', () async {
      recorder.permission = false;
      final v = make();
      await v.start();
      expect(v.phase, VoicePhase.idle);
      expect(v.message, micDeniedMessage);
      expect(recorder.starts, 0);
    });

    test('a failed or empty transcription returns to idle and deletes the file', () async {
      final failing = make(transcribe: (_) async => throw StateError('model closed'));
      await failing.start();
      await failing.stop();
      expect(failing.phase, VoicePhase.idle);
      expect(failing.message, voiceFailedMessage);
      expect(recordingLeft(), isFalse);

      reply = '   ';
      final empty = make();
      await empty.start();
      await empty.stop();
      expect(empty.phase, VoicePhase.idle);
      expect(empty.message, nothingHeardMessage);
      expect(recordingLeft(), isFalse);
    });

    test('audio in the wrong format is never sent to the model', () async {
      recorder.bytes = wav(rate: 44100);
      final v = make();
      await v.start();
      await v.stop();
      expect(v.message, voiceFailedMessage);
      expect(heard, isEmpty);
      expect(recordingLeft(), isFalse);
    });

    test('cancel throws the recording away', () async {
      final v = make();
      await v.start();
      await v.cancel();
      expect(v.phase, VoicePhase.idle);
      expect(recorder.cancels, 1);
      expect(heard, isEmpty);
      expect(recordingLeft(), isFalse);
    });

    test('a release during the permission prompt stops once recording begins', () async {
      recorder.permissionGate = Completer();
      final v = make(min: const Duration(seconds: 5));
      final starting = v.start();
      expect(v.active, isTrue);
      await v.stop();
      recorder.permissionGate!.complete(true);
      await starting;
      expect(v.phase, VoicePhase.idle);
      expect(v.message, tooShortMessage);
      expect(recordingLeft(), isFalse);
    });

    test('a cancel during the permission prompt never transcribes', () async {
      recorder.permissionGate = Completer();
      final v = make();
      final starting = v.start();
      await v.cancel();
      recorder.permissionGate!.complete(true);
      await starting;
      expect(v.phase, VoicePhase.idle);
      expect(heard, isEmpty);
      expect(recordingLeft(), isFalse);
    });

    test('leftover recordings from a crash are swept', () async {
      final stale = File('${dir.path}/1.wav')..writeAsBytesSync(wav());
      stale.setLastModifiedSync(DateTime.now().subtract(staleVoiceAge * 2));
      final live = File('${dir.path}/2.wav')..writeAsBytesSync(wav());
      make();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stale.existsSync(), isFalse);
      expect(live.existsSync(), isTrue, reason: 'another composer may still be using it');
    });
  });

  group('composer', () {
    Future<void> pumpComposer(
      WidgetTester tester,
      VoiceInput voice, {
      VoiceSupport support = VoiceSupport.ready,
      VoidCallback? onOpenSettings,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: voice,
            builder: (_, _) => Column(
              children: [
                VoiceStatusLine(voice),
                VoiceMicButton(
                  voice: voice,
                  support: support,
                  modelFree: true,
                  onOpenSettings: onOpenSettings ?? () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // File reads finish on the real event loop and continue in the fake one, so alternate.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('walks idle, recording, transcribing and confirm', (tester) async {
      final pending = Completer<String>();
      final v = make(transcribe: (_) => pending.future);
      await pumpComposer(tester, v);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await settle(tester);
      expect(v.phase, VoicePhase.recording);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Listening 0:02 of 0:30'), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await settle(tester);
      expect(v.phase, VoicePhase.transcribing);
      expect(find.text('Transcribing on this device…'), findsOneWidget);

      pending.complete('Who were the Bereans?');
      await settle(tester);
      expect(v.phase, VoicePhase.confirm);
      expect(find.text('Check the words, edit them if needed, then send.'), findsOneWidget);
      v.dispose();
    });

    testWidgets('holding the button records until release', (tester) async {
      final v = make();
      await pumpComposer(tester, v);
      final hold = await tester.startGesture(tester.getCenter(find.byType(IconButton)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await settle(tester);
      expect(v.phase, VoicePhase.recording);
      await hold.up();
      await settle(tester);
      expect(v.phase, VoicePhase.confirm);
      expect(heard, hasLength(1));
      v.dispose();
    });

    testWidgets('without Gemma 4 the button points to Engine settings', (tester) async {
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
      v.dispose();
    });

    testWidgets('a model that is still loading disables the button', (tester) async {
      final v = make();
      await pumpComposer(tester, v, support: VoiceSupport.notReady);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
      v.dispose();
    });
  });
}
