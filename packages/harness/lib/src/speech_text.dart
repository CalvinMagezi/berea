import 'ref_parser.dart';
import 'sources.dart';

/// A guard marker means the claim failed its check, so the sentence holding it is never spoken.
final _failedClaim = RegExp(r'\[unverified\b|\[differs from Scripture\]');
final _corrected = RegExp(r'\s*\[quote corrected\]');

/// A sentence runs to . ? ! before a space or the end; a bracket group, "v." and "3.16" stay whole.
final _sentence = RegExp(
  r'(?:\[[^\]\n]*\]|\b(?:vv?|cf|ch)\.|[^.?!\[]|[.?!](?!\s|$)|\[)+[.?!]*\s*',
  caseSensitive: false,
);

final _blankLine = RegExp(r'\r?\n[ \t]*\r?\n');
final _blockMarkers = RegExp(r'^(?:\s*(?:#{1,6}|[-*+>]|\d+[.)])\s+)+');
final _link = RegExp(r'\[([^\]\n]+)\]\([^)\n]*\)');
final _bracket = RegExp(r'\[[^\]\n]*\]');
final _stars = RegExp(r'\*{1,3}([^*\n]+)\*{1,3}');
final _unders = RegExp(r'(?<!\w)_{1,2}([^_\n]+)_{1,2}(?!\w)');

/// Greek, Greek Extended and Hebrew: a voice cannot read them.
final _foreignScript = RegExp(r'[Ͱ-Ͽἀ-῿֐-׿]+');
final _strongs = RegExp(r'\b[GH]\d{1,5}[a-z]?\b');
final _emptyParen = RegExp(r'\s*\([,;:.\s]*\)');

final _paren = RegExp(r'\s*\(([^()\n]*)\)');
final _translationCode = RegExp(r'\s*,\s*[A-Z]{2,5}\s*$');

/// A translation named after a reference outside parentheses, as in "John 3:16, BSB, says".
final _codeAfterRef = RegExp(r'(?<=\d)\s*,\s*(?:BSB|KJV|WEB|ASV|YLT)\b');
final _numberedBook = RegExp(r'^([123]) (.+)$');
const _ordinals = {'1': 'First', '2': 'Second', '3': 'Third'};
const _psalms = 'Psalms';

final _lord = RegExp(r'\bLORD\b');
final _god = RegExp(r'\bGOD\b');

final _spaces = RegExp(r'\s+');
final _spaceBeforePunct = RegExp(r'\s+([.,;:?!])');
final _doubleComma = RegExp(r',(?:\s*,)+');
final _stackedPunct = RegExp(r'[,;:]+\s*([.?!])');
final _leadingPunct = RegExp(r'^[,;:\s]+');
final _sentenceEnd = RegExp(r'[.?!]$');

/// [script] as plain text a voice reads aloud, paragraphs separated by a blank line.
String speakable(String script) => speechParagraphs(script).join('\n\n');

/// The paragraphs of [speakable], none empty; a voice is called once for each.
List<String> speechParagraphs(String script) {
  final out = <String>[];
  for (final p in script.split(_blankLine)) {
    final text = _speakParagraph(p);
    if (text.isNotEmpty) out.add(text);
  }
  return out;
}

typedef _Unit = ({String text, bool block});

String _speakParagraph(String paragraph) {
  final spoken = <String>[];
  for (final u in _units(paragraph)) {
    var text = _speakUnit(u.text);
    // A heading or list item has no full stop of its own, so the voice would run it on.
    if (u.block && text.isNotEmpty && !_sentenceEnd.hasMatch(text)) text = '$text.';
    if (text.isNotEmpty) spoken.add(text);
  }
  return spoken.join(' ');
}

/// The lines of [paragraph] joined into prose, except that a heading or list item stands alone.
List<_Unit> _units(String paragraph) {
  final out = <_Unit>[];
  var open = false;
  for (final raw in paragraph.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final block = _blockMarkers.hasMatch(line);
    if (open && !block) {
      out.last = (text: '${out.last.text} $line', block: out.last.block);
    } else {
      out.add((text: line, block: block));
    }
    open = !line.startsWith('#');
  }
  return out;
}

String _speakUnit(String unit) {
  var s = _dropFailed(unit.replaceFirst(_blockMarkers, '')).replaceAll(_corrected, '');
  // Links go first so "[text](url)" is not taken for a source tag.
  s = s.replaceAllMapped(_link, (m) => m[1]!).replaceAll(sourceCitationGroup, '');
  s = s.replaceAll(_bracket, '');
  s = s.replaceAllMapped(_stars, (m) => m[1]!).replaceAllMapped(_unders, (m) => m[1]!);
  s = s.replaceAll('`', '');
  s = s.replaceAll(_foreignScript, '').replaceAll(_strongs, '').replaceAll(_emptyParen, '');
  s = _speakRefs(_refParens(s).replaceAll(_codeAfterRef, ''));
  return _tidy(s.replaceAll(_lord, 'Lord').replaceAll(_god, 'God'));
}

String _dropFailed(String s) => s.splitMapJoin(
  _sentence,
  onMatch: (m) => _failedClaim.hasMatch(m[0]!) ? '' : m[0]!,
  onNonMatch: (n) => n,
);

/// A parenthesised citation becomes part of the sentence, without its translation code.
String _refParens(String s) => s.replaceAllMapped(_paren, (m) {
  final inner = m[1]!;
  if (RefParser.matches(inner).isEmpty) return m[0]!;
  return ', ${inner.replaceAll(_translationCode, '')}';
});

String _speakRefs(String s) {
  final out = StringBuffer();
  var at = 0;
  for (final m in RefParser.matches(s)) {
    out
      ..write(s.substring(at, m.start))
      ..write(_spoken(m.ref));
    at = m.end;
  }
  return (out..write(s.substring(at))).toString();
}

String _spoken(Ref r) {
  final head = r.book.name == _psalms
      ? 'Psalm ${r.chapter}'
      : '${_bookWords(r.book.name)} chapter ${r.chapter}';
  final start = r.verseStart;
  if (start == null) return head;
  final end = r.verseEnd;
  return end == null || end == start ? '$head, verse $start' : '$head, verses $start to $end';
}

String _bookWords(String name) {
  final m = _numberedBook.firstMatch(name);
  return m == null ? name : '${_ordinals[m[1]]} ${m[2]}';
}

String _tidy(String s) => s
    .replaceAll(_spaces, ' ')
    .replaceAllMapped(_spaceBeforePunct, (m) => m[1]!)
    .replaceAll(_doubleComma, ',')
    .replaceAllMapped(_stackedPunct, (m) => m[1]!)
    .replaceFirst(_leadingPunct, '')
    .trim();
