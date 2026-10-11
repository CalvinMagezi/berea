// Runs eval/golden.json through the harness. Exit 1 if any reference was invented.
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';

import 'berea.dart';

Future<void> main(List<String> args) async {
  final h = harnessFromArgs(args);
  final cases = (jsonDecode(File('eval/golden.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  var invented = 0, badQuotes = 0, expected = 0, covered = 0;
  final sw = Stopwatch()..start();
  for (final c in cases) {
    h.history.clear();
    final r = await h.ask(c['q'] as String);
    final want = [for (final s in (c['expect'] as List? ?? [])) ...RefParser.parse(s as String)];
    final hit = want.where((w) => r.guard.verified.any(w.overlaps)).length;
    expected += want.length;
    covered += hit;
    invented += r.guard.unverified.length;
    badQuotes += r.guard.unverifiedQuotes.length;
    final flag = r.guard.unverified.isEmpty && hit == want.length ? 'ok ' : 'MISS';
    stdout.writeln(
      '$flag ${c['q']}  expect ${want.length} got $hit'
      '${r.guard.unverified.isEmpty ? '' : '  invented: ${r.guard.unverified.join(', ')}'}'
      '${r.guard.unverifiedQuotes.isEmpty ? '' : '  bad quotes: ${r.guard.unverifiedQuotes.length}'}',
    );
  }
  stdout.writeln(
    '\n${cases.length} cases in ${sw.elapsed.inSeconds}s on ${h.engine.name} tier ${h.tier.name}',
  );
  stdout.writeln(
    'invented refs: $invented | coverage: $covered/$expected | unverified quotes: $badQuotes',
  );
  h.db.close();
  exit(invented == 0 ? 0 : 1);
}
