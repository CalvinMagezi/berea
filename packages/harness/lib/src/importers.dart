import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'books.dart';
import 'csv.dart';

typedef VerseRow = ({Book book, int chapter, int verse, String text});

final _spaces = RegExp(r'\s+');

String _clean(String s) => s.replaceAll(_spaces, ' ').trim();

/// `Book,Chapter,Verse,Text` with a header row. Throws on an unknown book name.
List<VerseRow> parseCsvBible(String csv) {
  final rows = parseCsv(csv);
  if (rows.isEmpty || rows.first.length < 4) {
    throw const FormatException('expected a Book,Chapter,Verse,Text header');
  }
  return [
    for (final r in rows.skip(1))
      if (r.length >= 4 && r[0].trim().isNotEmpty)
        (
          book: bookFor(r[0]) ?? (throw FormatException('unknown book "${r[0]}"')),
          chapter: int.parse(r[1]),
          verse: int.parse(r[2]),
          text: r[3].trim(),
        ),
  ];
}

final _bsbVerse = RegExp(r'^(.+) (\d+):(\d+)\t(.*)$');
const _bsbHeader = 'Verse\t';

/// bereanbible.com bsb.txt (`Book C:V<TAB>Text` after a header); any other line throws.
List<VerseRow> parseBsbText(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final lines = const LineSplitter().convert(text);
  final header = lines.indexWhere((l) => l.startsWith(_bsbHeader));
  if (header < 0) throw const FormatException('expected a "Verse<TAB>..." header row');
  return [
    for (final line in lines.skip(header + 1))
      if (line.trim().isNotEmpty) _bsbRow(line),
  ];
}

VerseRow _bsbRow(String line) {
  final m = _bsbVerse.firstMatch(line);
  if (m == null) throw FormatException('not a verse line: "$line"');
  final book = bookFor(m[1]!) ?? (throw FormatException('unknown book "${m[1]}"'));
  return (book: book, chapter: int.parse(m[2]!), verse: int.parse(m[3]!), text: m[4]!.trim());
}

/// A footnote or cross reference closed by its own marker before the next verse or chapter. An
/// unclosed opener is not matched, so its following text is kept rather than scripture deleted;
/// the stray marker itself is removed with the other markers.
final _usfmNotes = RegExp(r'\\(f|fe|x|ef|ex)\s(?:(?!\\[vc]\s).)*?\\\1\*', dotAll: true);
final _usfmWord = RegExp(r'\\\+?w\s+([^|\\]*?)(?:\|[^\\]*?)?\\\+?w\*');
final _usfmLineMarker = RegExp(r'^\\([a-z]+)(\d*)\b');
final _usfmChapterVerse = RegExp(r'\\(c|v)\s+(\d+)(?:-\d+)?\s?');
final _usfmAnyMarker = RegExp(r'\\\+?[a-z]+\d*\*?');

/// Lines that carry headings, titles or intro text, never verse text.
const _usfmSkipLines = {
  'id',
  'ide',
  'h',
  'toc',
  'mt',
  'ms',
  'mr',
  's',
  'r',
  'd',
  'rem',
  'sp',
  'ip',
  'ili',
  'is',
  'imt',
  'io',
  'iot',
  'sts',
  'cl',
  'cd',
  'mte',
  'periph',
};

/// One USFM book file. Books outside the 66 (deuterocanon, front matter, glossary) return empty.
List<VerseRow> parseUsfm(String usfm) {
  if (usfm.startsWith('\uFEFF')) usfm = usfm.substring(1);
  final id = RegExp(r'^\\id\s+([A-Z0-9]{3})', multiLine: true).firstMatch(usfm);
  final book = id == null ? null : bookFor(id[1]!);
  if (book == null) return const [];

  final text = usfm.replaceAll(_usfmNotes, '').replaceAllMapped(_usfmWord, (m) => m[1]!);
  final kept = StringBuffer();
  for (final line in const LineSplitter().convert(text)) {
    final m = _usfmLineMarker.firstMatch(line.trimLeft());
    if (m != null && _usfmSkipLines.contains(m[1])) continue;
    kept
      ..write(line)
      ..write(' ');
  }

  final out = <VerseRow>[];
  final body = kept.toString();
  var chapter = 0, verse = 0, start = 0;
  void flush(int end) {
    if (chapter == 0 || verse == 0) return;
    final t = _clean(body.substring(start, end).replaceAll(_usfmAnyMarker, ''));
    if (t.isNotEmpty) out.add((book: book, chapter: chapter, verse: verse, text: t));
  }

  for (final m in _usfmChapterVerse.allMatches(body)) {
    flush(m.start);
    if (m[1] == 'c') {
      chapter = int.parse(m[2]!);
      verse = 0;
    } else {
      verse = int.parse(m[2]!);
    }
    start = m.end;
  }
  flush(body.length);
  return out;
}

