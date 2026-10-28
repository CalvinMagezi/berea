import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/chat_screen.dart';
import 'package:berea/models.dart';
import 'package:berea/study_store.dart';
import 'package:berea/voice.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/bible.dart';

class _Answer implements LlmEngine {
  final asked = <String>[];

  @override
  String get name => 'answer';

  @override
  Stream<String> generate(List<ChatMessage> messages, {required int maxTokens}) {
    asked.add(messages.last.content);
    return Stream.value('Grace is a gift (John 3:16, BSB).');
  }
}

class _NoRecorder implements AudioRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _model = edgeModels.first;

void main() {
  late Directory dir;
  late BibleDb bible;

  setUp(() => dir = Directory.systemTemp.createTempSync('berea-helper-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// An app whose helper is still loading: no harness yet.
  AppState loading() {
    bible = testBible();
    return AppState()
      ..db = bible
      ..study = StudyStore(sqlite3.openInMemory())
      ..settings = Settings(engine: EngineKind.device)
      ..voice = VoiceInput(
        transcribe: (_) async => '',
        recorder: _NoRecorder(),
        cacheDir: () async => dir,
      )
      ..helperState = const HelperLoading();
  }

  test('a question sent while the helper loads is answered once it is ready', () async {
    final s = loading();
    expect(s.ready, isTrue, reason: 'one question may be sent during the load');
    final sent = s.send('What is grace?');
    await Future<void>.delayed(Duration.zero);
    expect(s.turns.single.question, 'What is grace?');
    expect(s.turns.single.done, isFalse);
    expect(s.ready, isFalse, reason: 'a second question waits for the first');

    final engine = _Answer();
    s.harness = Harness(db: bible, engine: engine, systemPrompt: 'SYS');
    s.helperState = const HelperReady();
    await sent;

    expect(engine.asked, hasLength(1));
    expect(engine.asked.single, contains('What is grace?'));
    expect(s.turns.single.done, isTrue);
    expect(s.turns.single.answer, contains('Grace is a gift'));
    expect(s.ready, isTrue);
  });

  test('a held question says in plain words why it went unanswered when the load fails', () async {
    final s = loading();
    final sent = s.send('What is grace?');
    s.helperState = const HelperFailed(helperLoadFailed, detail: 'PlatformException(boom)');
    await sent;
    expect(s.turns.single.error, helperLoadFailed);
    expect(s.deviceError, helperLoadFailed, reason: 'Settings shows words, not the exception');
  });

  test('with no helper on the way, nothing is sent', () async {
    final s = loading()..helperState = const HelperNotInstalled();
    expect(s.ready, isFalse);
    await s.send('What is grace?');
    expect(s.turns, isEmpty);
  });

  test('the older device state follows the helper state', () {
    final s = loading();
    expect(s.deviceState, DeviceModelState.loading);
    s.helperState = const HelperChecking();
    expect(s.deviceState, DeviceModelState.loading);
    s.helperState = HelperDownloading(0.42, model: _model, total: 1000);
    expect(s.deviceState, DeviceModelState.downloading);
    expect(s.downloadProgress, 42);
    expect((s.helperState as HelperDownloading).bytes, 420);
    s.helperState = const HelperFailed(helperDownloadFailed);
    expect(s.deviceState, DeviceModelState.failed);
    expect(s.deviceError, helperDownloadFailed);
    s.deviceState = DeviceModelState.downloading;
    expect(s.helperState, isA<HelperDownloading>());
  });

  test('a hand-built app never starts loading a real model', () async {
    final s = loading();
    await s.startHelper();
    expect(s.helperState, isA<HelperLoading>());
    expect(s.harness, isNull);
  });

  test('failures reach readers as plain sentences, never raw error text', () {
    expect(answerFailure(const SocketException('Connection refused')), answerFailed);
    expect(answerFailure(const OllamaException('Ollama HTTP 500: {"error":"x"}')), ollamaFailed);
    const unreachable = '$ollamaUnreachable at http://localhost:11434. Install Ollama.';
    expect(answerFailure(const OllamaException(unreachable)), unreachable);
    const restoreFailed = 'The backup could not be restored.';
    expect(plainFailure(StateError('bad'), restoreFailed), restoreFailed);
    expect(plainFailure(const ReaderMessage('Use 1 to 8 letters.'), 'x'), 'Use 1 to 8 letters.');
    const parser = FormatException('unknown book "Xyz"');
    expect(plainFailure(parser, 'The translation could not be imported.'), isNot(contains('Xyz')));

    final s = loading();
    s.helperState = const HelperFailed(helperLoadFailed, detail: 'PlatformException(...)');
    expect(s.deviceError, helperLoadFailed);
  });

  testWidgets('a question from the reader waits in Study and is answered once the helper is ready', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final s = loading()..prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(state: s)));
    s.askAboutWord('What is grace?');
    await tester.pump();
    expect(s.turns.single.question, 'What is grace?');
    expect(s.turns.single.done, isFalse);
    expect(find.text('What is grace?'), findsOneWidget, reason: 'the held question is shown');

    s.harness = Harness(db: bible, engine: _Answer(), systemPrompt: 'SYS');
    s.helperState = const HelperReady();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.turns.single.done, isTrue);
    expect(find.textContaining('Grace is a gift'), findsOneWidget);
  });

  test('clearing the study drops a held question', () async {
    final s = loading();
    final sent = s.send('What is grace?');
    s.clear();
    await sent;
    expect(s.turns, isEmpty);
    s.harness = Harness(db: bible, engine: _Answer(), systemPrompt: 'SYS');
    s.helperState = const HelperReady();
    expect(s.busy, isFalse, reason: 'nothing was left to answer');
  });
}
