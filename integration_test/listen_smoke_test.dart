import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/listen.dart';
import 'package:berea/listen_voice.dart';
import 'package:berea/notebook_store.dart';
import 'package:berea/notebooks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The whole of Listen in the real app with `flutter test integration_test/listen_smoke_test.dart
/// -d macos`: the voice download from the data release, the script written by Ollama's Gemma 4,
/// Supertonic in its isolate, and playback. Needs `ollama pull gemma4:e2b` and the network.
const _deadline = Duration(minutes: 30);
const _poll = Duration(seconds: 2);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a notebook becomes a deep dive that plays', (tester) async {
    final dir = await Directory.systemTemp.createTemp('berea-listen');
    SharedPreferences.setMockInitialValues({'engine': EngineKind.ollama.name});
    final s = await AppState.bootstrap(
      supportDir: dir,
      prefs: await SharedPreferences.getInstance(),
    );
    await tester.runAsync(s.startHelper);
    final id = s.notebooks.createNotebook('Rejoice');
    await tester.runAsync(
      () => s.notebooks.addSource(id, passageSource(s.db, 'Philippians 4:4-9', 'BSB')!),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NotebookScreen(state: s, notebookId: id),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Listen'));
    await tester.pumpAndSettle();
    expect(find.text('Listen needs a voice'), findsOneWidget);

    final t0 = DateTime.now();
    await tester.tap(find.text('Agree and download'));
    await tester.runAsync(() async {
      while (s.voiceDownloading || !s.voiceReady) {
        if (s.voiceError != null) fail(s.voiceError!);
        await Future<void>.delayed(_poll);
      }
    });
    final t1 = DateTime.now();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make the deep dive'));
    final stages = <String>[];
    await tester.runAsync(() async {
      final until = DateTime.now().add(_deadline);
      while (s.listenJob?.running ?? true) {
        final status = s.listenJob?.status ?? 'starting';
        if (stages.isEmpty || stages.last.split(' @ ').first != status) {
          stages.add('$status @ ${DateTime.now().difference(t1).inSeconds}s');
        }
        if (DateTime.now().isAfter(until)) fail('not done in $_deadline: $stages');
        await Future<void>.delayed(_poll);
      }
    });
    final job = s.listenJob!;
    expect(job.stage, ListenStage.ready, reason: '${job.error} $stages');
    final done = s.listenStore(id).finished(s.listenKey(s.studyPacket(id)))!;
    final words = done.script.fold(0, (n, b) => n + b.text.split(RegExp(r'\s+')).length);
    debugPrint(
      'LISTEN voice=${t1.difference(t0).inSeconds}s total=${DateTime.now().difference(t1).inSeconds}s '
      'audio=${done.length} words=$words rate=${wavRate(done.audio)} file=${done.audio.path}',
    );
    for (final st in stages.where((x) => x.startsWith('Writing') || x.startsWith('Recording, 0'))) {
      debugPrint('LISTEN stage $st');
    }
    for (final b in done.script) {
      debugPrint('LISTEN ${b.beat.name}: ${b.text}');
    }
    expect(wavRate(done.audio), 44100);
    expect(done.length, greaterThan(const Duration(minutes: 2)));

    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Play'));
    // The player reads its position once a frame, so frames are drawn while it plays.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^0:0[1-9] / ')), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 40)));
}