/// A heading printed before [verse]: `ms` a major division (the five books of Psalms), `s1` a
/// section, `s2` a subsection, `qa` an acrostic letter. [refs] holds the parallel passages
/// (`\r`) or the division's range (`\mr`), empty when there are none.
typedef HeadingRow = ({Book book, int chapter, int verse, String kind, String text, String refs});

final _usfmHeadingLine = RegExp(r'^\\(ms|s|qa|r|mr)(\d*)\s+(.*)$');

/// The headings of one USFM book file, each anchored to the verse that follows it. Psalm
/// superscriptions (`\d`) are scripture in the BSB's own text, so they are not headings.
List<HeadingRow> parseUsfmHeadings(String usfm) {
  if (usfm.startsWith('﻿')) usfm = usfm.substring(1);
  final id = RegExp(r'^\\id\s+([A-Z0-9]{3})', multiLine: true).firstMatch(usfm);
  final book = id == null ? null : bookFor(id[1]!);
  if (book == null) return const [];

  final out = <HeadingRow>[];
  final pending = <_PendingHeading>[];
  var chapter = 0;
  final text = usfm.replaceAll(_usfmNotes, '');
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trimLeft();
    final heading = _usfmHeadingLine.firstMatch(line);
    if (heading != null) {
      _addPending(pending, heading);
      continue;
    }
    for (final m in _usfmChapterVerse.allMatches(line)) {
      if (m[1] == 'c') {
        chapter = int.parse(m[2]!);
        continue;
      }
      final verse = int.parse(m[2]!);
      out.addAll(pending.map((p) => p.at(book, chapter, verse)));
      pending.clear();
    }
  }
  return out;
}

class _PendingHeading {
  final String kind;
  final String text;
  String refs = '';
  _PendingHeading(this.kind, this.text);

  HeadingRow at(Book book, int chapter, int verse) =>
      (book: book, chapter: chapter, verse: verse, kind: kind, text: text, refs: refs);
}

void _addPending(List<_PendingHeading> pending, RegExpMatch heading) {
  final body = _clean(heading[3]!.replaceAll(_usfmAnyMarker, ''));
  if (body.isEmpty) return;
  final marker = heading[1]!;
  if (marker != 'r' && marker != 'mr') {
    pending.add(
      _PendingHeading(marker == 's' ? 's${heading[2]!.isEmpty ? '1' : heading[2]}' : marker, body),
    );
    return;
  }
  // A reference line belongs to the heading just above it; with none waiting it is dropped.
  if (pending.isEmpty) return;
  final last = pending.last;
  last.refs = last.refs.isEmpty ? body : '${last.refs} $body';
}

/// Headings from every USFM file in an ebible.org style zip.
List<HeadingRow> parseUsfmZipHeadings(Uint8List zip) => [
  for (final e in readZip(zip).entries)
    if (e.key.toLowerCase().endsWith('.usfm') || e.key.toLowerCase().endsWith('.sfm'))
      ...parseUsfmHeadings(utf8.decode(e.value, allowMalformed: true)),
];

final _xmlToken = RegExp(r'<[^>]+>|[^<]+');
final _xmlName = RegExp(r'^</?\s*([A-Za-z:]+)');

/// An attribute value in double or single quotes.
String? _attr(String tag, String name) {
  final m = RegExp('\\b$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')').firstMatch(tag);
  return m == null ? null : (m[1] ?? m[2]);
}

