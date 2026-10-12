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

const bytesPerMb = 1024 * 1024;

/// Size and SHA-256 of a file published on a data-only release, from that build's manifest.
class PackPin {
  final String sha256;
  final int bytes;
  const PackPin(this.sha256, this.bytes);

  String get sizeLabel => '${(bytes / bytesPerMb).round()} MB';
}

/// Progress is reported in whole percents, so a download redraws the app at most this often.
const _progressSteps = 100;

/// Wraps [onStep] so it runs only when progress reaches a new whole percent.
void Function(double fraction) wholePercents(void Function(double fraction) onStep) {
  var shown = 0;
  return (f) {
    final step = (f * _progressSteps).floor();
    if (step == shown) return;
    shown = step;
    onStep(f);
  };
}

const _gzipMagic = [0x1f, 0x8b];

/// Copies [from] to [to], gunzipping when it is gzipped, and stops past [maxBytes] so a
/// hostile file cannot fill the disk. Meant for `Isolate.run`, off the UI isolate.
Future<void> copyUnpacked(String from, String to, int maxBytes) async {
  final source = File(from);
  final head = await source.openRead(0, _gzipMagic.length).expand((b) => b).toList();
  final gzipped =
      head.length == _gzipMagic.length && head[0] == _gzipMagic[0] && head[1] == _gzipMagic[1];
  final data = gzipped ? source.openRead().transform(gzip.decoder) : source.openRead();
  final sink = File(to).openWrite();
  var written = 0;
  try {
    await for (final chunk in data) {
      written += chunk.length;
      if (written > maxBytes) throw const FormatException('That file is too large to be a pack.');
      sink.add(chunk);
    }
  } finally {
    await sink.close();
  }
}
