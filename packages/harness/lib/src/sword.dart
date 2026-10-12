// Build-time reader for CrossWire SWORD zCom and zCom4 commentary modules. Pure Dart, so the
// app never links libsword (GPL).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'commentary.dart';

/// Testament book counts in the KJV versification every module here uses.
const otBookCount = 39;
const ntBookCount = 27;

/// Verse counts per chapter, per book, in canonical order (Genesis first).
typedef Versification = List<List<int>>;

/// One verse-index slot of a SWORD testament: a book intro (chapter 0), a chapter intro
/// (verse 0) or a verse.
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

/// The keys of one testament in index order, mirroring SWORD's VersificationMgr: slot 0 is the
/// module heading, slot 1 the testament heading, then each book's heading, and each chapter's
/// heading followed by its verses. Book ids are canonical (Matthew is 40).
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

/// Reads every non-empty slot of a module's testament. [prefix] is the data path plus `ot` or
/// `nt`; [blockLetter] is `b`, `c` or `v` from the module's BlockType. Verses that link to the
/// same text as the verse before them are folded into that entry's [SwordEntry.lastVerse].
List<SwordEntry> readTestament(
  String prefix,
  String blockLetter,
  List<SwordKey?> slots, {
  required bool zCom4,
}) {
  final idx = File('$prefix.${blockLetter}zv');
  if (!idx.existsSync()) return const [];
  final verseIndex = ByteData.sublistView(idx.readAsBytesSync());
  final blockIndex = ByteData.sublistView(File('$prefix.${blockLetter}zs').readAsBytesSync());
  final data = File('$prefix.${blockLetter}zz').readAsBytesSync();
  final width = zCom4 ? _zCom4VerseEntryBytes : _zComVerseEntryBytes;
  if (verseIndex.lengthInBytes != slots.length * width) {
    throw FormatException(
      '$prefix: ${verseIndex.lengthInBytes ~/ width} index slots, expected ${slots.length}. '
      'The module does not use KJV versification.',
    );
  }
  final blocks = <int, Uint8List>{};
  Uint8List block(int n) => blocks.putIfAbsent(n, () {
    final at = n * _blockIndexEntryBytes;
    final offset = blockIndex.getUint32(at, Endian.little);
    final size = blockIndex.getUint32(at + 4, Endian.little);
    return Uint8List.fromList(zlib.decode(data.sublist(offset, offset + size)));
  });

  final out = <SwordEntry>[];
  (int, int, int)? previous;
  for (var i = 0; i < slots.length; i++) {
    final key = slots[i];
    final at = i * width;
    final b = verseIndex.getUint32(at, Endian.little);
    final o = verseIndex.getUint32(at + 4, Endian.little);
    final size = zCom4
        ? verseIndex.getUint32(at + 8, Endian.little)
        : verseIndex.getUint16(at + 8, Endian.little);
    final pointer = (b, o, size);
    if (key == null || size == 0) {
      previous = null;
      continue;
    }
    final linked = pointer == previous && out.isNotEmpty && key.verse > 0;
    previous = pointer;
    if (linked) {
      final last = out.removeLast();
      out.add(SwordEntry(last.key, key.verse, last.text));
      continue;
    }
    final bytes = block(b);
    final text = _utf8OrLatin1(bytes.sublist(o, o + size));
    if (text.trim().isEmpty) continue;
    out.add(SwordEntry(key, key.verse, text));
  }
  return out;
}

/// Older ThML modules are Latin-1; newer OSIS ones UTF-8.
String _utf8OrLatin1(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Key and value pairs of a SWORD `.conf` file. Repeated keys keep the first value, and
/// continuation lines ending in a backslash are joined.
Map<String, String> parseSwordConf(String raw) {
  final out = <String, String>{};
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
    out.putIfAbsent(joined.substring(0, eq).trim(), () => joined.substring(eq + 1).trim());
  }
  return out;
}

final _preverse = RegExp(
  r'<div\b[^>]*x-preverse[^>]*\bsID="([^"]+)"[^>]*/>(.*?)<div\b[^>]*x-preverse[^>]*\beID="\1"[^>]*/>',
  dotAll: true,
);

/// An opening section tag naming the passage it comments on, as Calvin's module marks them.
final _annotateRef = RegExp(r'<div\b[^>]*\bannotateRef="Bible:([^"]+)"[^>]*>');
final _chapterVerse = RegExp(r'\.(\d+)\.(\d+)');

/// "Verses 3-5", "Ver. 3-6." or a bare "3-6." at the start of a comment.
final _rangeHeading = RegExp(r'^(?:Verses?\s+|Ver\.?\s*)?(\d+)\s*[-\u2013]\s*(\d+)\b');

/// Converted rows of one module with counts for the build report: range headings that
/// disagree with SWORD's links, and links cut back to the verses a comment names.
class ConvertedModule {
  final List<CommentaryEntry> entries;
  final int headingDisagreements;
  final int clampedLinks;
  const ConvertedModule(this.entries, this.headingDisagreements, this.clampedLinks);
}

/// Turns raw SWORD slots into display rows.
///
/// Front matter stored before the first verse of a chapter (book introductions, chapter
/// outlines, Calvin's title pages and prefaces) becomes that chapter's introduction (verse 0)
/// instead of the verse's comment. A comment that names its own range in a heading gets that
/// range when SWORD did not link the verses. Section-keyed modules then run each single-verse
/// comment to the next one.
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

/// The last verse a comment covers: SWORD's link, cut back to the verses Calvin's sections
/// name, or widened to a range heading when SWORD did not link the verses.
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

/// The text before a line headed with the chapter's first verse ("Isa 1:1", "1Ch 1:1-4",
/// "Verse 1"), and the comment from that line on.
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

/// Spurgeon's Treasury of David holds a whole psalm at verse 1, in sections (EXPOSITION,
/// EXPLANATORY NOTES AND QUAINT SAYINGS, HINTS TO THE VILLAGE PREACHER) whose paragraphs open
/// with "Verse 4." Each run of paragraphs on the same verses becomes its own row, headed with
/// its section; paragraphs on no verse in particular become the psalm's introduction.
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

/// The plain-text introduction held at the first verse of a chapter, and the markup left for
/// the verse itself. Calvin's module has no preverse markers: everything before its first
/// verse section is front matter, and a first verse with no verse section is all front matter.
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
