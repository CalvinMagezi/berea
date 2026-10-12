// Build-time reader for SWORD zCom commentaries, in pure Dart so libsword (GPL) is never used.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'commentary.dart';

/// Testament book counts in the KJV versification every module here uses.
const otBookCount = 39;
const ntBookCount = 27;

/// Verse counts per chapter, per book, in canonical order (Genesis first).
typedef Versification = List<List<int>>;

/// One SWORD index slot: a book intro (chapter 0), a chapter intro (verse 0) or a verse.
class SwordKey {
  final int book;
  final int chapter;
  final int verse;
  const SwordKey(this.book, this.chapter, this.verse);

  @override
  bool operator ==(Object other) =>
      other is SwordKey && other.book == book && other.chapter == chapter && other.verse == verse;

  @override
  int get hashCode => Object.hash(book, chapter, verse);

  @override
  String toString() => '$book $chapter:$verse';
}

/// A testament's keys in SWORD index order: two headings, then each book, chapter and verse.
List<SwordKey?> testamentSlots(Versification v11n, {required bool newTestament}) {
  final first = newTestament ? otBookCount : 0;
  final count = newTestament ? ntBookCount : otBookCount;
  final slots = <SwordKey?>[null, null];
  for (var b = first; b < first + count; b++) {
    final book = b + 1;
    slots.add(SwordKey(book, 0, 0));
    for (var c = 0; c < v11n[b].length; c++) {
      slots.add(SwordKey(book, c + 1, 0));
      for (var v = 1; v <= v11n[b][c]; v++) {
        slots.add(SwordKey(book, c + 1, v));
      }
    }
  }
  return slots;
}

/// Raw text of one slot, with the run of following verses that point at the same text.
class SwordEntry {
  final SwordKey key;
  final int lastVerse;
  final String text;
  const SwordEntry(this.key, this.lastVerse, this.text);
}

const _blockIndexEntryBytes = 12;
const _zComVerseEntryBytes = 10;
const _zCom4VerseEntryBytes = 12;

/// Where a slot's text lives: block number, offset in the unpacked block, and size.
typedef _Pointer = (int, int, int);

/// The kept slots of the testament at [prefix] (data path plus ot or nt), links folded to ranges.
List<SwordEntry> readTestament(
  String prefix,
  String blockLetter,
  List<SwordKey?> slots, {
  required bool zCom4,
}) {
  final idx = File('$prefix.${blockLetter}zv');
  if (!idx.existsSync()) return const [];
  final verseIndex = ByteData.sublistView(idx.readAsBytesSync());
  final width = zCom4 ? _zCom4VerseEntryBytes : _zComVerseEntryBytes;
  if (verseIndex.lengthInBytes != slots.length * width) {
    throw FormatException(
      '$prefix: ${verseIndex.lengthInBytes ~/ width} index slots, expected ${slots.length}. '
      'The module does not use KJV versification.',
    );
  }
  final textAt = _textReader(
    ByteData.sublistView(File('$prefix.${blockLetter}zs').readAsBytesSync()),
    File('$prefix.${blockLetter}zz').readAsBytesSync(),
  );
  _Pointer pointerAt(int i) {
    final at = i * width;
    final size = zCom4
        ? verseIndex.getUint32(at + 8, Endian.little)
        : verseIndex.getUint16(at + 8, Endian.little);
    return (
      verseIndex.getUint32(at, Endian.little),
      verseIndex.getUint32(at + 4, Endian.little),
      size,
    );
  }

  return _foldLinks(slots, pointerAt, textAt);
}

/// Decodes a slot's text, unpacking each zlib block once.
String Function(_Pointer) _textReader(ByteData blockIndex, Uint8List data) {
  final blocks = <int, Uint8List>{};
  Uint8List unpack(int n) {
    final at = n * _blockIndexEntryBytes;
    final offset = blockIndex.getUint32(at, Endian.little);
    final size = blockIndex.getUint32(at + 4, Endian.little);
    return Uint8List.fromList(zlib.decode(data.sublist(offset, offset + size)));
  }

  return (p) {
    final (b, o, size) = p;
    return _utf8OrLatin1(blocks.putIfAbsent(b, () => unpack(b)).sublist(o, o + size));
  };
}

