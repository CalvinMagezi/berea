// Interactive CLI against Ollama. Usage: dart run bin/berea.dart [--model gemma4:e2b] [--tier mid]
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';

const defaultDb = '../../assets/berea.sqlite';
const defaultPrompt = '../../prompts/system.md';

String systemPromptFrom(String path) {
  final raw = File(path).readAsStringSync();
  final i = raw.indexOf('\n---\n');
  return (i < 0 ? raw : raw.substring(i + 5)).trim();
}

Harness harnessFromArgs(List<String> args) {
  String opt(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final tier = Tier.values.byName(opt('tier', 'mid'));
  return Harness(
    db: BibleDb.open(opt('db', defaultDb)),
    engine: OllamaEngine(model: opt('model', 'gemma4:e2b'), numCtx: tier.contextWindow),
    systemPrompt: systemPromptFrom(opt('prompt', defaultPrompt)),
    tier: tier,
    translation: opt('translation', defaultTranslation),
    notebook: args.contains('--notebook'),
  );
}

Future<void> main(List<String> args) async {
  final h = harnessFromArgs(args);
  stdout.writeln('Berea (${h.engine.name}, tier ${h.tier.name}). Empty line to quit.');
  while (true) {
    stdout.write('\n> ');
    final line = stdin.readLineSync();
    if (line == null || line.trim().isEmpty) break;
    final sw = Stopwatch()..start();
    final r = await h.ask(line, onToken: stdout.write);
    final g = r.guard;
    stdout.writeln(
      '\n\n[${sw.elapsed.inSeconds}s] loaded: ${r.context.refs.map((e) => e.label).join(', ')}'
      ' | verified: ${g.verified.length}'
      ' | unverified refs: ${g.unverified.map((e) => e.label).join(', ')}'
      ' | unverified quotes: ${g.unverifiedQuotes.length}'
      ' | near misses: ${g.nearMisses.join(', ')}',
    );
  }
  h.db.close();
}
