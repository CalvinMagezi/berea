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

String hexOf(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