/// Keeps each slot's text once; a link only extends an unbroken run of verses in one chapter.
List<SwordEntry> _foldLinks(
  List<SwordKey?> slots,
  _Pointer Function(int) pointerAt,
  String Function(_Pointer) textAt,
) {
  final out = <SwordEntry>[];
  // The slot just before (null after an empty one), and the record behind the last entry kept.
  _Pointer? previous;
  _Pointer? kept;
  for (var i = 0; i < slots.length; i++) {
    final key = slots[i];
    final pointer = pointerAt(i);
    final contiguous = pointer == previous;
    previous = key == null || pointer.$3 == 0 ? null : pointer;
    if (key == null || previous == null) continue;
    if (pointer == kept) {
      if (contiguous) _extendRun(out, key);
      continue;
    }
    final text = textAt(pointer);
    // A blank record is never kept, so nothing may be linked through it.
    if (text.trim().isEmpty) {
      previous = null;
      continue;
    }
    kept = pointer;
    if (!_copiesLastChapter(out.lastOrNull, key, text)) out.add(SwordEntry(key, key.verse, text));
  }
  return out;
}

/// Older modules point note-less verses at the last note; only same-chapter verses extend it.
void _extendRun(List<SwordEntry> out, SwordKey key) {
  final run = out.last;
  final sameChapter = run.key.book == key.book && run.key.chapter == key.chapter;
  if (!sameChapter || run.key.verse == 0 || key.verse == 0) return;
  out[out.length - 1] = SwordEntry(run.key, key.verse, run.text);
}

/// Some modules store a copy of a chapter's last note again under the next chapter.
bool _copiesLastChapter(SwordEntry? last, SwordKey key, String text) {
  if (last == null || text != last.text) return false;
  return last.key.book != key.book || last.key.chapter != key.chapter;
}

/// Older ThML modules are Latin-1; newer OSIS ones UTF-8.
String _utf8OrLatin1(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// A SWORD `.conf` as every value of each key; keys such as GlobalOptionFilter repeat.
typedef SwordConf = Map<String, List<String>>;

/// Parses a SWORD `.conf`, joining continuation lines that end in a backslash.
SwordConf parseSwordConf(String raw) {
  final out = <String, List<String>>{};
  String? pending;
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final joined = pending == null ? line : '$pending\n$line';
    if (joined.endsWith('\\')) {
      pending = joined.substring(0, joined.length - 1);
      continue;
    }
    pending = null;
    final eq = joined.indexOf('=');
    if (joined.startsWith('#') || joined.startsWith('[') || eq <= 0) continue;
    out.putIfAbsent(joined.substring(0, eq).trim(), () => []).add(joined.substring(eq + 1).trim());
  }
  return out;
}

const _publicDomain = 'Public Domain';
const _kjv = 'KJV';
const _blockLetters = {'BOOK': 'b', 'CHAPTER': 'c', 'VERSE': 'v'};

/// SWORD's default when a conf has no BlockType.
const _defaultBlockType = 'CHAPTER';

/// How to read a module; throws [FormatException] unless public domain, KJV-keyed zCom or zCom4.
({String dataPath, String blockLetter, bool zCom4, String version}) checkModuleConf(
  String module,
  SwordConf conf,
) {
  String? only(String key) {
    final values = conf[key] ?? const [];
    if (values.toSet().length > 1) throw FormatException('$module has conflicting $key values');
    return values.firstOrNull;
  }

  final licence = only('DistributionLicense');
  if (licence != _publicDomain) throw FormatException('$module is "$licence", not $_publicDomain');
  final v11n = only('Versification') ?? _kjv;
  if (v11n != _kjv) throw FormatException('$module uses $v11n versification, not $_kjv');
  final driver = only('ModDrv')?.toLowerCase();
  if (driver != 'zcom' && driver != 'zcom4') {
    throw FormatException('$module uses $driver, not zCom');
  }
  final letter = _blockLetters[(only('BlockType') ?? _defaultBlockType).toUpperCase()];
  if (letter == null) throw FormatException('$module has an unknown BlockType');
  final path = only('DataPath')?.replaceFirst(RegExp(r'^\./'), '');
  if (path == null || path.split('/').contains('..')) {
    throw FormatException('$module has no usable DataPath');
  }
  return (
    dataPath: path,
    blockLetter: letter,
    zCom4: driver == 'zcom4',
    version: only('Version') ?? '',
  );
}

