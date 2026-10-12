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
    File('$out/${f.name}').writeAsBytesSync(bytes);
    stdout.writeln('${f.sha256}  ${f.bytes}  ${f.name}');
  }
  File('$out/manifest.json').writeAsStringSync(voicePackManifestJson());
  stdout.writeln('wrote $out/manifest.json');
}

Future<List<int>> _fetch(VoicePackFile f, String cached) async {
  final file = File(cached);
  if (file.existsSync()) {
    final bytes = file.readAsBytesSync();
    if (_matches(bytes, f)) return bytes;
    file.deleteSync();
  }
  stdout.writeln('fetching ${f.upstream}');
  final r = await http.get(Uri.parse(f.upstream));
  if (r.statusCode != HttpStatus.ok) {
    throw StateError('HTTP ${r.statusCode} for ${f.upstream}');
  }
  // Checked before caching, so a bad download never sticks in the cache.
  checkPin(r.bodyBytes, f.sha256, source: f.upstream);
  if (r.bodyBytes.length != f.bytes) {
    throw StateError('${f.name} is ${r.bodyBytes.length} bytes, pinned ${f.bytes}.');
  }
  file.writeAsBytesSync(r.bodyBytes);
  return r.bodyBytes;
}

bool _matches(List<int> bytes, VoicePackFile f) {
  if (bytes.length != f.bytes) return false;
  try {
    checkPin(bytes, f.sha256, source: f.name);
    return true;
  } on StateError {
    return false;
  }
}
