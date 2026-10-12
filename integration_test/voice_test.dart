// Drives the real voice on a desktop build: installs the pack from files, speaks John 3:16 in
// each voice on the Test voice screen while checking the highlight against the audio clock, and
// runs the benchmark. Needs the voice pack files (from bin/build_voice_pack.dart) in
// voice-src under the app's documents folder; on a sandboxed Mac that is
// ~/Library/Containers/com.magezi.berea/Data/Documents/voice-src.
// Run: flutter test integration_test/voice_test.dart -d macos
import 'dart:io';

import 'package:berea/app_state.dart';
import 'package:berea/attributions_screen.dart';
import 'package:berea/commentary_packs.dart' show bytesPerMb;
import 'package:berea/edge_engine.dart';
import 'package:berea/models.dart';
import 'package:berea/voice_settings.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _poll = Duration(milliseconds: 40);
const _leakToleranceMb = 300;
const _synthesisLimit = Duration(minutes: 2);

/// How far apart the highlight's offsets from the timings may drift over one verse. The offset
/// itself includes the player's start-up latency, which is constant across the verse.
const _driftToleranceMs = 150;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the licence page carries the voice notices in full', (tester) async {
    registerBundledLicences();
    final names = {
      await for (final l in LicenseRegistry.licenses)
        if (l.paragraphs.isNotEmpty) ...l.packages,
    };
    expect(names, containsAll(['CMU Pronouncing Dictionary', 'ONNX Runtime third party notices']));
  });

  // ONNX Runtime needs statically linked pods; the on-device LLM plugin must still start.
  testWidgets('the on-device language model plugin still initialises', (tester) async {
    expect(await EdgeAiEngine.isInstalled(edgeModels.first), isA<bool>());
  });

  testWidgets('installs the voice from files, speaks with live highlighting, benchmarks', (
    tester,
  ) async {
    final state = await AppState.bootstrap();
    final src = Directory('${(await getApplicationDocumentsDirectory()).path}/voice-src');
    if (!state.voice.installed) {
      final added = await state.voice.installFromFiles([
        for (final f in src.listSync().whereType<File>()) f.path,
      ]);
      debugPrint('installed from files: $added');
    }
    expect(state.voice.installed, isTrue, reason: 'Put the voice pack files in ${src.path}');

    await tester.pumpWidget(MaterialApp(home: VoiceTestScreen(state: state)));
    final verse = state.db
        .passage(Ref(bookFor('John')!, 3, 16), translation: state.settings.translation)
        .map((v) => v.text)
        .join(' ');

    // First, so its memory figures start from a freshly launched app.
    await tester.tap(find.text('Benchmark'));
    await _until(tester, () => _status(tester)?.startsWith('Running') ?? false);
    await _until(tester, () => _status(tester)?.contains('Memory:') ?? false);

    // Loading and closing again must not keep adding memory.
    final closed = <int>[];
    for (var i = 0; i < 3; i++) {
      await state.withVoice((v) => v.speak(verse, kokoroSpeakers.first));
      closed.add(ProcessInfo.currentRss ~/ bytesPerMb);
    }
    debugPrint('RSS after each close: $closed MB');
    expect(closed.last - closed.first, lessThan(_leakToleranceMb));

    for (final speaker in kokoroSpeakers) {
      final expected = await state.withVoice((v) => v.speak(verse, speaker));
      debugPrint(
        'direct ${speaker.id}: ${expected.words.length} words, ${expected.duration} audio, '
        'RTF ${expected.realTimeFactor.toStringAsFixed(3)}',
      );
      await tester.tap(find.text(speaker.label));
      await _until(tester, () => _status(tester)?.startsWith(speaker.label) ?? false);
      final started = DateTime.now();
      debugPrint(_status(tester));
      final lags = <int>[];
      var seen = <int>{};
      final end = expected.duration + const Duration(milliseconds: 500);
      while (DateTime.now().difference(started) < end) {
        await Future<void>.delayed(_poll);
        await tester.pump();
        final at = _highlightStart(tester);
        if (at == null) continue;
        final i = expected.words.indexWhere((w) => w.sourceStart == at);
        expect(i, isNonNegative);
        if (!seen.add(i)) continue;
        // The first moment a word lights, against when the audio clock says it starts.
        lags.add(DateTime.now().difference(started).inMilliseconds - expected.words[i].startMs);
      }
      lags.sort();
      final median = lags[lags.length ~/ 2];
      debugPrint(
        '${speaker.id}: lit ${seen.length} of ${expected.words.length} words, '
        'offset from word timings median $median ms, range ${lags.first}..${lags.last} ms',
      );
      expect(seen.length, greaterThan(expected.words.length * 3 ~/ 4));
      expect(lags.last - lags.first, lessThan(_driftToleranceMs));
      await _until(tester, () => _highlightStart(tester) == null);
      seen = {};
    }
  });
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(_synthesisLimit);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out. Status: ${_status(tester)}');
    await Future<void>.delayed(_poll);
    await tester.pump();
  }
}

String? _status(WidgetTester tester) {
  final f = find.byType(SelectableText);
  return f.evaluate().isEmpty ? null : tester.widget<SelectableText>(f).data;
}

/// Source offset of the lit word in the verse, or null when nothing is lit.
int? _highlightStart(WidgetTester tester) {
  final rich = tester.widget<Text>(find.byWidgetPredicate((w) => w is Text && w.textSpan != null));
  var offset = 0;
  for (final span in (rich.textSpan! as TextSpan).children!.cast<TextSpan>()) {
    if (span.style?.backgroundColor != null) return offset;
    offset += span.text!.length;
  }
  return null;
}
