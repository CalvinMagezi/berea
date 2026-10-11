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

final _usfmNotes = RegExp(r'\\(f|fe|x|ef|ex)\s.*?\\\1\*', dotAll: true);
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

final _xmlToken = RegExp(r'<[^>]+>|[^<]+');
final _xmlName = RegExp(r'^</?\s*([A-Za-z:]+)');

String? _attr(String tag, String name) => RegExp('\\b$name\\s*=\\s*"([^"]*)"').firstMatch(tag)?[1];

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
    final parts = id.split(' ').first.split('.');
    if (parts.length < 3) return;
    final book = bookFor(parts[0]);
    final text = _clean(_unescape(buf.toString()));
    buf.clear();
    if (book == null || text.isEmpty) return;
    out.add((book: book, chapter: int.parse(parts[1]), verse: int.parse(parts[2]), text: text));
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

/// Entries of a zip archive, stored or deflated. Enough for ebible.org USFM bundles.
Map<String, Uint8List> readZip(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  const eocdSig = 0x06054b50, centralSig = 0x02014b50;
  var eocd = bytes.length - 22;
  while (eocd >= 0 && d.getUint32(eocd, Endian.little) != eocdSig) {
    eocd--;
  }
  if (eocd < 0) throw const FormatException('not a zip file');
  final count = d.getUint16(eocd + 10, Endian.little);
  var p = d.getUint32(eocd + 16, Endian.little);
  final out = <String, Uint8List>{};
  for (var i = 0; i < count; i++) {
    if (d.getUint32(p, Endian.little) != centralSig) throw const FormatException('bad zip');
    final method = d.getUint16(p + 10, Endian.little);
    final compressed = d.getUint32(p + 20, Endian.little);
    final nameLen = d.getUint16(p + 28, Endian.little);
    final extraLen = d.getUint16(p + 30, Endian.little);
    final commentLen = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen), allowMalformed: true);
    final dataStart =
        local +
        30 +
        d.getUint16(local + 26, Endian.little) +
        d.getUint16(local + 28, Endian.little);
    final raw = bytes.sublist(dataStart, dataStart + compressed);
    if (!name.endsWith('/')) {
      out[name] = switch (method) {
        0 => raw,
        8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(raw)),
        _ => throw FormatException('unsupported zip compression $method in $name'),
      };
    }
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

/// Picks the parser from the file name and contents. Zips may hold USFM, OSIS or Zefania files.
List<VerseRow> parseBibleFile(String name, Uint8List bytes) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.zip')) {
    return [
      for (final e in readZip(bytes).entries)
        if (!e.key.startsWith('__MACOSX')) ...parseBibleFile(e.key, e.value),
    ];
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  if (lower.endsWith('.csv')) return parseCsvBible(text);
  if (lower.endsWith('.usfm') || lower.endsWith('.sfm')) return parseUsfm(text);
  if (lower.endsWith('.xml') || lower.endsWith('.osis')) {
    if (text.contains('<osis')) return parseOsis(text);
    if (text.contains('<XMLBIBLE') || text.contains('<BIBLEBOOK')) return parseZefania(text);
    throw FormatException('$name is XML but neither OSIS nor Zefania');
  }
  return const [];
}
