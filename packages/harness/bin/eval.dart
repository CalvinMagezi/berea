// Runs eval/golden.json through the harness, or with --notebook eval/notebook.json against a
// fixture notebook. Exit 1 if any reference or source citation was invented. Add
// --commentary <pack.sqlite> to let notebook answers draw on an installed commentary pack, and
// --show to print each notebook answer as the guard left it.
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';

import 'berea.dart';
import 'notebook_fixture.dart';

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

/// What the notebook rules ask a model to say when the sources do not cover a question.
final _notCovered = RegExp(
  r"(do|does|did)\s*(not|n't)\s+(cover|mention|say|contain|include|address|discuss)",
  caseSensitive: false,
);

final _locatorWords = RegExp(r'\b(pp?|pages?|sec|sections?)\b');

/// "S3 p.7", "S3 page 7" and "S3 §7" all read "s3 7", so a tag echoing the bait matches it.
String _tagKey(String tag) =>
    CitationGuard.normalize(tag).replaceAll(_locatorWords, ' ').replaceAll(RegExp(r'\s+'), ' ');

List<String> _strings(Map<String, dynamic> c, String key) =>
    (c[key] as List? ?? const []).cast<String>();

List<Map<String, dynamic>> _cases(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List).cast<Map<String, dynamic>>();

Future<void> main(List<String> args) async {
  final h = harnessFromArgs(args);
  final ok = h.notebook ? await _notebook(h, args) : await _golden(h);
  h.db.close();
  exit(ok ? 0 : 1);
}

Future<bool> _golden(Harness h) async {
  final cases = _cases('eval/golden.json');
  var invented = 0, badQuotes = 0, expected = 0, covered = 0, misattributed = 0, adversarialOk = 0;
  var adversarial = 0, nearMisses = 0;
  final sw = Stopwatch()..start();
  for (final c in cases) {
    h.history.clear();
    final r = await h.ask(c['q'] as String);
    final want = [for (final s in _strings(c, 'expect')) ...RefParser.parse(s)];
    final bait = _strings(c, 'bait');
    final forbid = _strings(c, 'forbid');
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
  return invented == 0 && misattributed == 0;
}

Future<bool> _notebook(Harness h, List<String> args) async {
  final cases = _cases('eval/notebook.json');
  final index = fixtureNotebook(h.db);
  final packAt = args.indexOf('--commentary');
  final library = CommentaryLibrary();
  if (packAt >= 0 && packAt + 1 < args.length && !library.open('eval', args[packAt + 1])) {
    stderr.writeln('Not a commentary pack: ${args[packAt + 1]}');
    return false;
  }
  var invented = 0, inventedSources = 0, badQuotes = 0, misattributed = 0;
  var expected = 0, covered = 0, wantSources = 0, citedSources = 0;
  var adversarial = 0, adversarialOk = 0;
  final sw = Stopwatch()..start();
  for (final c in cases) {
    h.history.clear();
    final q = c['q'] as String;
    final sources = notebookSources(index: index, question: q, tier: h.tier, commentary: library);
    final r = await h.ask(q, sources: sources);
    final g = r.guard;
    final want = [for (final s in _strings(c, 'expect')) ...RefParser.parse(s)];
    final hit = want.where((w) => g.verified.any(w.overlaps)).length;
    final cited = {for (final s in g.sources) s.tag.split(' ').first};
    final wantedSources = _strings(c, 'sources');
    final sourceHits = wantedSources.where(cited.contains).length;
    final inventedHere = [
      ...g.unverified.map((e) => e.label),
      ...g.unknownBooks,
    ].where((x) => !_isBait(x, _strings(c, 'bait'))).toList();
    final sourceBait = {for (final b in _strings(c, 'sourceBait')) _tagKey(b)};
    final inventedSourcesHere = [
      for (final s in g.unverifiedSources)
        if (!sourceBait.contains(_tagKey(s))) s,
    ];
    final forbid = _strings(c, 'forbid');
    final misSentence = forbid.isEmpty ? null : _misattributed(r.text, forbid);
    final coverageOk = c['notCovered'] != true || g.sources.isEmpty || _notCovered.hasMatch(r.text);
    expected += want.length;
    covered += hit;
    wantSources += wantedSources.length;
    citedSources += sourceHits;
    invented += inventedHere.length;
    inventedSources += inventedSourcesHere.length;
    badQuotes += g.unverifiedQuotes.length;
    if (misSentence != null) misattributed++;
    final ok =
        inventedHere.isEmpty &&
        inventedSourcesHere.isEmpty &&
        misSentence == null &&
        coverageOk &&
        hit == want.length &&
        sourceHits == wantedSources.length;
    if (c['kind'] == 'adversarial') {
      adversarial++;
      if (ok) adversarialOk++;
    }
    stdout.writeln(
      '${ok ? 'ok ' : 'MISS'} $q  refs $hit/${want.length} sources $sourceHits/'
      '${wantedSources.length} shown ${r.context.sources.length} cited ${g.sources.map((s) => s.tag).join(', ')}'
      '${inventedHere.isEmpty ? '' : '  invented: ${inventedHere.join(', ')}'}'
      '${g.unverifiedSources.isEmpty ? '' : '  unverified sources: ${g.unverifiedSources.join(', ')}'}'
      '${misSentence == null ? '' : '  misattributed: "${misSentence.trim()}"'}'
      '${coverageOk ? '' : '  claimed coverage the notebook lacks'}'
      '${g.unverifiedQuotes.isEmpty ? '' : '  bad quotes: ${g.unverifiedQuotes.length}'}',
    );
    if (args.contains('--show')) stdout.writeln('    ${r.text.replaceAll('\n', '\n    ')}\n');
  }
  library.closeAll();
  index.db.dispose();
  stdout.writeln(
    '\n${cases.length} notebook cases in ${sw.elapsed.inSeconds}s on ${h.engine.name} tier '
    '${h.tier.name}',
  );
  stdout.writeln(
    'invented refs: $invented | invented source citations: $inventedSources | verse coverage: '
    '$covered/$expected | source coverage: $citedSources/$wantSources | unverified quotes: '
    '$badQuotes | misattributed sayings: $misattributed | adversarial passed: '
    '$adversarialOk/$adversarial',
  );
  return invented == 0 && inventedSources == 0 && misattributed == 0;
}
