import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:berea/app_state.dart';
import 'package:berea/edge_engine.dart';
import 'package:berea/listen.dart';
import 'package:berea/listen_voice.dart';
import 'package:berea/models.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/voice.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

const _rate = 8000;

/// Writes each beat as one short cited sentence, and can hold a beat until released.
class _Writer implements LlmEngine {
  var calls = 0;
  Completer<void>? gate;

  @override
  String get name => 'writer';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) async* {
    calls++;
    await gate?.future;
    yield 'Nicodemus came to Jesus at night (John 3:2). ';
    yield 'Ask yourself what new birth means.';
  }
}

/// A Gemma that only knows whether it was closed.
class _ClosingModel implements InferenceModel {
  var closed = false;

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notice implements ListenNotice {
  final log = <String>[];
  @override
  Future<void> working(String title, String body) async => log.add('working $body');
  @override
  Future<void> idle() async => log.add('idle');
  @override
  Future<void> ready(String title, String body) async => log.add('ready $body');
}

/// Tests have no microphone plugin; the deep dive only asks whether voice is in use.
class _NoRecorder implements AudioRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  if (needsBuiltBible case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppState s;
  late _Writer writer;
  late _ClosingModel gemma;
  late _Notice notice;
  late List<String> spokeWith;
  late int notebook;
  Completer<void>? holdVoice;

  /// Stands in for Supertonic: a tenth of a second of quiet per paragraph, and it notes what the
  /// helper was doing when the voice started.
  Future<void> fakeVoice({
    required Directory voice,
    required List<List<String>> beats,
    required Directory out,
    required void Function(int done, int total) onProgress,
    Future<void>? stop,
  }) async {
    spokeWith.add('closed=${gemma.closed} harness=${s.harness != null}');
    var stopped = false;
    unawaited(stop?.then((_) => stopped = true));
    final total = beats.fold(0, (n, b) => n + b.length);
    var done = 0;
    for (var i = 0; i < beats.length; i++) {
      if (beatAudio(out, i).existsSync()) {
        done += beats[i].length;
        continue;
      }
      await holdVoice?.future;
      if (stopped) return;
      final sink = WavSink(File('${out.path}/beat-$i.wav.part'), _rate);
      for (final _ in beats[i]) {
        sink.add(Float32List(_rate ~/ 10));
        onProgress(++done, total);
      }
      await sink.close();
      File('${out.path}/beat-$i.wav.part').renameSync(beatAudio(out, i).path);
    }
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('berea-listen-test');
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
    s = await AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
    writer = _Writer();
    gemma = _ClosingModel();
    notice = _Notice();
    spokeWith = [];
    holdVoice = null;
    s
      ..harness = Harness(db: s.db, engine: writer, systemPrompt: s.systemPrompt)
      ..debugEdge = EdgeAiEngine(gemma, edgeModelById('gemma-4-e2b'))
      ..voicePresent = ((_) => true)
      ..speakBeats = fakeVoice
      ..listenNotice = notice
      ..voice = VoiceInput(
        transcribe: (_) async => '',
        recorder: _NoRecorder(),
        cacheDir: () async => dir,
      );
    notebook = s.notebooks.createNotebook('Born again');
    await s.notebooks.addSource(notebook, passageSource(s.db, 'John 3:1-21', 'BSB')!);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  int planned() => ListenWriter(
    s.db,
    s.systemPrompt,
    s.settings.tier,
  ).plan(s.studyPacket(notebook)).beats.length;

  test('writes every beat, closes Gemma before the voice, and keeps the joined audio', () async {
    await s.makeDeepDive(notebook, 'Born again');
    final job = s.listenJob!;
    expect(job.stage, ListenStage.ready, reason: job.error);
    expect(writer.calls, planned());
    expect(spokeWith, ['closed=true harness=false']);
    final store = s.listenStore(notebook);
    final done = store.finished(s.listenKey(s.studyPacket(notebook)))!;
    expect(done.current, isTrue);
    expect(done.script.length, planned());
    expect(done.script.first.text, contains('John 3:2'));
    expect(done.length.inMilliseconds, greaterThan(0));
    expect(wavRate(done.audio), _rate);
    expect(store.dir.listSync().where((f) => f.path.contains('beat-')), isEmpty);
    expect(notice.log.first, startsWith('working Writing part 1 of'));
    expect(notice.log, containsAllInOrder(['idle', 'ready Born again']));
  });

  test('the voice reads the machine-generated notice first and never a failed claim', () async {
    final spoken = <List<String>>[];
    s.speakBeats =
        ({
          required Directory voice,
          required List<List<String>> beats,
          required Directory out,
          required void Function(int done, int total) onProgress,
          Future<void>? stop,
        }) async {
          spoken.addAll(beats);
          return fakeVoice(
            voice: voice,
            beats: beats,
            out: out,
            onProgress: onProgress,
            stop: stop,
          );
        };
    await s.makeDeepDive(notebook, 'Born again');
    expect(spoken.first.first, listenOpeningNotice);
    expect(
      spoken.first[1],
      'Nicodemus came to Jesus at night, John chapter 3, verse 2. '
      'Ask yourself what new birth means.',
    );
  });

  test('a question that holds the helper goes first; the deep dive waits for it', () async {
    final answer = Completer<void>();
    final asking = s.useModel(() => answer.future);
    final dive = s.makeDeepDive(notebook, 'Born again');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(writer.calls, 0);
    answer.complete();
    await asking;
    await dive;
    expect(s.listenJob!.stage, ListenStage.ready);
  });

  test('Stop while writing keeps the parts written; Continue writes only the rest', () async {
    writer.gate = Completer<void>();
    final dive = s.makeDeepDive(notebook, 'Born again');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.listenJob!.stop();
    writer.gate!.complete();
    await dive;
    expect(s.listenJob!.stage, ListenStage.stopped);
    expect(writer.calls, 1);
    expect(s.listenStore(notebook).unfinished(s.listenKey(s.studyPacket(notebook))), isTrue);
    expect(gemma.closed, isFalse, reason: 'the voice never started');

    writer.gate = null;
    await s.makeDeepDive(notebook, 'Born again');
    expect(s.listenJob!.stage, ListenStage.ready);
    expect(writer.calls, planned());
  });

  test('Stop while speaking keeps the beats spoken and loads the helper again', () async {
    holdVoice = Completer<void>();
    final dive = s.makeDeepDive(notebook, 'Born again');
    while (s.listenJob?.stage != ListenStage.speaking) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    s.listenJob!.stop();
    holdVoice!.complete();
    await dive;
    expect(s.listenJob!.stage, ListenStage.stopped);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.helperState, isNot(isA<HelperResting>()), reason: 'the helper is rebuilt');

    holdVoice = null;
    final writes = writer.calls;
    await s.makeDeepDive(notebook, 'Born again');
    expect(s.listenJob!.stage, ListenStage.ready);
    expect(writer.calls, writes, reason: 'the script was already written');
  });

  test('a deep dive never enters the backup', () async {
    final before = jsonEncode(s.study.exportTables());
    await s.makeDeepDive(notebook, 'Born again');
    expect(s.listenJob!.stage, ListenStage.ready);
    expect(jsonEncode(s.study.exportTables()).length, before.length);
  });

  test('a changed notebook keeps the old deep dive playable until a new one replaces it', () async {
    await s.makeDeepDive(notebook, 'Born again');
    await s.notebooks.addSource(notebook, passageSource(s.db, 'John 1:1-5', 'BSB')!);
    final key = s.listenKey(s.studyPacket(notebook));
    final store = s.listenStore(notebook);
    expect(store.finished(key)!.current, isFalse);
    expect(store.unfinished(key), isFalse);
    // The voice gave the memory back and the helper was rebuilt; this one writes again.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.harness = Harness(db: s.db, engine: writer, systemPrompt: s.systemPrompt);
    await s.makeDeepDive(notebook, 'Born again');
    expect(store.finished(key)!.current, isTrue);
  });

  test('without the voice or a passage, it says what is missing', () async {
    s.voicePresent = (_) => false;
    await s.makeDeepDive(notebook, 'Born again');
    expect(s.listenJob!.error, listenNeedsVoice);
    s.voicePresent = (_) => true;
    final empty = s.notebooks.createNotebook('Empty');
    await s.makeDeepDive(empty, 'Empty');
    expect(s.listenJob!.error, listenNothing);
    expect(writer.calls, 0);
  });

  test('deep dives of deleted notebooks are removed at the next start', () async {
    await s.makeDeepDive(notebook, 'Born again');
    final kept = s.listenStore(notebook).dir;
    s.notebooks.deleteNotebook(notebook);
    final again = await AppState.bootstrap(supportDir: dir, prefs: s.prefs);
    expect(again.listenStore(notebook).dir.existsSync(), isFalse);
    expect(kept.existsSync(), isFalse);
  });

  test('Make it again keeps the recording playing when the new one cannot be made', () async {
    await s.makeDeepDive(notebook, 'Born again');
    final key = s.listenKey(s.studyPacket(notebook));
    final store = s.listenStore(notebook);
    final before = store.finished(key)!.length;
    // The voice gave the memory back and nothing rebuilt a helper that can write.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s
      ..harness = null
      ..helperState = const HelperNotInstalled();
    await s.makeDeepDive(notebook, 'Born again', again: true);
    expect(s.listenJob!.error, listenNeedsHelper);
    expect(store.finished(key)!.length, before);
    expect(store.audio.existsSync(), isTrue);
  });

  test('deleting the notebook stops its deep dive and removes what was made', () async {
    writer.gate = Completer<void>();
    final dive = s.makeDeepDive(notebook, 'Born again');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.notebooks.deleteNotebook(notebook);
    expect(s.listenJob!.stopping, isTrue);
    writer.gate!.complete();
    await dive;
    expect(s.listenJob!.stage, ListenStage.stopped);
    expect(s.listenStore(notebook).dir.existsSync(), isFalse);
    expect(notice.log, isNot(contains(startsWith('ready'))));
  });

  test('a new tier while it is written stops it, since the plan was for the old one', () async {
    writer.gate = Completer<void>();
    final dive = s.makeDeepDive(notebook, 'Born again');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.settings = s.settings.copyWith(tier: Tier.low);
    writer.gate!.complete();
    await dive;
    expect(s.listenJob!.error, listenSettingsChanged);
  });

  test('a settings change while the voice reads returns at once; the helper loads after', () async {
    holdVoice = Completer<void>();
    final dive = s.makeDeepDive(notebook, 'Born again');
    while (s.listenJob?.stage != ListenStage.speaking) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await s
        .updateSettings(s.settings.copyWith(translation: 'KJV'))
        .timeout(const Duration(seconds: 1));
    expect(s.harness, isNull, reason: 'nothing loads beside the voice');
    holdVoice!.complete();
    await dive;
    expect(s.listenJob!.stage, ListenStage.ready);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.harness, isNotNull);
  });

  test('Stop before the voice starts never starts it', () async {
    writer.gate = Completer<void>();
    final dive = s.makeDeepDive(notebook, 'Born again');
    while (writer.calls < planned()) {
      writer.gate!.complete();
      writer.gate = Completer<void>();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    s.listenJob!.stop();
    writer.gate!.complete();
    await dive;
    expect(s.listenJob!.stage, ListenStage.stopped);
    expect(spokeWith, isEmpty);
    expect(gemma.closed, isFalse);
  });

  test('beats are joined with a pause between them and the header says how long', () async {
    final out = Directory('${dir.path}/join')..createSync();
    for (var i = 0; i < 2; i++) {
      final sink = WavSink(beatAudio(out, i), _rate)..add(Float32List(_rate));
      await sink.close();
    }
    final into = File('${out.path}/all.wav');
    final length = await joinBeats(out, 2, into);
    expect(length, const Duration(seconds: 2) + beatPause);
    final bytes = into.readAsBytesSync();
    final data = ByteData.sublistView(bytes).getUint32(40, Endian.little);
    expect(data, bytes.length - 44);
    expect(wavRate(into), _rate);
  });
}
