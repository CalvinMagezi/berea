import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'books.dart';

/// Format stamp of the narration packs this version reads (`tool/audio/pack.py`).
const narrationPackFormat = '1';

/// Narrators whose packs this version accepts; a pack's id is `<narrator>-<book>`.
const narrationNarrators = {'souer'};

const _packTables = {'meta', 'chapters'};

/// An MP4 file names its type in a box at byte 4.
const _mp4TypeOffset = 4;
const _mp4Type = 'ftyp';

/// One word's place in the chapter audio, in milliseconds from the start of the file.
class WordTiming {
  final int verse;

  /// Position among the verse's words as [wordRanges] counts them, from 0.
  final int word;
  final int startMs;
  final int endMs;
  const WordTiming(this.verse, this.word, this.startMs, this.endMs);
}

final _wordPattern = RegExp(r'\S+');

/// The words of [verseText] as the timings count them, with offsets in the untrimmed text.
List<({int start, int end})> wordRanges(String verseText) => [
  for (final m in _wordPattern.allMatches(verseText)) (start: m.start, end: m.end),
];

/// The word of [ranges] at or before [offset]; a point between two words is the earlier one.
int? wordAtOffset(List<({int start, int end})> ranges, int offset) =>
    _lastAtOrBefore(ranges.length, (i) => ranges[i].start, offset);

/// Index of the last of [count] ascending keys at or before [target], by binary search.
int? _lastAtOrBefore(int count, int Function(int i) key, int target) {
  var lo = 0;
  var hi = count - 1;
  int? found;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (key(mid) <= target) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}

/// Word timings for one chapter, in reading order.
class ChapterTimings {
  final int book;
  final int chapter;
  final List<WordTiming> words;

  /// Number of timed words in each verse; a verse with none is absent.
  final Map<int, int> wordsPerVerse;

  ChapterTimings._(this.book, this.chapter, this.words)
    : wordsPerVerse = {for (final w in words) w.verse: w.word + 1};

  /// Parses the `timings` column for [book] [chapter], throwing [FormatException] on anything else.
  factory ChapterTimings.parse(
    String json, {
    required int book,
    required int chapter,
    required int durationMs,
  }) {
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      throw FormatException('The timings for chapter $chapter are not JSON.');
    }
    if (data is! Map || data['book'] != book || data['chapter'] != chapter) {
      throw FormatException('The timings for chapter $chapter belong to another chapter.');
    }
    final raw = data['words'];
    if (raw is! List) throw FormatException('Chapter $chapter has no word timings.');
    final words = <WordTiming>[];
    for (final entry in raw) {
      words.add(_timingOf(entry, chapter, durationMs, words.lastOrNull));
    }
    return ChapterTimings._(book, chapter, words);
  }

  /// Checks an entry against the previous: verses ascend, words count from 0, times inside audio.
  static WordTiming _timingOf(Object? entry, int chapter, int durationMs, WordTiming? previous) {
    final bad = FormatException('Chapter $chapter has a malformed word timing.');
    if (entry is! List || entry.length != 4 || entry.any((e) => e is! int)) throw bad;
    final t = WordTiming(entry[0] as int, entry[1] as int, entry[2] as int, entry[3] as int);
    final expectedWord = previous != null && previous.verse == t.verse ? previous.word + 1 : 0;
    final inOrder =
        t.verse >= 1 &&
        t.word == expectedWord &&
        (previous == null || t.verse >= previous.verse) &&
        (previous == null || t.startMs >= previous.startMs);
    final inAudio = t.startMs >= 0 && t.startMs <= t.endMs && t.endMs <= durationMs;
    if (!inOrder || !inAudio) throw bad;
    return t;
  }

  /// The word being spoken at [ms], held until the next starts; null during the announcement.
  int? indexAt(int ms) => _lastAtOrBefore(words.length, (i) => words[i].startMs, ms);

  /// Index of [word] of [verse], or of the verse's first word when [word] is out of range.
  int? indexOf(int verse, [int word = 0]) {
    final first = words.indexWhere((w) => w.verse == verse);
    if (first < 0) return null;
    final count = wordsPerVerse[verse]!;
    return first + (word >= 0 && word < count ? word : 0);
  }
}

/// What a checked narration pack holds.
class NarrationPackInfo {
  final String id;
  final int book;
  final String narrator;
  final List<int> chapters;

  /// Encoder priming a player that ignores the MP4 edit list would hear first.
  final int primingMs;
  const NarrationPackInfo(this.id, this.book, this.narrator, this.chapters, this.primingMs);
}

