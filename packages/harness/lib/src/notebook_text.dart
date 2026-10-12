import 'dart:convert';
import 'dart:typed_data';

import 'commentary.dart';
import 'importers.dart';

/// A chunk aims for this many characters, so a few fit a small model's prompt with room to cite.
const notebookChunkChars = 1200;

/// A break is not taken before this many characters, so chunks do not shrink to a line each.
const notebookChunkMinChars = 400;

/// About 600 pages of prose. Larger sources are refused rather than cut short silently.
const maxNotebookSourceChars = 1500000;

const tooLongMessage = 'That source is too long. The limit is about 600 pages of text.';

/// Search uses at most this many distinct words from a query.
const maxNotebookQueryTerms = 16;

/// A slice of a source's normalised text: `text == source.substring(start, end)`. Offsets are
/// UTF-16 indices. [page] is the 1-based PDF page, null for sources without pages.
class TextChunk {
  final int ordinal;
  final int start;
  final int end;
  final int? page;
  final String text;
  const TextChunk(this.ordinal, this.start, this.end, this.page, this.text);
}

/// A source's normalised text and the chunks that cover it.
class ChunkedText {
  final String text;
  final List<TextChunk> chunks;
  const ChunkedText(this.text, this.chunks);
}

/// Separates sections (or pages) in a source's text.
const _sectionBreak = '\n\n';

final _lineBreaks = RegExp(r'\r\n?');
final _runsOfSpace = RegExp(r'[ \t\u00a0\f\v]+');
final _spaceAtLineEdges = RegExp(r' *\n *');
final _manyBlankLines = RegExp(r'\n{3,}');

/// Line endings unified, runs of spaces collapsed, at most one blank line in a row.
String normalizeSourceText(String raw) => raw
    .replaceAll(_lineBreaks, '\n')
    .replaceAll(_runsOfSpace, ' ')
    .replaceAll(_spaceAtLineEdges, '\n')
    .replaceAll(_manyBlankLines, '\n\n')
    .trim();

/// Normalises [sections] and chunks each one on its own, so no chunk crosses a section. When
/// [paged] is true each section is a PDF page and its chunks carry its 1-based number, empty
/// pages included in the count. Throws [FormatException] when there is no text or too much.
ChunkedText chunkSections(List<String> sections, {bool paged = false}) {
  final buffer = StringBuffer();
  final spans = <(int, int, int?)>[];
  for (var i = 0; i < sections.length; i++) {
    final section = normalizeSourceText(sections[i]);
    if (section.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.write(_sectionBreak);
    final start = buffer.length;
    buffer.write(section);
    spans.add((start, buffer.length, paged ? i + 1 : null));
    if (buffer.length > maxNotebookSourceChars) throw const FormatException(tooLongMessage);
  }
  if (buffer.isEmpty) {
    throw const FormatException('No text was found in that source.');
  }
  final text = buffer.toString();
  final chunks = <TextChunk>[];
  for (final (start, end, page) in spans) {
    _chunkSpan(text, start, end, page, chunks);
  }
  return ChunkedText(text, chunks);
}

void _chunkSpan(String text, int from, int to, int? page, List<TextChunk> out) {
  var start = from;
  while (start < to) {
    start = _skipSpace(text, start, to);
    if (start >= to) return;
    final limit = start + notebookChunkChars;
    var end = limit >= to ? to : _breakBefore(text, start, limit);
    while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
      end--;
    }
    out.add(TextChunk(out.length, start, end, page, text.substring(start, end)));
    start = end;
  }
}

