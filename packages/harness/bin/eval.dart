// Runs eval/golden.json through the harness. Exit 1 if any reference was invented.
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';

import 'berea.dart';

/// Unverified citations that only repeat the question's own bait are correct behaviour.
/// References compare as references, so "Psalms 151" matches the bait "Psalm 151".
bool _isBait(String citation, List<String> bait) {
  final c = CitationGuard.normalize(citation);
  final cRefs = RefParser.parse(citation);
  return bait.any((b) {
    final bRefs = RefParser.parse(b);
    if (cRefs.isNotEmpty && bRefs.isNotEmpty) return cRefs.any((r) => bRefs.any(r.overlaps));
    return c.contains(CitationGuard.normalize(b));
  });
}

final _negation = RegExp(
  r"\b(not|never|nowhere|isn't|doesn't|misquot\w*|popular saying)\b",
  caseSensitive: false,
);

/// A forbidden saying attributed to Scripture: it appears, without a denial, in the same sentence
/// as a real verse. Returns that sentence.
String? _misattributed(String text, List<String> forbid) {
  for (final sentence in text.split(RegExp(r'(?<=[.!?])\s+'))) {
    if (_negation.hasMatch(sentence)) continue;
    final s = CitationGuard.normalize(sentence);
    final hasRef = RefParser.parse(sentence).isNotEmpty;
    if (hasRef && forbid.any((f) => s.contains(CitationGuard.normalize(f)))) return sentence;
  }
  return null;
}

Future<void> main(List<String> args) async {
  final h = harnessFromArgs(args);
  final cases = (jsonDecode(File('eval/golden.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  var invented = 0, badQuotes = 0, expected = 0, covered = 0, misattributed = 0, adversarialOk = 0;
  var adversarial = 0, nearMisses = 0;
  final sw = Stopwatch()..start();
  for (final c in cases) {
    h.history.clear();
    final r = await h.ask(c['q'] as String);
    final want = [for (final s in (c['expect'] as List? ?? [])) ...RefParser.parse(s as String)];
    final bait = (c['bait'] as List? ?? []).cast<String>();
    final forbid = (c['forbid'] as List? ?? []).cast<String>();
    final hit = want.where((w) => r.guard.verified.any(w.overlaps)).length;
    final inventedHere = [
      ...r.guard.unverified.map((e) => e.label),
      ...r.guard.unknownBooks,
    ].where((x) => !_isBait(x, bait)).toList();
    final misSentence = forbid.isEmpty ? null : _misattributed(r.text, forbid);
    final misattr = misSentence != null;
    expected += want.length;
    covered += hit;
    invented += inventedHere.length;
    badQuotes += r.guard.unverifiedQuotes.length;
    nearMisses += r.guard.nearMisses.length;
    if (misattr) misattributed++;
    final ok = inventedHere.isEmpty && hit == want.length && !misattr;
    if (c['kind'] == 'adversarial') {
      adversarial++;
      if (ok) adversarialOk++;
    }
    stdout.writeln(
      '${ok ? 'ok ' : 'MISS'} ${c['q']}  expect ${want.length} got $hit'
      '${inventedHere.isEmpty ? '' : '  invented: ${inventedHere.join(', ')}'}'
      '${misattr ? '  misattributed: "${misSentence.trim()}"' : ''}'
      '${r.guard.unverifiedQuotes.isEmpty ? '' : '  bad quotes: ${r.guard.unverifiedQuotes.length}'}'
      '${r.guard.nearMisses.isEmpty ? '' : '  near misses: ${r.guard.nearMisses.join(', ')}'}',
    );
  }
  stdout.writeln(
    '\n${cases.length} cases in ${sw.elapsed.inSeconds}s on ${h.engine.name} tier ${h.tier.name}',
  );
  stdout.writeln(
    'invented refs: $invented | coverage: $covered/$expected | unverified quotes: $badQuotes'
    ' | misattributed sayings: $misattributed | adversarial passed: $adversarialOk/$adversarial'
    ' | near misses to review: $nearMisses',
  );
  h.db.close();
  exit(invented == 0 && misattributed == 0 ? 0 : 1);
}