/// Opens an untrusted pack read-only with its schema disarmed; SQLite errors are FormatException.
T _withPack<T>(String path, T Function(Database db) read) {
  if (!File(path).existsSync()) throw const FormatException('The narration pack is missing.');
  Database? db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
    db.execute('PRAGMA trusted_schema = OFF');
    return read(db);
  } on SqliteException {
    throw const FormatException('That file is not a Berea narration pack.');
  } finally {
    db?.dispose();
  }
}

/// Checks a pack before it may replace anything; full chapter coverage is the caller's check.
NarrationPackInfo readNarrationPack(String path, {int? expectedBook}) => _withPack(path, (db) {
  const notAPack = FormatException('That file is not a Berea narration pack.');
  final tables = {
    for (final r in db.select("SELECT name FROM sqlite_master WHERE type = 'table'"))
      r['name'] as String?,
  };
  if (!tables.containsAll(_packTables)) throw notAPack;
  final meta = {
    for (final r in db.select('SELECT key, value FROM meta')) '${r['key']}': '${r['value']}',
  };
  if (meta['format'] != narrationPackFormat) throw notAPack;
  final book = int.tryParse(meta['book'] ?? '');
  final narrator = meta['narrator'] ?? '';
  if (book == null || book < 1 || book > books.length) throw notAPack;
  if (!narrationNarrators.contains(narrator) || meta['pack'] != '$narrator-$book') throw notAPack;
  if (expectedBook != null && book != expectedBook) {
    throw FormatException(
      'That pack narrates ${bookById(book).name}, not '
      '${bookById(expectedBook).name}.',
    );
  }
  final chapters = <int>[];
  final rows = db.select(
    'SELECT chapter, duration_ms, substr(audio, ?, ?) AS type, timings '
    'FROM chapters ORDER BY chapter',
    [_mp4TypeOffset + 1, _mp4Type.length],
  );
  for (final r in rows) {
    final chapter = r['chapter'];
    final duration = r['duration_ms'];
    final type = r['type'];
    final timings = r['timings'];
    if (chapter is! int || duration is! int || duration <= 0 || timings is! String) {
      throw notAPack;
    }
    if (type is! Uint8List || ascii.decode(type, allowInvalid: true) != _mp4Type) {
      throw FormatException('Chapter $chapter has no audio.');
    }
    ChapterTimings.parse(timings, book: book, chapter: chapter, durationMs: duration);
    chapters.add(chapter);
  }
  return NarrationPackInfo(meta['pack']!, book, narrator, chapters, _primingOf(meta));
});

/// AAC encoders prime with a few frames, well under this.
const _maxPrimingMs = 1000;

/// The pack's priming, absent meaning none; anything not a small count of milliseconds is refused.
int _primingOf(Map<String, String> meta) {
  final raw = meta['priming_ms'];
  if (raw == null) return 0;
  final ms = double.tryParse(raw);
  if (ms == null || !ms.isFinite || ms < 0 || ms > _maxPrimingMs) {
    throw const FormatException('That narration pack has an invalid priming time.');
  }
  return ms.round();
}

/// Throws unless [info] holds exactly chapters 1 to [chapterCount] of its book.
void checkNarrationChapters(NarrationPackInfo info, int chapterCount) {
  final name = bookById(info.book).name;
  for (var c = 1; c <= chapterCount; c++) {
    if (!info.chapters.contains(c)) throw FormatException('That pack is missing $name $c.');
  }
  if (info.chapters.length != chapterCount) {
    throw FormatException('That pack has chapters $name does not.');
  }
}

/// One chapter read out of a pack.
class NarrationChapter {
  final Uint8List audio;
  final int durationMs;

  /// Encoder priming a player that ignores the MP4 edit list would hear first.
  final int primingMs;
  final ChapterTimings timings;
  const NarrationChapter(this.audio, this.durationMs, this.primingMs, this.timings);
}

/// Reads [chapter] from the installed pack at [path], which was checked at install.
NarrationChapter readNarrationChapter(String path, int book, int chapter) => _withPack(path, (db) {
  final r = db.select('SELECT duration_ms, audio, timings FROM chapters WHERE chapter = ?', [
    chapter,
  ]).firstOrNull;
  if (r == null) throw FormatException('The narration has no chapter $chapter.');
  final meta = {
    for (final m in db.select("SELECT key, value FROM meta WHERE key = 'priming_ms'"))
      '${m['key']}': '${m['value']}',
  };
  final duration = r['duration_ms'] as int;
  final timings = ChapterTimings.parse(
    r['timings'] as String,
    book: book,
    chapter: chapter,
    durationMs: duration,
  );
  return NarrationChapter(r['audio'] as Uint8List, duration, _primingOf(meta), timings);
});