int _skipSpace(String text, int i, int to) {
  while (i < to && _isSpace(text.codeUnitAt(i))) {
    i++;
  }
  return i;
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x0A;

const _paragraphEnd = '\n\n';
final _sentenceEnd = RegExp(r'[.!?;:]["\u201d\u2019)]?\s');
const _highSurrogateFirst = 0xD800;
const _highSurrogateLast = 0xDBFF;

/// The best place to end a chunk that starts at [start] and must end by [limit]: after the last
/// paragraph, else the last sentence, else the last space, else at [limit] itself.
int _breakBefore(String text, int start, int limit) {
  final floor = start + notebookChunkMinChars;
  final window = text.substring(floor, limit);
  final paragraph = window.lastIndexOf(_paragraphEnd);
  if (paragraph >= 0) return floor + paragraph;
  final sentence = _sentenceEnd.allMatches(window).lastOrNull;
  if (sentence != null) return floor + sentence.end - 1;
  final space = window.lastIndexOf(' ');
  if (space >= 0) return floor + space;
  final unit = text.codeUnitAt(limit - 1);
  // Never split a surrogate pair.
  return unit >= _highSurrogateFirst && unit <= _highSurrogateLast ? limit - 1 : limit;
}

// Every tag pattern stops at the next '<', so hostile input such as '<<<<' stays linear.
final _hiddenOpen = RegExp(r'<(head|script|style|nav)\b[^<>]*>', caseSensitive: false);
final _htmlBreaks = RegExp(
  r'</?(?:p|div|br|h[1-6]|li|ul|ol|tr|table|blockquote|section|article|header|footer|aside|hr|dd|dt|pre)\b[^<>]*>',
  caseSensitive: false,
);
final _htmlTags = RegExp(r'<[^<>]*>');

/// Plain text from an HTML or XHTML document: comments, head, scripts and styles dropped, block
/// elements turned into line breaks, entities decoded.
String htmlPlainText(String html) => normalizeSourceText(
  decodeHtmlEntities(
    _dropHidden(_dropComments(html)).replaceAll(_htmlBreaks, '\n').replaceAll(_htmlTags, ''),
  ),
);

/// Removes comments in one pass; an unclosed comment runs to the end, as in a browser.
String _dropComments(String html) {
  final out = StringBuffer();
  var i = 0;
  while (true) {
    final open = html.indexOf('<!--', i);
    if (open < 0) break;
    out.write(html.substring(i, open));
    final close = html.indexOf('-->', open + 4);
    if (close < 0) return out.toString();
    i = close + 3;
  }
  out.write(html.substring(i));
  return out.toString();
}

/// Removes head, script, style and nav elements with their content. A tag whose closing tag is
/// missing loses only itself and is not searched for again, so the pass stays linear.
String _dropHidden(String html) {
  final out = StringBuffer();
  final unclosed = <String>{};
  var i = 0;
  for (final m in _hiddenOpen.allMatches(html)) {
    if (m.start < i) continue;
    final name = m[1]!.toLowerCase();
    out.write(html.substring(i, m.start));
    // A self-closing tag such as <script src="a.js"/> has no content to drop.
    final selfClosing = m[0]!.endsWith('/>');
    final close = selfClosing || unclosed.contains(name)
        ? null
        : RegExp('</$name\\s*>', caseSensitive: false).allMatches(html, m.end).firstOrNull;
    if (close == null && !selfClosing) unclosed.add(name);
    i = close?.end ?? m.end;
  }
  out.write(html.substring(i));
  return out.toString();
}

// ponytail: regex over the OPF, not an XML parser; enough for EPUB 2 and 3 packages. Use
// package:xml if real files carry attributes this misses.
final _rootFile = RegExp(r"""<rootfile\b[^<>]*full-path\s*=\s*["']([^"'<>]+)["']""");
final _manifestItem = RegExp(r'<item\b[^<>]*>', caseSensitive: false);
final _spineItem = RegExp(r'<itemref\b[^<>]*>', caseSensitive: false);

/// Longer manifest or spine tags are skipped, which keeps attribute matching cheap.
const _maxTagChars = 4096;

final _encryptedUri = RegExp(r'''URI\s*=\s*["']([^"'<>]*)["']''');

String? _attr(String tag, String name) =>
    RegExp('(?<![\\w:-])$name\\s*=\\s*["\']([^"\']*)["\']').firstMatch(tag)?.group(1);

Iterable<String> _tags(RegExp pattern, String package) =>
    pattern.allMatches(package).map((m) => m[0]!).where((t) => t.length <= _maxTagChars);

/// The text of each document in an EPUB's reading order. Reads the zip with the importers' size
/// limits in two passes, so only the package files and the spine's documents are inflated,
/// never images or fonts. Documents listed as encrypted (DRM) are skipped. Throws
/// [FormatException] when the file is not an EPUB or holds more text than a source may.
List<String> epubSections(Uint8List bytes) {
  final meta = readZip(
    bytes,
    include: (n) => n.startsWith('META-INF/') || n.toLowerCase().endsWith('.opf'),
  );
  final encryption = meta['META-INF/encryption.xml'];
  final encrypted = {
    if (encryption != null)
      for (final m in _encryptedUri.allMatches(_utf8(encryption))) m[1]!,
  };
  final container = meta['META-INF/container.xml'];
  final opfPath = container == null ? null : _rootFile.firstMatch(_utf8(container))?.group(1);
  final opf = opfPath == null ? null : meta[opfPath];
  if (opfPath == null || opf == null) {
    throw const FormatException('That file is not an EPUB.');
  }
  final package = _utf8(opf);
  final base = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';
  final hrefs = <String, String>{
    for (final tag in _tags(_manifestItem, package))
      if ((_attr(tag, 'id'), _attr(tag, 'href')) case (final String id, final String href))
        id: href,
  };
  final spine = [
    for (final tag in _tags(_spineItem, package))
      if (hrefs[_attr(tag, 'idref')] case final href?)
        if (_resolve(base, href) case final path?)
          if (!encrypted.contains(path) && !encrypted.contains(Uri.encodeFull(path))) path,
  ];
  final wanted = spine.toSet();
  final docs = readZip(bytes, include: wanted.contains);
  final sections = <String>[];
  var chars = 0;
  for (final path in spine) {
    final doc = docs[path];
    if (doc == null) continue;
    final text = htmlPlainText(_utf8(doc));
    chars += text.length;
    if (chars > maxNotebookSourceChars) throw const FormatException(tooLongMessage);
    sections.add(text);
  }
  return sections;
}

String _utf8(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

/// [href] relative to the OPF folder [base], without its fragment, percent-decoded and with
/// `..` segments resolved.
String? _resolve(String base, String href) {
  final String path;
  try {
    path = Uri.decodeFull(href.split('#').first);
  } on ArgumentError {
    return null;
  }
  final parts = <String>[];
  for (final segment in '$base$path'.split('/')) {
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (segment.isNotEmpty && segment != '.') {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

// Marks stay inside the word, so pointed Hebrew and accented Greek search as whole words.
final _queryWord = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

/// An FTS5 query matching any word of [text], each quoted so no input can act as an operator.
/// Null when [text] has no words.
String? notebookFtsQuery(String text) {
  final terms = _queryWord
      .allMatches(text.toLowerCase())
      .map((m) => m[0]!)
      .toSet()
      .take(maxNotebookQueryTerms);
  if (terms.isEmpty) return null;
  return terms.map((t) => '"$t"').join(' OR ');
}
