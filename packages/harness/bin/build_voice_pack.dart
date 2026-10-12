// Fetches the optional voice pack's files from their pinned upstream sources, checks each
// against its SHA-256, and writes them unchanged to build/voice with a manifest.json, ready to
// publish on the voice-1 release.
// Usage: dart run bin/build_voice_pack.dart [--out ../../build/voice] [--cache .cache/voice]
import 'dart:io';

import 'package:berea_harness/src/source_checks.dart';
import 'package:berea_harness/src/voice_pack.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  var out = '../../build/voice';
  var cache = '.cache/voice';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--out') out = args[i + 1];
    if (args[i] == '--cache') cache = args[i + 1];
  }
  Directory(out).createSync(recursive: true);
  Directory(cache).createSync(recursive: true);
  for (final f in voicePackFiles) {
    final bytes = await _fetch(f, '$cache/${f.name}');
    checkPin(bytes, f.sha256, source: f.upstream);
    if (bytes.length != f.bytes) {
      throw StateError('${f.name} is ${bytes.length} bytes, pinned ${f.bytes}.');
    }
    File('$out/${f.name}').writeAsBytesSync(bytes);
    stdout.writeln('${f.sha256}  ${f.bytes}  ${f.name}');
  }
  File('$out/manifest.json').writeAsStringSync(voicePackManifestJson());
  stdout.writeln('wrote $out/manifest.json');
}

Future<List<int>> _fetch(VoicePackFile f, String cached) async {
  final file = File(cached);
  if (file.existsSync() && file.lengthSync() == f.bytes) return file.readAsBytesSync();
  stdout.writeln('fetching ${f.upstream}');
  final r = await http.get(Uri.parse(f.upstream));
  if (r.statusCode != HttpStatus.ok) {
    throw StateError('HTTP ${r.statusCode} for ${f.upstream}');
  }
  file.writeAsBytesSync(r.bodyBytes);
  return r.bodyBytes;
}