final _preverse = RegExp(
  r'<div\b[^>]*x-preverse[^>]*\bsID="([^"]+)"[^>]*/>(.*?)'
  r'<div\b[^>]*x-preverse[^>]*\beID="\1"[^>]*/>',
  dotAll: true,
);

/// An opening section tag naming the passage it comments on, as Calvin's module marks them.
final _annotateRef = RegExp(r'<div\b[^>]*\bannotateRef="Bible:([^"]+)"[^>]*>');
final _chapterVerse = RegExp(r'\.(\d+)\.(\d+)');

/// "Verses 3-5", "Ver. 3-6." or a bare "3-6." at the start of a comment.
final _rangeHeading = RegExp(r'^(?:Verses?\s+|Ver\.?\s*)?(\d+)\s*[-\u2013]\s*(\d+)\b');

/// One module's rows, with counts for the build report.
class ConvertedModule {
  final List<CommentaryEntry> entries;
  final int headingDisagreements;
  final int clampedLinks;
  const ConvertedModule(this.entries, this.headingDisagreements, this.clampedLinks);
}

/// Display rows from raw slots: front matter becomes introductions, each comment gets its verses.
ConvertedModule convertSwordEntries(
  CommentaryModule module,
  List<SwordEntry> raw,
  int Function(int book, int chapter) versesIn,
) {
  final out = <CommentaryEntry>[];
  var disagreements = 0;
  var clamped = 0;
  for (final e in raw) {
    final k = e.key;
    var (intro, body) = _splitFrontMatter(module, e);
    var text = commentaryPlainText(body);
    if (module.introBeforeHeading && k.verse == 1 && intro.isEmpty) {
      (intro, text) = _splitAtVerseHeading(text, k.chapter);
    }
    if (intro.isNotEmpty) out.add(CommentaryEntry(module.id, k.book, k.chapter, 0, 0, intro));
    if (text.isEmpty) continue;
    // Book introductions sit in chapter 0, which has no verses.
    final lastInChapter = k.chapter == 0 ? 0 : versesIn(k.book, k.chapter);
    if (module.verseParagraphs) {
      out.addAll(_splitVerseParagraphs(module.id, k, text, lastInChapter));
      continue;
    }
    final range = _range(module, e, body, text, lastInChapter);
    if (range.clamped) clamped++;
    if (range.disagrees) disagreements++;
    out.add(CommentaryEntry(module.id, k.book, k.chapter, k.verse, range.end, text));
  }
  final entries = module.sectionKeyed ? expandSectionStarts(out, versesIn) : out;
  return ConvertedModule(entries, disagreements, clamped);
}

/// A comment's last verse: SWORD's link, cut to Calvin's named verses, or widened by a heading.
({int end, bool clamped, bool disagrees}) _range(
  CommentaryModule module,
  SwordEntry e,
  String markup,
  String text,
  int lastInChapter,
) {
  final k = e.key;
  var end = e.lastVerse;
  var clamped = false;
  final named = module.annotateKeyed ? _lastAnnotatedVerse(markup, k.chapter) : null;
  if (named != null && end > named && named >= k.verse) {
    end = named;
    clamped = true;
  }
  final heading = k.verse > 0 ? _rangeHeading.firstMatch(text) : null;
  if (heading == null || int.parse(heading[1]!) != k.verse) {
    return (end: end, clamped: clamped, disagrees: false);
  }
  final headed = int.parse(heading[2]!);
  final valid = headed > k.verse && headed <= lastInChapter;
  if (valid && end == k.verse) end = headed;
  return (end: end, clamped: clamped, disagrees: valid && end != headed);
}