final _leadingDigits = RegExp(r'^\d+');

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// OSIS, with container `<verse osisID>` or milestone `sID`/`eID` verses.
List<VerseRow> parseOsis(String xml) {
  final out = <VerseRow>[];
  String? current;
  final buf = StringBuffer();
  var skip = 0;

  void flush() {
    final id = current;
    current = null;
    if (id == null) return;
    final parts = id.split(' ').first.split('-').first.split('.');
    final text = _clean(_unescape(buf.toString()));
    buf.clear();
    if (parts.length < 3) return;
    final book = bookFor(parts[0]);
    final chapter = int.tryParse(_leadingDigits.firstMatch(parts[1])?[0] ?? '');
    final verse = int.tryParse(_leadingDigits.firstMatch(parts[2])?[0] ?? '');
    if (book == null || chapter == null || verse == null || text.isEmpty) return;
    out.add((book: book, chapter: chapter, verse: verse, text: text));
  }

  for (final m in _xmlToken.allMatches(xml)) {
    final tok = m[0]!;
    if (!tok.startsWith('<')) {
      if (current != null && skip == 0) buf.write(tok);
      continue;
    }
    final name = _xmlName.firstMatch(tok)?[1]?.toLowerCase();
    final closing = tok.startsWith('</');
    final selfClosing = tok.endsWith('/>');
    if (name == 'note' || name == 'title') {
      if (!selfClosing) skip += closing ? -1 : 1;
      continue;
    }
    if (name != 'verse') continue;
    if (closing || _attr(tok, 'eID') != null) {
      flush();
    } else if (_attr(tok, 'osisID') != null || _attr(tok, 'sID') != null) {
      flush();
      current = _attr(tok, 'osisID') ?? _attr(tok, 'sID');
    }
  }
  flush();
  return out;
}

/// Zefania XML: BIBLEBOOK bnumber, CHAPTER cnumber, VERS vnumber.
List<VerseRow> parseZefania(String xml) {
  final out = <VerseRow>[];
  Book? book;
  var chapter = 0, verse = 0, skip = 0;
  StringBuffer? buf;
  for (final m in _xmlToken.allMatches(xml)) {
    final tok = m[0]!;
    if (!tok.startsWith('<')) {
      if (buf != null && skip == 0) buf.write(tok);
      continue;
    }
    final name = _xmlName.firstMatch(tok)?[1]?.toUpperCase();
    final closing = tok.startsWith('</');
    if (name == 'NOTE') {
      if (!tok.endsWith('/>')) skip += closing ? -1 : 1;
    } else if (name == 'BIBLEBOOK' && !closing) {
      final n = int.tryParse(_attr(tok, 'bnumber') ?? '');
      book = n != null && n >= 1 && n <= books.length ? bookById(n) : null;
    } else if (name == 'CHAPTER' && !closing) {
      chapter = int.tryParse(_attr(tok, 'cnumber') ?? '') ?? 0;
    } else if (name == 'VERS' && !closing) {
      verse = int.tryParse(_attr(tok, 'vnumber') ?? '') ?? 0;
      buf = StringBuffer();
    } else if (name == 'VERS' && closing && buf != null) {
      final text = _clean(_unescape(buf.toString()));
      if (book != null && chapter > 0 && verse > 0 && text.isNotEmpty) {
        out.add((book: book, chapter: chapter, verse: verse, text: text));
      }
      buf = null;
    }
  }
  return out;
}

/// Limits for untrusted zips: a whole Bible in USFM is about 15 MB uncompressed.
const maxZipEntryBytes = 64 * 1024 * 1024;
const maxZipTotalBytes = 256 * 1024 * 1024;
const maxZipEntries = 2000;
const _zip64Sentinel = 0xFFFFFFFF;

/// Entries of a zip archive, stored or deflated. Enough for ebible.org USFM bundles. Rejects
/// zip64, oversized or truncated archives with a [FormatException] instead of exhausting memory.
/// [include] limits which entries are inflated and counted; [maxEntryBytes] lowers the cap.
Map<String, Uint8List> readZip(
  Uint8List bytes, {
  bool Function(String name)? include,
  int maxEntryBytes = maxZipEntryBytes,
}) {
  try {
    return _readZip(bytes, include, maxEntryBytes);
  } on RangeError {
    throw const FormatException('not a valid zip file');
  }
}

