// Prints the Kokoro phonemes, token ids and word spans for some text, so a pronunciation can be
// checked or fed to the model outside the app.
// Usage: dart run bin/phonemize.dart --lexicon ../../build/voice/cmudict.dict "Text to say"
import 'dart:convert';
import 'dart:io';

import 'package:berea_harness/berea_harness.dart';

void main(List<String> args) {
  var lexicon = '../../build/voice/$cmudictFile';
  final words = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--lexicon' && i + 1 < args.length) {
      lexicon = args[++i];
    } else {
      words.add(args[i]);
    }
  }
  final p = Phonemizer(Lexicon.parseCmudict(File(lexicon).readAsStringSync()));
  final out = [
    for (final u in p.utterances(words.join(' ')))
      {
        'phonemes': u.phonemes,
        'ids': u.inputIds,
        'words': [
          for (var w = 0; w < u.words.length; w++)
            {
              'word': u.words[w].text,
              'tokens': [u.tokenSpans[w].$1, u.tokenSpans[w].$2],
            },
        ],
      },
  ];
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
