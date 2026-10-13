import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:berea_harness/berea_harness.dart';

import 'pinned_download.dart';

/// Packs are published uncompressed on a data-only release, pinned by tag and by hash.
const narrationReleaseUrl = 'https://github.com/CalvinMagezi/berea/releases/download/audio-1';

/// The narrator every published pack uses.
const narrationNarrator = 'souer';
const narrationCredit = 'Bob Souer';

/// Size and SHA-256 of each published pack by book; adding a book is adding its pin.
const narrationPins = <int, PackPin>{
  43: PackPin('c30bbe16566e09eab0517208079d0533ac0ec1599f891cf5b7822ca76b749391', 27140096),
};

/// Size cap for a picked file; Psalms, the longest book, is about 90 MB at 32 kbps.
const maxNarrationPackBytes = 256 * bytesPerMb;
const narrationDownloadTimeout = Duration(minutes: 10);

String narrationFileName(int book) => '$narrationNarrator-$book.sqlite';

/// A chapter ready to play: its audio extracted to [file], and its word timings.
class NarrationTrack {
  final File file;
  final int durationMs;
  final int primingMs;
  final ChapterTimings timings;
  const NarrationTrack(this.file, this.durationMs, this.primingMs, this.timings);
}

/// The installed narration packs, one SQLite file per book, downloaded only on request.
class NarrationShelf {
  final Directory dir;
  final void Function() onChange;

  /// Chapters of a book in the Bible database, which a pack must match exactly.
  final int Function(int book) chapterCount;
  final int maxPackBytes;

  /// Download progress from 0 to 1 for books being fetched.
  final progress = <int, double>{};

  /// Numbers each install's temporary file, so two installs at once never share one.
  var _installs = 0;

  /// Numbers each extracted chapter, so a new one never overwrites a file the player has open.
  var _tracks = 0;

  /// Downloads in flight by book; asking again joins the one already running.
  final _downloads = <int, Future<void>>{};

  /// Books whose download should stop at its next chunk.
  final _cancelled = <int>{};

  NarrationShelf(
    this.dir,
    this.onChange, {
    required this.chapterCount,
    this.maxPackBytes = maxNarrationPackBytes,
  }) {
    dir.createSync(recursive: true);
    // Downloads or installs cut short leave only temporary files, with any SQLite journal.
    for (final f in dir.listSync().whereType<File>()) {
      if (f.uri.pathSegments.last.contains('.part')) f.deleteSync();
    }
    if (_playDir.existsSync()) _playDir.deleteSync(recursive: true);
  }

  String _path(int book) => '${dir.path}/${narrationFileName(book)}';

  /// Where the chapter being played is extracted; the player needs a real `.m4a` file.
  Directory get _playDir => Directory('${dir.path}/play');

  bool isInstalled(int book) => File(_path(book)).existsSync();

  /// Books with a published pack or one installed from a file, in Bible order.
  List<int> get availableBooks => {
    ...narrationPins.keys,
    for (final b in books)
      if (isInstalled(b.id)) b.id,
  }.toList()..sort();

  Future<void> download(int book) => _downloads[book] ??= _download(book).whenComplete(() {
    _downloads.remove(book);
    _cancelled.remove(book);
  });

  bool isDownloading(int book) => _downloads.containsKey(book);

  /// Stops [book]'s download, if one is running; its callers see a [DownloadCancelled].
  void cancelDownload(int book) {
    if (isDownloading(book)) _cancelled.add(book);
  }

  Future<void> _download(int book) async {
    final pin = narrationPins[book];
    if (pin == null) throw StateError('No published narration for ${bookById(book).name}.');
    final part = File('${_path(book)}.download.part');
    progress[book] = 0;
    onChange();
    try {
      await downloadPinned(
        Uri.parse('$narrationReleaseUrl/${narrationFileName(book)}'),
        part,
        sha256: pin.sha256,
        maxBytes: pin.bytes,
        timeout: narrationDownloadTimeout,
        cancelled: () => _cancelled.contains(book),
        onProgress: wholePercents((f) {
          progress[book] = f;
          onChange();
        }),
      );
      await _install(part, expectedBook: book);
    } finally {
      progress.remove(book);
      if (part.existsSync()) part.deleteSync();
      onChange();
    }
  }

  /// Installs a picked pack after checking it, in the place of the book it names.
  Future<String> installFromFile(String path) async {
    final source = File(path);
    if (!source.existsSync()) throw const FormatException('That file is not on this device.');
    if (source.lengthSync() > maxPackBytes) {
      throw const FormatException('That file is too large to be a narration pack.');
    }
    final book = await _install(source);
    onChange();
    return bookById(book).name;
  }

  Future<int> _install(File source, {int? expectedBook}) async {
    final tmp = File('${dir.path}/incoming-${_installs++}.sqlite.part');
    try {
      // Locals only: a closure that touched `this` would try to send the shelf to the isolate.
      final (from, to, cap) = (source.path, tmp.path, maxPackBytes);
      final info = await Isolate.run(() async {
        await copyUnpacked(from, to, cap);
        return readNarrationPack(to, expectedBook: expectedBook);
      });
      checkNarrationChapters(info, chapterCount(info.book));
      tmp.renameSync(_path(info.book));
      return info.book;
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  void delete(int book) {
    final f = File(_path(book));
    if (f.existsSync()) f.deleteSync();
    onChange();
  }

  /// Deletes every extracted chapter but [keep], once the player has moved to it.
  void prunePlayed({required File keep}) {
    if (!_playDir.existsSync()) return;
    for (final f in _playDir.listSync().whereType<File>()) {
      if (f.path != keep.path) f.deleteSync();
    }
  }

  /// Extracts [chapter] of [book] under a new name; [prunePlayed] removes old ones.
  Future<NarrationTrack> track(int book, int chapter) async {
    // Locals only, as in _install.
    final (path, play) = (_path(book), _playDir.path);
    final out = '$play/$book-$chapter-${_tracks++}.m4a';
    final c = await Isolate.run(() async {
      final c = readNarrationChapter(path, book, chapter);
      Directory(play).createSync(recursive: true);
      await File(out).writeAsBytes(c.audio, flush: true);
      return (durationMs: c.durationMs, primingMs: c.primingMs, timings: c.timings);
    });
    return NarrationTrack(File(out), c.durationMs, c.primingMs, c.timings);
  }
}
