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
  /// The hash of the published `.gz` file, and of the SQLite file inside it. The second lets a
  /// pack passed from one phone to another, in either form, be checked with no network.
  final String sha256;
  final int bytes;
  final String unpackedSha256;
  const PackPin(this.sha256, this.bytes, this.unpackedSha256);

  String get sizeLabel => '${(bytes / bytesPerMb).round()} MB';
}

const bytesPerMb = 1024 * 1024;

/// Whether an installed pack must match the hash Berea published for it. Tests that install packs
/// they built themselves turn it off.
bool verifyCommentaryPacks = true;

const commentaryPins = <String, PackPin>{
  'core': PackPin('a8013704eedc58e28c7f5305c51752c626855b8fc718a04e4f4b748c2b1eff5c', 19984091, '08e7a844cfd82b9588a80c4d2eda1da5b4997509af58b9ac242e6711c7613f38'),
  'mhc': PackPin('31189ae6f3f4cfbdbfada315603defcb73c09234e50c6acfb9536cbdca40c3e0', 25536620, 'a95116e753483e7a77b12481ff7a0dab59abf59adbf1d89b559666bdfb79e2d6'),
  'clarke': PackPin('658a0928f5d676b01190a829eed6ee90fd1d4120e0d821924bdf51cbe6660d7e', 15215716, '22affb07d89ce5f4968fcd56db3c4fbb27c5929c3c2f010881bd0f1834dbede9'),
  'calvin': PackPin('7590864d8ae89441277d5906372c6c3701354f2967939875642f1888d11ab93d', 26535568, 'e2a17a1cc3eae507cd06bbb66c804ff927c03d0b64e2403c210604e6595e3998'),
  'kd': PackPin('10223ab9ca957d592657a1e9e3040c9ce26b8a2f0d30fb9c61c72e566a91d1b3', 18180887, '7e66025ead509c7700063da5147030f3e261b140c2f177be29ff73b7845c3204'),
  'barnes': PackPin('2b28dbaae0f0b42fd844507c2887d619bb8db3a06d962b7e015df2cebf60b663', 10200748, 'ba7dda31e7212cd294df4903c6199b02fa8a6f25fda1ed8ac3c7bc0c13dc4d1c'),
  'wesley': PackPin('dca59c30ff37ce9b7ae0805e8d1fdbc5cb50531326d9a79fef79e60912fe69ef', 3841717, '04587a55135d23e5abf0aa3c55b27f342a67eeed14247c8f1b28aeae8b556dfa'),
  'tdavid': PackPin('85f3d13bfbdb6cf4cdb169e98610320df65148f83809d06af24759fca2612076', 8826308, 'cdd371759b041129c3ac9126f6ee5153f7369553e8ad3b78e3c630374a2631c2'),
};

/// Unpacked size cap for a pack picked from a file; the largest published pack is under 64 MB.
const maxCommentaryPackBytes = 160 * bytesPerMb;
const commentaryDownloadTimeout = Duration(minutes: 10);

/// Progress is reported in whole percents, so a download redraws the app at most this often.
const _progressSteps = 100;

/// The installed commentary packs, one SQLite file each under the app's support folder.
/// Downloads happen only when the user asks.
class CommentaryShelf {
  final Directory dir;
  final void Function() onChange;

  /// Unpacked size cap for any pack this shelf installs.
  final int maxPackBytes;
  final library = CommentaryLibrary();

  /// Download progress from 0 to 1 for packs being fetched.
  final progress = <String, double>{};

  /// Numbers each install's temporary file, so two installs at once never share one.
  var _installs = 0;

  CommentaryShelf(this.dir, this.onChange, {this.maxPackBytes = maxCommentaryPackBytes}) {
    dir.createSync(recursive: true);
    // A download or install cut short by the app closing leaves only temporary files behind.
    for (final f in dir.listSync().whereType<File>()) {
      if (f.path.endsWith('.part')) f.deleteSync();
    }
    for (final spec in commentaryPackSpecs) {
      library.open(spec.id, _path(spec));
    }
  }

  String _path(CommentaryPackSpec spec) => '${dir.path}/${spec.fileName}';

  bool isInstalled(String id) => library.installed.contains(id);

  /// The id and file of each installed pack, for a search that opens connections of its own.
  List<(String, String)> installedFiles() => [
    for (final spec in commentaryPackSpecs)
      if (isInstalled(spec.id)) (spec.id, _path(spec)),
  ];

  Future<void> download(CommentaryPackSpec spec) async {
    final pin = commentaryPins[spec.id];
    if (pin == null) throw StateError('No published pack for ${spec.id}.');
    final gz = File('${_path(spec)}.gz.part');
    progress[spec.id] = 0;
    onChange();
    var shownStep = 0;
    try {
      // A broken connection leaves the part, and the next try continues it.
      await downloadPinnedResumable(
        Uri.parse('$commentaryReleaseUrl/${spec.fileName}.gz'),
        gz,
        sha256: pin.sha256,
        maxBytes: pin.bytes,
        timeout: commentaryDownloadTimeout,
        onProgress: (received, total) {
          if (total == null || total <= 0) return;
          final f = received / total;
          progress[spec.id] = f;
          final step = (f * _progressSteps).floor();
          if (step == shownStep) return;
          shownStep = step;
          onChange();
        },
      );
      try {
        await _install(gz, expectedId: spec.id);
      } finally {
        discardPart(gz);
      }
    } finally {
      progress.remove(spec.id);
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
    final tmp = File('${dir.path}/incoming-${_installs++}.sqlite.part');
    CommentaryPackSpec? spec;
    try {
      // Locals only: a closure that touched `this` would try to send the open databases.
      final (from, to, cap) = (source.path, tmp.path, maxPackBytes);
      await Isolate.run(() => _unpack(from, to, cap));
      final id = CommentaryLibrary.packIdOf(tmp.path);
      spec = commentaryPackSpecs.where((s) => s.id == id).firstOrNull;
      if (spec == null || (expectedId != null && spec.id != expectedId)) {
        throw const FormatException('That file is not a Berea commentary pack.');
      }
      // The open pack holds its file; let go of it before replacing it.
      final pin = commentaryPins[spec.id];
      if (verifyCommentaryPacks && pin != null && !await hashCheck(tmp, pin.unpackedSha256)) {
        throw const FormatException("That file is not the pack Berea published, so it was not installed.");
      }
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
