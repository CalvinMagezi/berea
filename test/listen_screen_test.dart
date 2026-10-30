import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/listen.dart';
import 'package:berea/listen_screen.dart';
import 'package:berea/listen_voice.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bible.dart';

const _phone = Size(600, 1000);

/// Answers the audio player's platform calls, which tests have no plugin for.
void _quietAudio() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
}

void main() {
  if (needsBuiltBible case final why?) {
    test('these tests open the built Bible', () {}, skip: why);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppState s;
  late int notebook;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('berea-listen-screen');
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
    s = await AppState.bootstrap(supportDir: dir, prefs: await SharedPreferences.getInstance());
    s.listenNotice = const QuietListenNotice();
    notebook = s.notebooks.createNotebook('Born again');
    await s.notebooks.addSource(notebook, passageSource(s.db, 'John 3:1-21', 'BSB')!);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: bereaTheme(Brightness.light), home: home));
    await tester.pump();
  }

  Widget screen([int? id]) =>
      ListenScreen(state: s, notebookId: id ?? notebook, title: 'Born again');

  testWidgets('without the voice, Listen offers it with its size and licence first', (
    tester,
  ) async {
    s
      ..voicePresent = ((_) => false)
      ..mobileDataNow = (() async => false);
    final asked = <int>[];
    s.voiceDownload = (dir, {required onProgress, stop}) async {
      onProgress(voiceBytes ~/ 2, voiceBytes);
      asked.add(1);
    };
    await pump(tester, screen());
    expect(find.text('Listen needs a voice'), findsOneWidget);
    expect(find.textContaining('145 MB download'), findsOneWidget);
    expect(find.textContaining('Open RAIL-M License'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
    await tester.tap(find.text('Agree and download'));
    await tester.pump();
    expect(asked, [1]);
  });

  testWidgets('with the voice, it says how long the deep dive is and how long it takes', (
    tester,
  ) async {
    s.voicePresent = (_) => true;
    await pump(tester, screen());
    expect(find.textContaining(RegExp(r'about (\d+) minutes long')), findsOneWidget);
    expect(find.textContaining('You can keep using Berea'), findsOneWidget);
    expect(find.text('Make the deep dive'), findsOneWidget);
    expect(find.textContaining('walks through'), findsNothing);
  });

  testWidgets('a long notebook says how much of it the deep dive walks', (tester) async {
    s.voicePresent = (_) => true;
    final psalm = s.notebooks.createNotebook('Psalm 119');
    await tester.runAsync(
      () => s.notebooks.addSource(psalm, passageSource(s.db, 'Psalm 119', 'BSB')!),
    );
    await pump(tester, screen(psalm));
    expect(find.textContaining('of its 176 verses, from the start'), findsOneWidget);
  });

  testWidgets('while it is made, the screen and the notebook button show how far along it is', (
    tester,
  ) async {
    s.voicePresent = (_) => true;
    s.listenJob = ListenJob(notebook, 'Born again')..writing(2, 8);
    await pump(
      tester,
      Scaffold(
        appBar: AppBar(
          actions: [ListenButton(state: s, notebookId: notebook, title: 'Born again')],
        ),
      ),
    );
    expect(find.byTooltip('Listen: Writing part 3 of 8'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await pump(tester, screen());
    expect(find.text('Writing part 3 of 8'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Stopping after this part'), findsOneWidget);
  });

  testWidgets('a finished deep dive plays, says it is machine generated, and shows its script', (
    tester,
  ) async {
    _quietAudio();
    s.voicePresent = (_) => true;
    final key = s.listenKey(s.studyPacket(notebook));
    final store = s.listenStore(notebook)
      ..saveBeats(key, const [ScriptBeat(Beat.opening, 'Nicodemus came (John 3:2).', [])]);
    await tester.runAsync(() async {
      await (WavSink(store.audio, 8000)..silence(const Duration(seconds: 3))).close();
    });
    store.finish(key, const Duration(minutes: 8, seconds: 5), store.beats(key));
    await pump(tester, screen());
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.text('0:00 / 8:05'), findsOneWidget);
    expect(find.textContaining('Machine generated'), findsOneWidget);
    expect(find.text('Make it again'), findsOneWidget);
    await tester.tap(find.text('Script'));
    await tester.pumpAndSettle();
    expect(find.text('Nicodemus came (John 3:2).'), findsOneWidget);
  });
}
