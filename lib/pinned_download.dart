import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// Hears the bytes received so far and the size the server gave, if it gave one.
typedef ByteProgress = void Function(int received, int? total);

/// Thrown when a download ends because [downloadPinned]'s `stop` completed.
class DownloadStopped implements Exception {
  const DownloadStopped();

  @override
  String toString() => 'The download was stopped.';
}

/// Streams [url] into [dest] and checks it against the published SHA-256, so what arrives is
/// exactly what was released. Stops past [maxBytes], so a wrong or hostile response can never
/// fill the disk, and throws [DownloadStopped] once [stop] completes. [dest] is left behind on
/// failure; the caller owns cleaning it up.
Future<void> downloadPinned(
  Uri url,
  File dest, {
  required String sha256,
  required int maxBytes,
  required Duration timeout,
  ByteProgress? onProgress,
  Future<void>? stop,
}) async {
  final client = http.Client();
  var stopped = false;
  // An abort ends the response stream at once, even mid-stall.
  final abort = stop?.then((_) => stopped = true);
  final sink = dest.openWrite();
  final hash = Sha256().newHashSink();
  Object? failure;
  try {
    if (stopped) throw const DownloadStopped();
    final r = await client
        .send(http.AbortableRequest('GET', url, abortTrigger: abort))
        .timeout(timeout);
    if (r.statusCode != 200) throw HttpException('The download failed (HTTP ${r.statusCode}).');
    final total = r.contentLength;
    if ((total ?? 0) > maxBytes) throw const FormatException('The download is too large.');
    var received = 0;
    await for (final chunk in r.stream.timeout(timeout)) {
      received += chunk.length;
      if (received > maxBytes) throw const FormatException('The download is too large.');
      hash.add(chunk);
      sink.add(chunk);
      onProgress?.call(received, total);
    }
    if (stopped) throw const DownloadStopped();
    hash.close();
    if (hexOf((await hash.hash()).bytes) != sha256) {
      throw const FormatException('The download does not match the published file.');
    }
  } catch (e) {
    failure = e;
    if (stopped) throw const DownloadStopped();
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

/// Thrown when a model file arrives the wrong size or with the wrong hash; the partial file is
/// removed with it, so the next try starts fresh.
class DownloadDamaged extends FormatException {
  const DownloadDamaged(super.message);
}

/// What a partial download was fetched against, kept beside it so a resume asks for the same file.
class _PartMeta {
  final String url;
  final String? etag;
  final String? lastModified;
  final int? total;
  const _PartMeta({required this.url, this.etag, this.lastModified, this.total});

  factory _PartMeta.of(Uri url, http.StreamedResponse r, int? total) => _PartMeta(
    url: url.toString(),
    etag: r.headers['etag'],
    lastModified: r.headers['last-modified'],
    total: total,
  );

  static _PartMeta? read(File file) {
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return _PartMeta(
        url: j['url'] as String,
        etag: j['etag'] as String?,
        lastModified: j['lastModified'] as String?,
        total: j['total'] as int?,
      );
    } on Object {
      return null;
    }
  }

  void write(File file) => file.writeAsStringSync(
    jsonEncode({'url': url, 'etag': etag, 'lastModified': lastModified, 'total': total}),
  );

  /// If-Range takes a strong ETag or a date; a weak ETag cannot promise the same bytes.
  String? get validator => etag != null && !etag!.startsWith('W/') ? etag : lastModified;
}

File _partOf(Directory dir, String name) => File('${dir.path}/$name.part');
File _metaOf(File part) => File('${part.path}.json');

/// The bytes of [name] already in [dir] from a stopped download, and the size it is heading
/// for. Null when there is nothing a resume could continue from.
({int bytes, int? total})? partialDownload(Directory dir, String name) {
  final part = _partOf(dir, name);
  final meta = _PartMeta.read(_metaOf(part));
  if (meta == null || !part.existsSync()) return null;
  return (bytes: part.lengthSync(), total: meta.total);
}

/// Removes what a stopped download of [name] left in [dir], as Cancel asks.
void discardPartial(Directory dir, String name) => _discard(_partOf(dir, name));

void _discard(File part) {
  for (final f in [part, _metaOf(part)]) {
    if (f.existsSync()) f.deleteSync();
  }
}

/// Puts the pinned model file [name] into [dir] and returns it. The file appears there only once
/// its size and hash match, and is stamped with that hash so a changed pin fetches it again. With
/// [recheck] a stamped file is hashed again first, and replaced if it no longer matches. A stopped
/// or broken download keeps its partial file, and the next call continues it with a Range request.
Future<File> downloadModelFile(
  Uri url,
  Directory dir,
  String name, {
  required String sha256,
  required int bytes,
  required Duration timeout,
  ByteProgress? onProgress,
  Future<void>? stop,
  bool recheck = false,
}) async {
  dir.createSync(recursive: true);
  var stopped = false;
  unawaited(stop?.then((_) => stopped = true));
  final dest = File('${dir.path}/$name');
  final stamp = File('${dest.path}.sha256');
  if (hostedModelCurrent(dest, sha256: sha256, bytes: bytes)) {
    if (!recheck || await _hashMatches(dest, sha256)) return dest;
    stamp.deleteSync();
  }
  final part = _partOf(dir, name);
  try {
    await _fetchResumable(
      url,
      part,
      maxBytes: bytes + modelSizeMargin,
      timeout: timeout,
      onProgress: onProgress,
      stop: stop,
    );
    if (part.lengthSync() != bytes) {
      throw const DownloadDamaged('The download is not the size of the published file.');
    }
    if (!await hashCheck(part, sha256)) {
      throw const DownloadDamaged('The download does not match the published file.');
    }
    // Pause or Cancel while the last bytes were checked still wins: the part stays a part.
    if (stopped) throw const DownloadStopped();
  } on DownloadDamaged {
    _discard(part);
    rethrow;
  }
  await part.rename(dest.path);
  _discard(part);
  stamp.writeAsStringSync(sha256);
  return dest;
}

/// Streams [url] onto the end of [part], asking only for the bytes it lacks. A server that
/// ignores the Range, or a file that changed since the part began, starts the part again.
Future<void> _fetchResumable(
  Uri url,
  File part, {
  required int maxBytes,
  required Duration timeout,
  ByteProgress? onProgress,
  Future<void>? stop,
}) async {
  final client = http.Client();
  var stopped = false;
  // An abort ends the response stream at once, even mid-stall.
  final abort = stop?.then((_) => stopped = true);
  try {
    // A second try asks for the whole file, so it cannot be turned down again.
    for (var fresh = false; ; fresh = true) {
      final meta = fresh ? null : _resumable(part, url, maxBytes);
      if (meta == null) _discard(part);
      final from = meta == null ? 0 : part.lengthSync();
      final request = http.AbortableRequest('GET', url, abortTrigger: abort);
      if (from > 0) {
        request.headers['range'] = 'bytes=$from-';
        if (meta!.validator case final v?) request.headers['if-range'] = v;
      }
      if (stopped) throw const DownloadStopped();
      final r = await client.send(request).timeout(timeout);
      final whole = r.statusCode == HttpStatus.ok;
      final refused = r.statusCode == HttpStatus.requestedRangeNotSatisfiable;
      if (!whole && !refused && r.statusCode != HttpStatus.partialContent) {
        throw HttpException('The download failed (HTTP ${r.statusCode}).');
      }
      if (refused && meta != null && from == meta.total) {
        // The app closed after the last byte and before the file was checked.
        await r.stream.listen(null).cancel();
        return;
      }
      if (!whole && (refused || meta == null || !_continues(r, from, meta))) {
        // Cancelled, not drained: the refused body can be the whole file.
        await r.stream.listen(null).cancel();
        if (fresh) throw const HttpException('The download could not continue.');
        continue;
      }
      final total = whole ? r.contentLength : meta!.total;
      if (whole) _PartMeta.of(url, r, total).write(_metaOf(part));
      await _append(r, part, whole ? 0 : from, total, maxBytes, timeout, onProgress);
      if (stopped) throw const DownloadStopped();
      return;
    }
  } catch (e) {
    if (stopped) throw const DownloadStopped();
    rethrow;
  } finally {
    client.close();
  }
}

/// The meta of a part a resume can continue; null when the part must start again.
_PartMeta? _resumable(File part, Uri url, int maxBytes) {
  if (!part.existsSync()) return null;
  final meta = _PartMeta.read(_metaOf(part));
  if (meta == null || meta.url != url.toString()) return null;
  final length = part.lengthSync();
  return length == 0 || length > maxBytes ? null : meta;
}

final _contentRange = RegExp(r'^bytes (\d+)-\d+/(\d+|\*)$');

/// Whether the 206 [r] carries the rest of the part begun under [meta]: it starts at [from],
/// and its total and ETag are the ones the part began with.
bool _continues(http.StreamedResponse r, int from, _PartMeta meta) {
  final m = _contentRange.firstMatch(r.headers['content-range'] ?? '');
  if (m == null || int.parse(m.group(1)!) != from) return false;
  final etag = r.headers['etag'];
  if (etag != null && meta.etag != null && etag != meta.etag) return false;
  return meta.total == null || int.tryParse(m.group(2)!) == meta.total;
}

Future<void> _append(
  http.StreamedResponse r,
  File part,
  int start,
  int? total,
  int maxBytes,
  Duration timeout,
  ByteProgress? onProgress,
) async {
  if ((total ?? 0) > maxBytes) throw const DownloadDamaged('The download is too large.');
  final sink = part.openWrite(mode: start == 0 ? FileMode.write : FileMode.append);
  Object? failure;
  try {
    var received = start;
    await for (final chunk in r.stream.timeout(timeout)) {
      received += chunk.length;
      if (received > maxBytes) throw const DownloadDamaged('The download is too large.');
      sink.add(chunk);
      onProgress?.call(received, total);
    }
  } catch (e) {
    failure = e;
    rethrow;
  } finally {
    try {
      await sink.close();
    } on FileSystemException {
      // A failed close must not hide the error that stopped the download.
      if (failure == null) rethrow;
    }
  }
}

/// Hashes the file away from the UI isolate: a model is hundreds of megabytes.
/// Whether a file's hash is the pinned one; tests replace it to act while the hash runs.
Future<bool> Function(File file, String sha256) hashCheck = _hashMatches;

Future<bool> _hashMatches(File file, String sha256) => Isolate.run(() async {
  final hash = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    hash.add(chunk);
  }
  hash.close();
  return hexOf((await hash.hash()).bytes) == sha256;
});

/// Puts [notice] in a NOTICE file beside the models, as the Gemma terms ask of every copy.
void writeModelNotice(Directory dir, String notice) {
  dir.createSync(recursive: true);
  final file = File('${dir.path}/NOTICE');
  if (!file.existsSync() || file.readAsStringSync().trim() != notice) {
    file.writeAsStringSync('$notice\n');
  }
}

String hexOf(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
