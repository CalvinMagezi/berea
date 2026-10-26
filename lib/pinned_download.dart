import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// Streams [url] into [dest] and checks it against the published SHA-256, so what arrives is
/// exactly what was released. Stops past [maxBytes], so a wrong or hostile response can never
/// fill the disk. [dest] is left behind on failure; the caller owns cleaning it up.
Future<void> downloadPinned(
  Uri url,
  File dest, {
  required String sha256,
  required int maxBytes,
  required Duration timeout,
  void Function(double fraction)? onProgress,
}) async {
  final client = http.Client();
  final sink = dest.openWrite();
  final hash = Sha256().newHashSink();
  Object? failure;
  try {
    final r = await client.send(http.Request('GET', url)).timeout(timeout);
    if (r.statusCode != 200) throw HttpException('The download failed (HTTP ${r.statusCode}).');
    final total = r.contentLength;
    if ((total ?? 0) > maxBytes) throw const FormatException('The download is too large.');
    var received = 0;
    await for (final chunk in r.stream.timeout(timeout)) {
      received += chunk.length;
      if (received > maxBytes) throw const FormatException('The download is too large.');
      hash.add(chunk);
      sink.add(chunk);
      if (total != null && total > 0) onProgress?.call(received / total);
    }
    hash.close();
    if (hexOf((await hash.hash()).bytes) != sha256) {
      throw const FormatException('The download does not match the published file.');
    }
  } catch (e) {
    failure = e;
    rethrow;
  } finally {
    client.close();
    try {
      await sink.close();
    } on FileSystemException {
      // A failed close must not hide the error that stopped the download.
      if (failure == null) rethrow;
    }
  }
}

/// Room above a model's published size, so a response a little longer than expected fails on the
/// hash and not on the cap.
const modelSizeMargin = 1024 * 1024;

/// Whether [file] is the model pinned by [sha256]: the right size, and stamped with that hash
/// by [downloadModelFile] once it matched. A size alone cannot tell two builds of a model apart.
bool hostedModelCurrent(File file, {required String sha256, required int bytes}) {
  final stamp = File('${file.path}.sha256');
  return file.existsSync() &&
      file.lengthSync() == bytes &&
      stamp.existsSync() &&
      stamp.readAsStringSync().trim() == sha256;
}

/// Puts the pinned model file [name] into [dir] and returns it. The file appears there only once
/// its hash matches, and is stamped with that hash so a changed pin fetches it again. With
/// [recheck] a stamped file is hashed again first, and replaced if it no longer matches.
Future<File> downloadModelFile(
  Uri url,
  Directory dir,
  String name, {
  required String sha256,
  required int bytes,
  required Duration timeout,
  void Function(double fraction)? onProgress,
  bool recheck = false,
}) async {
  dir.createSync(recursive: true);
  final dest = File('${dir.path}/$name');
  final stamp = File('${dest.path}.sha256');
  if (hostedModelCurrent(dest, sha256: sha256, bytes: bytes)) {
    if (!recheck || await _hashMatches(dest, sha256)) return dest;
    stamp.deleteSync();
  }
  final part = File('${dest.path}.part');
  try {
    await downloadPinned(
      url,
      part,
      sha256: sha256,
      maxBytes: bytes + modelSizeMargin,
      timeout: timeout,
      onProgress: onProgress,
    );
    await part.rename(dest.path);
    stamp.writeAsStringSync(sha256);
  } finally {
    if (part.existsSync()) part.deleteSync();
  }
  return dest;
}

Future<bool> _hashMatches(File file, String sha256) async {
  final hash = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    hash.add(chunk);
  }
  hash.close();
  return hexOf((await hash.hash()).bytes) == sha256;
}

/// Puts [notice] in a NOTICE file beside the models, as the Gemma terms ask of every copy.
void writeModelNotice(Directory dir, String notice) {
  dir.createSync(recursive: true);
  final file = File('${dir.path}/NOTICE');
  if (!file.existsSync() || file.readAsStringSync().trim() != notice) {
    file.writeAsStringSync('$notice\n');
  }
}

String hexOf(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