/// Splits a first verse at its heading line ("Isa 1:1", "Verse 1") into preface and comment.
(String, String) _splitAtVerseHeading(String text, int chapter) {
  final heading = RegExp(
    '^(?:[1-3]?[A-Z][a-z]{1,3} $chapter:1|Verses? 1)(?:[-\\u2013]\\d+)?\\b',
    multiLine: true,
  );
  final m = heading.firstMatch(text);
  if (m == null || m.start == 0) return ('', text);
  return (text.substring(0, m.start).trim(), text.substring(m.start));
}

final _verseParagraph = RegExp(r'^Verses? (\d+)(?:\s*[-\u2013]\s*(\d+))?\b');
final _sectionHeading = RegExp(r"^[A-Z][A-Z ,'.]{2,60}$");
const _wholePsalm = 'Whole Psalm';

/// Splits Spurgeon's whole-psalm entry into rows per section and "Verse N." run; the rest is intro.
List<CommentaryEntry> _splitVerseParagraphs(
  String module,
  SwordKey k,
  String text,
  int lastInChapter,
) {
  final out = <CommentaryEntry>[];
  String? section;
  var (start, end) = (0, 0);
  final buf = <String>[];
  void flush() {
    if (buf.isEmpty) return;
    final body = [?section, ...buf].join('\n');
    out.add(CommentaryEntry(module, k.book, k.chapter, start, end, body));
    buf.clear();
  }

  for (final line in text.split('\n')) {
    if (_sectionHeading.hasMatch(line)) {
      flush();
      section = line;
      (start, end) = (0, 0);
      continue;
    }
    if (line.startsWith(_wholePsalm) && (start, end) != (0, 0)) {
      flush();
      (start, end) = (0, 0);
    }
    final m = _verseParagraph.firstMatch(line);
    final from = m == null ? null : int.parse(m[1]!);
    if (from != null && from >= 1 && from <= lastInChapter) {
      final to = (m![2] == null ? from : int.parse(m[2]!)).clamp(from, lastInChapter);
      if ((from, to) != (start, end)) flush();
      (start, end) = (from, to);
    }
    buf.add(line);
  }
  flush();
  return out;
}

/// A first verse's front matter as plain text, and the markup left for the verse itself.
(String, String) _splitFrontMatter(CommentaryModule module, SwordEntry e) {
  if (e.key.verse != 1) return ('', e.text);
  final preverse = _preverse.firstMatch(e.text);
  if (preverse != null) {
    final rest = e.text.replaceRange(preverse.start, preverse.end, '');
    return (commentaryPlainText(preverse[2]!), rest);
  }
  if (!module.annotateKeyed) return ('', e.text);
  final first = _verseSections(e.text, e.key.chapter).firstOrNull;
  final cut = first?.start ?? e.text.length;
  return (commentaryPlainText(e.text.substring(0, cut)), e.text.substring(cut));
}

Iterable<RegExpMatch> _verseSections(String markup, int chapter) =>
    _annotateRef.allMatches(markup).where((m) {
      final ref = m[1];
      if (ref == null) return false;
      final cv = _chapterVerse.firstMatch(ref);
      return cv != null && int.parse(cv[1]!) == chapter;
    });

/// The highest verse of [chapter] that a section of [markup] says it comments on.
int? _lastAnnotatedVerse(String markup, int chapter) {
  int? last;
  for (final m in _verseSections(markup, chapter)) {
    for (final cv in _chapterVerse.allMatches(m[1]!)) {
      if (int.parse(cv[1]!) != chapter) continue;
      final v = int.parse(cv[2]!);
      if (last == null || v > last) last = v;
    }
  }
  return last;
}
