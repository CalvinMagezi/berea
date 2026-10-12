import 'dart:io';
import 'dart:math';

import 'package:berea/app_state.dart';
import 'package:berea/narration_packs.dart';
import 'package:berea/pinned_download.dart';
import 'package:berea/read_along.dart';
import 'package:berea/reader_screen.dart';
import 'package:berea/theme.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Path to a built narration pack for John, passed with --dart-define.
const packPath = String.fromEnvironment('NARRATION_PACK');
const sampleEvery = Duration(milliseconds: 20);
const john = 43;

/// Runs the real app state against a temporary support folder and mocked preferences, so the
/// app's own data is never touched, then plays John 3 muted and measures the highlight.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppState s;
  late Directory support;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    support = Directory.systemTemp.createTempSync('berea_read_along_it');
    if (!bool.fromEnvironment('NO_BACKGROUND')) await initReadAlongAudio();
    s = await AppState.bootstrap(supportDir: support);
  });

  tearDownAll(() async {
    await s.readAlong.stop();
    support.deleteSync(recursive: true);
  });

  testWidgets('the John pack matches its pin and every verse of the Bible database', (_) async {
    expect(packPath, isNotEmpty, reason: 'pass --dart-define=NARRATION_PACK=<souer-43.sqlite>');
    final bytes = File(packPath).readAsBytesSync();
    expect(bytes.length, narrationPins[john]!.bytes);
    expect(hexOf((await Sha256().hash(bytes)).bytes), narrationPins[john]!.sha256);
    expect(await s.narration.installFromFile(packPath), 'John');
    var verses = 0;
    for (var c = 1; c <= s.db.chapterCount(bookById(john)); c++) {
      final track = await s.narration.track(john, c);
      for (final v in s.db.passage(Ref(bookById(john), c))) {
        verses++;
        expect(
          track.timings.wordsPerVerse[v.verse] ?? 0,
          wordRanges(v.text).length,
          reason: 'John $c:${v.verse}',
        );
      }
    }
    debugPrint('READALONG verses checked: $verses');
  });

  testWidgets('John 3 plays with the highlight in step with the player', (tester) async {
    s.setReader(bookById(john), 3);
    await tester.pumpWidget(
      MaterialApp(
        theme: bereaTheme(Brightness.light),
        home: ReaderScreen(state: s),
      ),
    );
    // Read before playing: extracting a chapter replaces the file the player has open.
    final track = await s.narration.track(john, 3);
    final r = s.readAlong;
    await r.start(
      book: bookById(john),
      chapter: 3,
      voice: ReadAlongVoice.narration,
      verses: s.db.passage(Ref(bookById(john), 3)),
    );
    final player = r.debugPlayer!;
    await player.setVolume(0);
    debugPrint(
      'READALONG duration: player ${player.duration?.inMilliseconds} ms, pack '
      '${track.durationMs} ms, priming ${track.primingMs} ms, applied offset ${r.offsetMs} ms',
    );
    expect(r.state.value?.status, isNot(ReadAlongStatus.failed), reason: r.state.value?.error);

    await _waitFor(tester, () => r.position.value != null);
    final normal = await _measure(tester, r, const Duration(seconds: 20));
    debugPrint('READALONG drift 1x: $normal');

    await r.setSpeed(1.5);
    final fast = await _measure(tester, r, const Duration(seconds: 8));
    debugPrint('READALONG drift 1.5x: $fast');
    await r.setSpeed(1.0);

    await r.togglePlay();
    await _waitFor(tester, () => r.state.value?.status == ReadAlongStatus.paused);
    await r.seek(16);
    expect(r.position.value, (verse: 16, word: 0));
    await _waitFor(tester, () => _markedWord(tester) == 'For');
    await r.seek(16, 3);
    await _waitFor(tester, () => _markedWord(tester) == 'loved');
    final pos = player.position.inMilliseconds - r.offsetMs;
    final want = track.timings.words[track.timings.indexOf(16, 3)!].startMs;
    debugPrint('READALONG seek to 3:16 "loved": player at $pos ms, word starts at $want ms');
    expect((pos - want).abs(), lessThan(aacFrameMs));

    await r.nextVerse();
    await tester.pump();
    expect(r.position.value?.verse, 17);
  });

  testWidgets('the device voice reports word progress offline', (tester) async {
    final r = s.readAlong;
    await r.start(
      book: bookById(john),
      chapter: 3,
      voice: ReadAlongVoice.device,
      verses: s.db.passage(Ref(bookById(john), 3)),
    );
    await r.debugTts!.setVolume(0);
    await _waitFor(tester, () => (r.position.value?.word ?? 0) >= 3, limit: 15);
    debugPrint('READALONG device voice reached ${r.position.value}');
    await r.stop();
  });
}

Future<void> _waitFor(WidgetTester tester, bool Function() done, {int limit = 10}) async {
  final until = DateTime.now().add(Duration(seconds: limit));
  while (!done()) {
    if (DateTime.now().isAfter(until)) fail('Timed out waiting');
    await Future<void>.delayed(sampleEvery);
    await tester.pump();
  }
}

/// Samples the player's clock against the word the reader marks. Lag is how far past a word's
/// start the player is when the reader is first seen marking it; an off sample is one where the
/// mark is not the word the player's position falls in, and its staleness is how long that word
/// has been playing unmarked.
Future<String> _measure(WidgetTester tester, ReadAlong r, Duration span) async {
  final player = r.debugPlayer!;
  final t = r.timings!;
  final lags = <int>[];
  var samples = 0;
  var mismatches = 0;
  var worst = 0;
  int? last;
  final clock = Stopwatch()..start();
  final startPos = player.position.inMilliseconds;
  while (clock.elapsed < span) {
    await Future<void>.delayed(sampleEvery);
    await tester.pump();
    final ms = player.position.inMilliseconds - r.offsetMs;
    final at = r.position.value;
    if (at == null || at.word == null) continue;
    final shown = t.indexOf(at.verse, at.word!)!;
    final truth = t.indexAt(ms);
    samples++;
    if (shown != truth) {
      mismatches++;
      worst = max(worst, truth == null ? 0 : ms - t.words[truth].startMs);
    }
    // The word already marked when sampling starts began before the window; it has no lag.
    if (shown != last && last != null) lags.add(ms - t.words[shown].startMs);
    last = shown;
  }
  final played = player.position.inMilliseconds - startPos;
  lags.sort();
  String pct(double p) => '${lags[((lags.length - 1) * p).round()]}';
  return '${lags.length} words, lag median ${pct(0.5)} ms, p95 ${pct(0.95)} ms, max '
      '${lags.last} ms, min ${lags.first} ms; $mismatches of $samples samples off (worst staleness '
      '$worst ms); player advanced $played ms in ${clock.elapsedMilliseconds} ms wall time';
}

/// The word the reader shows with the read-along background.
String? _markedWord(WidgetTester tester) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    String? found;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.style?.backgroundColor != null && span.text != null) {
        found = span.text;
        return false;
      }
      return true;
    });
    if (found != null) return found;
  }
  return null;
}
