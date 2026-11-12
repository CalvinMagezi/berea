import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'books.dart';

/// One passage a topic points to. [chapterEnd] differs from [chapter] only for a range that runs
/// into the next chapter. [verse] and [verseEnd] are 0 for a whole chapter.
typedef TopicRef = ({
  int book,
  int chapter,
  int verse,
  int verseEnd,
  int chapterEnd,
});

/// A line of a topic: the words the author wrote (a subheading, or "See" and the name it sends to)
/// and the passages after it.
class TopicLine {
  final String label;
  final List<TopicRef> refs;
  const TopicLine(this.label, this.refs);
}

class Topic {
  final String name;
  final List<TopicLine> lines;
  const Topic(this.name, this.lines);
}

/// The compact text a topic line's passages are stored as: book:chapter:verse:verseEnd:chapterEnd,
/// separated by semicolons.
String encodeTopicRefs(List<TopicRef> refs) => refs
    .map(
      (r) => '${r.book}:${r.chapter}:${r.verse}:${r.verseEnd}:${r.chapterEnd}',
    )
    .join(';');

List<TopicRef> decodeTopicRefs(String s) => [
  for (final part in s.split(';'))
    if (part.isNotEmpty)
      if (part.split(':').map(int.tryParse).toList() case [
        final int b,
        final int c,
        final int v,
        final int ve,
        final int ce,
      ])
        (book: b, chapter: c, verse: v, verseEnd: ve, chapterEnd: ce),
];

/// The SWORD OSIS book ids Nave uses, in canonical order.
const _osisBooks = [
  'Gen',
  'Exod',
  'Lev',
  'Num',
  'Deut',
  'Josh',
  'Judg',
  'Ruth',
  '1Sam',
  '2Sam',
  '1Kgs',
  '2Kgs',
  '1Chr',
  '2Chr',
  'Ezra',
  'Neh',
  'Esth',
  'Job',
  'Ps',
  'Prov',
  'Eccl',
  'Song',
  'Isa',
  'Jer',
  'Lam',
  'Ezek',
  'Dan',
  'Hos',
  'Joel',
  'Amos',
  'Obad',
  'Jonah',
  'Mic',
  'Nah',
  'Hab',
  'Zeph',
  'Hag',
  'Zech',
  'Mal',
  'Matt',
  'Mark',
  'Luke',
  'John',
  'Acts',
  'Rom',
  '1Cor',
  '2Cor',
  'Gal',
  'Eph',
  'Phil',
  'Col',
  '1Thess',
  '2Thess',
  '1Tim',
  '2Tim',
  'Titus',
  'Phlm',
  'Heb',
  'Jas',
  '1Pet',
  '2Pet',
  '1John',
  '2John',
  '3John',
  'Jude',
  'Rev',
];

/// The abbreviations Torrey's New Topical Textbook uses, by book id.
const _torreyBooks = {
  'Ge': 1,
  'Ex': 2,
  'Le': 3,
  'Nu': 4,
  'De': 5,
  'Jos': 6,
  'Jud': 7,
  'Ru': 8,
  '1Sa': 9,
  '2Sa': 10,
  '1Ki': 11,
  '2Ki': 12,
  '1Ch': 13,
  '2Ch': 14,
  'Ezr': 15,
  'Ne': 16,
  'Es': 17,
  'Job': 18,
  'Ps': 19,
  'Pr': 20,
  'Ec': 21,
  'So': 22,
  'Isa': 23,
  'Jer': 24,
  'La': 25,
  'Eze': 26,
  'Da': 27,
  'Ho': 28,
  'Joe': 29,
  'Am': 30,
  'Ob': 31,
  'Jon': 32,
  'Mic': 33,
  'Na': 34,
  'Hab': 35,
  'Zep': 36,
  'Hag': 37,
  'Zec': 38,
  'Mal': 39,
  'Mt': 40,
  'Mr': 41,
  'Lu': 42,
  'Joh': 43,
  'Ac': 44,
  'Ro': 45,
  '1Co': 46,
  '2Co': 47,
  'Ga': 48,
  'Eph': 49,
  'Php': 50,
  'Col': 51,
  '1Th': 52,
  '2Th': 53,
  '1Ti': 54,
  '2Ti': 55,
  'Tit': 56,
  'Phm': 57,
  'Heb': 58,
  'Jas': 59,
  '1Pe': 60,
  '2Pe': 61,
  '1Jo': 62,
  '2Jo': 63,
  '3Jo': 64,
  'Jude': 65,
  'Re': 66,
};

/// Books of one chapter, where a bare number after the book is a verse and not a chapter.
const _oneChapterBooks = {31, 57, 63, 64, 65};

/// Topics read from a SWORD module that was already unpacked into a [Topic] list, plus what could
/// not be read, so a build can report it.
class TopicsResult {
  final List<Topic> topics;
  final List<String> unread;
  const TopicsResult(this.topics, this.unread);
}

