import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:berea_harness/berea_harness.dart';

import 'pinned_download.dart';

/// Packs are published gzipped on a data-only release, pinned by tag and by hash, so what
/// arrives is exactly what `bin/build_commentary.dart` produced.
const commentaryReleaseUrl = 'https://github.com/CalvinMagezi/berea/releases/download/commentary-1';

/// Size and SHA-256 of each published `.gz` file, from build/commentary/manifest.json.
class PackPin {
  final String sha256;
  final int bytes;
  const PackPin(this.sha256, this.bytes);

  String get sizeLabel => '${(bytes / bytesPerMb).round()} MB';
}

const bytesPerMb = 1024 * 1024;

const commentaryPins = <String, PackPin>{
  'core': PackPin('a8013704eedc58e28c7f5305c51752c626855b8fc718a04e4f4b748c2b1eff5c', 19984091),
  'mhc': PackPin('31189ae6f3f4cfbdbfada315603defcb73c09234e50c6acfb9536cbdca40c3e0', 25536620),
  'clarke': PackPin('658a0928f5d676b01190a829eed6ee90fd1d4120e0d821924bdf51cbe6660d7e', 15215716),
  'calvin': PackPin('7590864d8ae89441277d5906372c6c3701354f2967939875642f1888d11ab93d', 26535568),
  'kd': PackPin('10223ab9ca957d592657a1e9e3040c9ce26b8a2f0d30fb9c61c72e566a91d1b3', 18180887),
  'barnes': PackPin('2b28dbaae0f0b42fd844507c2887d619bb8db3a06d962b7e015df2cebf60b663', 10200748),
  'wesley': PackPin('5ec8f565204d684454a2f0f1c1f092a0f5afb4af0bc8f114f8d4d0bafaee9bfc', 3864925),
  'tdavid': PackPin('85f3d13bfbdb6cf4cdb169e98610320df65148f83809d06af24759fca2612076', 8826308),
};

/// Unpacked size cap for a pack picked from a file; the largest published pack is under 64 MB.
const maxCommentaryPackBytes = 160 * bytesPerMb;
const commentaryDownloadTimeout = Duration(minutes: 10);

/// The installed commentary packs, one SQLite file each under the app's support folder.
/// Downloads happen only when the user asks.
class CommentaryShelf {
  final Directory dir;
  final void Function() onChange;
  final library = CommentaryLibrary();

  /// Download progress from 0 to 1 for packs being fetched.
  final progress = <String, double>{};

  CommentaryShelf(this.dir, this.onChange) {
    dir.createSync(recursive: true);
    for (final spec in commentaryPackSpecs) {
      library.open(spec.id, _path(spec));
    }
  }

  String _path(CommentaryPackSpec spec) => '${dir.path}/${spec.fileName}';

  bool isInstalled(String id) => library.installed.contains(id);

  Future<void> download(CommentaryPackSpec spec) async {
    final pin = commentaryPins[spec.id];
    if (pin == null) throw StateError('No published pack for ${spec.id}.');
    final gz = File('${_path(spec)}.gz.part');
    progress[spec.id] = 0;
    onChange();
    try {
      await downloadPinned(
        Uri.parse('$commentaryReleaseUrl/${spec.fileName}.gz'),
        gz,
        sha256: pin.sha256,
        maxBytes: pin.bytes,
        timeout: commentaryDownloadTimeout,
        onProgress: (f) {
          progress[spec.id] = f;
          onChange();
        },
      );
      await _install(gz, expectedId: spec.id);
    } finally {
      progress.remove(spec.id);
      if (gz.existsSync()) gz.deleteSync();
      onChange();
    }
  }

  /// Installs a pack the user picked, gzipped or not, and returns its title. The file is
  /// checked before it replaces anything; a pack names its own id, so it lands in its place.
  Future<String> installFromFile(String path) async {
    final spec = await _install(File(path));
    onChange();
    return spec.title;
  }

  Future<CommentaryPackSpec> _install(File source, {String? expectedId}) async {
    final tmp = File('${dir.path}/incoming.sqlite.part');
    CommentaryPackSpec? spec;
    try {
      await Isolate.run(() => _unpack(source.path, tmp.path, maxCommentaryPackBytes));
      final id = CommentaryLibrary.packIdOf(tmp.path);
      spec = commentaryPackSpecs.where((s) => s.id == id).firstOrNull;
      if (spec == null || (expectedId != null && spec.id != expectedId)) {
        throw const FormatException('That file is not a Berea commentary pack.');
      }
      // The open pack holds its file; let go of it before replacing it.
      library.close(spec.id);
      tmp.renameSync(_path(spec));
      return spec;
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
      if (spec != null) library.open(spec.id, _path(spec));
    }
  }

  void delete(CommentaryPackSpec spec) {
    library.close(spec.id);
    final f = File(_path(spec));
    if (f.existsSync()) f.deleteSync();
    onChange();
  }
}

const _gzipMagic = [0x1f, 0x8b];

/// Copies [from] to [to], gunzipping when it is gzipped, and stops past [maxBytes] so a
/// hostile file cannot fill the disk. Runs off the UI isolate.
Future<void> _unpack(String from, String to, int maxBytes) async {
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