Map<String, Uint8List> _readZip(
  Uint8List bytes,
  bool Function(String name)? include,
  int maxEntryBytes,
) {
  final d = ByteData.sublistView(bytes);
  const eocdSig = 0x06054b50, centralSig = 0x02014b50;
  var eocd = bytes.length - 22;
  while (eocd >= 0 && d.getUint32(eocd, Endian.little) != eocdSig) {
    eocd--;
  }
  if (eocd < 0) throw const FormatException('not a zip file');
  final count = d.getUint16(eocd + 10, Endian.little);
  if (count > maxZipEntries) throw const FormatException('zip has too many entries');
  var p = d.getUint32(eocd + 16, Endian.little);
  final out = <String, Uint8List>{};
  var total = 0;
  for (var i = 0; i < count; i++) {
    if (d.getUint32(p, Endian.little) != centralSig) throw const FormatException('bad zip');
    final method = d.getUint16(p + 10, Endian.little);
    final compressed = d.getUint32(p + 20, Endian.little);
    final size = d.getUint32(p + 24, Endian.little);
    final nameLen = d.getUint16(p + 28, Endian.little);
    final extraLen = d.getUint16(p + 30, Endian.little);
    final commentLen = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    if (compressed == _zip64Sentinel || size == _zip64Sentinel || local == _zip64Sentinel) {
      throw const FormatException('zip64 archives are not supported');
    }
    final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen), allowMalformed: true);
    p += 46 + nameLen + extraLen + commentLen;
    if (name.endsWith('/') || (include != null && !include(name))) continue;
    total += size;
    if (size > maxEntryBytes || total > maxZipTotalBytes) {
      throw FormatException('zip entry $name is too large');
    }
    final dataStart =
        local +
        30 +
        d.getUint16(local + 26, Endian.little) +
        d.getUint16(local + 28, Endian.little);
    final raw = bytes.sublist(dataStart, dataStart + compressed);
    final data = switch (method) {
      0 => raw,
      8 => _inflate(raw, size),
      _ => throw FormatException('unsupported zip compression $method in $name'),
    };
    if (data.length != size) throw FormatException('zip entry $name is damaged');
    out[name] = data;
  }
  return out;
}

/// Inflates at most [declared] bytes, so a lying header cannot expand without bound.
Uint8List _inflate(Uint8List raw, int declared) {
  final sink = BytesBuilder();
  final out = _CappedSink(sink, declared);
  final input = ZLibDecoder(raw: true).startChunkedConversion(out)..add(raw);
  input.close();
  return sink.takeBytes();
}

class _CappedSink implements Sink<List<int>> {
  final BytesBuilder builder;
  final int cap;
  _CappedSink(this.builder, this.cap);

  @override
  void add(List<int> chunk) {
    if (builder.length + chunk.length > cap) {
      throw const FormatException('zip entry is larger than it declares');
    }
    builder.add(chunk);
  }

  @override
  void close() {}
}

/// Picks the parser from the file name and contents. Zips may hold USFM, OSIS or Zefania files.
List<VerseRow> parseBibleFile(String name, Uint8List bytes) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.zip')) {
    return [
      for (final e in readZip(bytes).entries)
        // Nested zips are not opened: one level is all a Bible bundle needs.
        if (!e.key.startsWith('__MACOSX') && !e.key.toLowerCase().endsWith('.zip'))
          ...parseBibleFile(e.key, e.value),
    ];
  }
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  if (lower.endsWith('.csv')) return parseCsvBible(text);
  if (lower.endsWith('.usfm') || lower.endsWith('.sfm')) return parseUsfm(text);
  if (lower.endsWith('.xml') || lower.endsWith('.osis')) {
    if (text.contains('<osis')) return parseOsis(text);
    if (text.contains('<XMLBIBLE') || text.contains('<BIBLEBOOK')) return parseZefania(text);
    throw FormatException('$name is XML but neither OSIS nor Zefania');
  }
  return const [];
}