final _naveRef = RegExp(
  r'<ref osisRef="([^"]+)"[^>]*>(.*?)</ref>',
  dotAll: true,
);
final _anyTag = RegExp(r'<[^>]+>');
final _blank = RegExp(r'\s+');

String _plain(String s) => s
    .replaceAll(_anyTag, ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(_blank, ' ')
    .replaceAll(RegExp(r'^[\s→,;:\-–]+|[\s,;:\-–]+$'), '')
    .trim();

TopicRef? _osisRef(String id) {
  final parts = id.split('-');
  final start = _osisPoint(parts.first);
  if (start == null) return null;
  final end = parts.length > 1 ? _osisPoint(parts.last) : null;
  if (end == null || end.book != start.book) return start;
  return (
    book: start.book,
    chapter: start.chapter,
    verse: start.verse,
    verseEnd: end.verse,
    chapterEnd: end.chapter,
  );
}

TopicRef? _osisPoint(String s) {
  final m = RegExp(r'^([1-3]?[A-Za-z]+)\.(\d+)(?:\.(\d+))?$').firstMatch(s);
  if (m == null) return null;
  final i = _osisBooks.indexOf(m[1]!);
  if (i < 0) return null;
  final v = int.tryParse(m[3] ?? '') ?? 0;
  return (
    book: i + 1,
    chapter: int.parse(m[2]!),
    verse: v,
    verseEnd: v,
    chapterEnd: int.parse(m[2]!),
  );
}

/// Nave's entries: `<entryFree n="NAME"><def><lb/>→ subheading <ref osisRef="Gen.1.1">...`. A line may
/// carry several items, each a few words and the passages after them ("Esau forgives Jacob Ge 33:4;
/// Joseph forgives his brothers Ge 50:15"); each becomes its own line.
TopicsResult parseNave(String key, String entry) {
  final unread = <String>[];
  final lines = <TopicLine>[];
  final body = entry.replaceAll(RegExp(r'</?entryFree[^>]*>|</?def>'), '');
  for (final raw in body.split('<lb/>')) {
    var label = '';
    var refs = <TopicRef>[];
    void flush() {
      if (label.isNotEmpty || refs.isNotEmpty) lines.add(TopicLine(label, refs));
      label = '';
      refs = <TopicRef>[];
    }

    var at = 0;
    void words(String piece) {
      final text = _plain(piece);
      if (!RegExp(r'[A-Za-z]').hasMatch(text)) return;
      if (refs.isNotEmpty) flush();
      label = label.isEmpty ? text : '$label $text';
    }

    for (final m in _naveRef.allMatches(raw)) {
      words(raw.substring(at, m.start));
      at = m.end;
      final r = _osisRef(m[1]!);
      if (r == null) {
        unread.add('$key: ${m[1]}');
      } else {
        refs.add(r);
      }
    }
    words(raw.substring(at));
    flush();
  }
  return TopicsResult([Topic(key, lines)], unread);
}

/// Torrey's entries: `NAME\r\n- Subheading<br /><scripRef>Joh 10:7,9; 14:6</scripRef><br /><br />`.
TopicsResult parseTorrey(String entry) {
  final unread = <String>[];
  final nl = entry.indexOf('\r\n');
  final name = _plain(nl < 0 ? entry : entry.substring(0, nl));
  final lines = <TopicLine>[];
  final body = nl < 0 ? '' : entry.substring(nl + 2);
  var label = '';
  for (final chunk in body.split(RegExp(r'<br\s*/>'))) {
    final ref = RegExp(
      r'<scripRef>(.*?)</scripRef>',
      dotAll: true,
    ).firstMatch(chunk);
    if (ref == null) {
      final t = _plain(chunk);
      if (t.isNotEmpty) {
        if (label.isNotEmpty) lines.add(TopicLine(label, const []));
        label = t;
      }
      continue;
    }
    final refs = parseTorreyRefs(ref[1]!, unread, name);
    lines.add(TopicLine(label, refs));
    label = '';
  }
  if (label.isNotEmpty) lines.add(TopicLine(label, const []));
  return TopicsResult([Topic(name, lines)], unread);
}

/// "Joh 10:7,9; 14:6; Ro 5:2" into passages. A part without a book continues the book before it; a
/// bare number after a comma is a verse of the chapter before it.
List<TopicRef> parseTorreyRefs(String text, List<String> unread, String topic) {
  final out = <TopicRef>[];
  var book = 0, chapter = 0;
  for (final part in text.split(';')) {
    var rest = part.trim();
    if (rest.isEmpty) continue;
    final b = RegExp(r'^((?:[1-3]\s?)?[A-Za-z]+)\s*(.*)$').firstMatch(rest);
    if (b != null && _torreyBooks.containsKey(b[1]!.replaceAll(' ', ''))) {
      book = _torreyBooks[b[1]!.replaceAll(' ', '')]!;
      rest = b[2]!;
      chapter = 0;
    } else if (b != null &&
        b[1]!.isNotEmpty &&
        RegExp(r'^[A-Za-z]').hasMatch(rest)) {
      unread.add('$topic: ${part.trim()}');
      continue;
    }
    if (book == 0) {
      unread.add('$topic: ${part.trim()}');
      continue;
    }
    var first = true;
    for (final item in rest.split(',')) {
      final s = item.trim();
      if (s.isEmpty) continue;
      final cv = RegExp(r'^(\d+):(\d+)(?:-(?:(\d+):)?(\d+))?$').firstMatch(s);
      final num = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(s);
      if (cv != null) {
        chapter = int.parse(cv[1]!);
        final v = int.parse(cv[2]!);
        final endChapter = cv[3] == null ? chapter : int.parse(cv[3]!);
        final ve = cv[4] == null ? v : int.parse(cv[4]!);
        out.add((
          book: book,
          chapter: chapter,
          verse: v,
          verseEnd: ve,
          chapterEnd: endChapter,
        ));
        if (endChapter != chapter) chapter = endChapter;
      } else if (num != null) {
        final a = int.parse(num[1]!), z = int.parse(num[2] ?? num[1]!);
        if (_oneChapterBooks.contains(book)) {
          out.add((
            book: book,
            chapter: 1,
            verse: a,
            verseEnd: z,
            chapterEnd: 1,
          ));
        } else if (first || chapter == 0) {
          // A bare number straight after the book is a whole chapter ("Ps 23"; "Ps 23-25").
          for (var c = a; c <= z; c++) {
            out.add((
              book: book,
              chapter: c,
              verse: 0,
              verseEnd: 0,
              chapterEnd: c,
            ));
          }
          chapter = z;
        } else {
          out.add((
            book: book,
            chapter: chapter,
            verse: a,
            verseEnd: z,
            chapterEnd: chapter,
          ));
        }
      } else {
        unread.add('$topic: ${part.trim()}');
      }
      first = false;
    }
  }
  return out;
}

/// Reads every key and entry of a SWORD `RawLD` module (Torrey): the `.idx` holds an offset and
/// a size for each entry in the `.dat`, and each entry begins with its key and a line break.
List<String> readRawLd(String idxPath, String datPath) {
  final idx = File(idxPath).readAsBytesSync();
  final dat = File(datPath).readAsBytesSync();
  final view = ByteData.sublistView(idx);
  const record = 6;
  return [
    for (var i = 0; i + record <= idx.length; i += record)
      _utf8(
        dat.sublist(
          view.getUint32(i, Endian.little),
          view.getUint32(i, Endian.little) +
              view.getUint16(i + 4, Endian.little),
        ),
      ),
  ];
}

/// Reads every entry of a SWORD `zLD` module (Nave): keys with their block and slot in `.dat`, the
/// blocks zlib-compressed in `.zdt` and located by `.zdx`. Returns key to entry text.
Map<String, String> readZLd(String basePath) {
  final idx = File('$basePath.idx').readAsBytesSync();
  final dat = File('$basePath.dat').readAsBytesSync();
  final zdx = File('$basePath.zdx').readAsBytesSync();
  final zdt = File('$basePath.zdt').readAsBytesSync();
  final idxView = ByteData.sublistView(idx);
  final zdxView = ByteData.sublistView(zdx);
  final blocks = <int, Uint8List>{};
  Uint8List block(int n) => blocks.putIfAbsent(n, () {
    final off = zdxView.getUint32(n * 8, Endian.little);
    final size = zdxView.getUint32(n * 8 + 4, Endian.little);
    return Uint8List.fromList(zlib.decode(zdt.sublist(off, off + size)));
  });
  final out = <String, String>{};
  for (var i = 0; i + 8 <= idx.length; i += 8) {
    final off = idxView.getUint32(i, Endian.little);
    final size = idxView.getUint32(i + 4, Endian.little);
    final rec = dat.sublist(off, off + size);
    final keyEnd = rec.length - 8;
    final key = _utf8(
      rec.sublist(0, keyEnd),
    ).replaceAll(RegExp(r'[\r\n]+$'), '');
    final rv = ByteData.sublistView(Uint8List.fromList(rec));
    final b = block(rv.getUint32(keyEnd, Endian.little));
    final slot = rv.getUint32(keyEnd + 4, Endian.little);
    final bv = ByteData.sublistView(b);
    final eo = bv.getUint32(4 + slot * 8, Endian.little);
    final es = bv.getUint32(8 + slot * 8, Endian.little);
    out[key] = _utf8(b.sublist(eo, eo + es));
  }
  return out;
}

String _utf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// Books named by [bookById], used to print a reference.
String topicRefLabel(TopicRef r) {
  final name = bookById(r.book).name;
  if (r.verse == 0) {
    return r.chapter == r.chapterEnd ? '$name ${r.chapter}' : '$name ${r.chapter}-${r.chapterEnd}';
  }
  final start = '$name ${r.chapter}:${r.verse}';
  if (r.chapterEnd != r.chapter) return '$start-${r.chapterEnd}:${r.verseEnd}';
  return r.verseEnd == r.verse ? start : '$start-${r.verseEnd}';
}
