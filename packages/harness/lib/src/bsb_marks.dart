import 'importers.dart';
import 'ref_parser.dart';

/// What the BSB publisher prints with a verse's words: the words of Jesus in red, the words the
/// translators supplied in square brackets, and their footnotes. All of it is the publisher's.
enum MarkKind { red, supplied }

/// A span of the verse text, as UTF-16 offsets, [start] inclusive and [end] exclusive.
typedef MarkSpan = ({MarkKind kind, int start, int end});

/// A translators' footnote; [at] is the offset in the verse text just after the word it follows.
typedef BsbFootnote = ({int at, String text});

/// The marks and footnotes of one verse as the reader asks for them.
class VerseMarkSet {
  final List<MarkSpan> spans;
  final List<BsbFootnote> footnotes;
  const VerseMarkSet(this.spans, this.footnotes);
}

class VerseMarks {
  final Ref ref;
  final List<MarkSpan> spans;
  final List<BsbFootnote> footnotes;
  const VerseMarks(this.ref, this.spans, this.footnotes);
}

class MarksResult {
  /// Verses whose words in the tables file equal the words of bsb.txt. Only these are stored.
  final List<VerseMarks> verses;

  /// Verses where the two files differ in a word; nothing is stored for them.
  final List<Ref> unreconciled;
  const MarksResult(this.verses, this.unreconciled);
}

/// A word, with an apostrophe or a right quote inside it kept ("don't"), compared in lower case.
final _wordPattern = RegExp(
  r"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*",
  unicode: true,
);
final _tag = RegExp('<[^>]*>');

/// The tables file marks a word the translators left out of the English with "vvv".
const _absentMarker = 'vvv';

const _redOpen = '<span class=|red|>';
const _redParagraph = '<p class=|red|>';
const _paragraphOpen = '<p class=|';
const _spanClose = '</span>';

List<String> _words(String s) => [
  for (final m in _wordPattern.allMatches(s.replaceAll(_tag, '')))
    if (m[0]!.toLowerCase() != _absentMarker) m[0]!.toLowerCase(),
];

class _Token {
  final String word;
  final bool red, supplied;
  final String? footnote;
  const _Token(this.word, this.red, this.supplied, this.footnote);
}

/// Reads bsb_tables.tsv and the verse text of bsb.txt together. A verse is kept only when the two
/// files give the same words in the same order; the offsets are then those of bsb.txt's text.
MarksResult parseBsbMarks(String tsv, List<VerseRow> bsb) {
  final lines = tsv.split('\n');
  final header = lines.first.split('\t').map((h) => h.trim()).toList();
  int col(String name) {
    final i = header.indexOf(name);
    if (i < 0) throw FormatException('bsb_tables has no "$name" column');
    return i;
  }

  final sortCol = col('BSB Sort'),
      idCol = col('VerseId'),
      englishCol = col('BSB version');
  final hdgCol = col('Hdg'), crossCol = col('Crossref'), parCol = col('Par');
  final spaceCol = col('Space'), begCol = col('begQ');
  final pncCol = col('pnc'), endQCol = col('endQ'), noteCol = col('footnotes');
  final endCol = col('End text');
  final lastCol = [
    endCol,
    noteCol,
    englishCol,
    sortCol,
    idCol,
  ].reduce((a, b) => a > b ? a : b);

  final rows = <List<String>>[];
  for (final line in lines.skip(1)) {
    final c = line.replaceAll('\r', '').split('\t');
    if (c.length > lastCol) rows.add(c);
  }
  rows.sort(
    (a, b) => (int.tryParse(a[sortCol]) ?? 0).compareTo(
      int.tryParse(b[sortCol]) ?? 0,
    ),
  );

  final tokens = <String, List<_Token>>{};
  final refs = <String, Ref>{};
  String? current;
  var red = false, redParagraph = false;
  for (final c in rows) {
    if (c[idCol].isNotEmpty) {
      final ref = RefParser.parse(c[idCol]).firstOrNull;
      if (ref == null) {
        throw FormatException('bsb_tables: unknown verse "${c[idCol]}"');
      }
      current = _key(ref.book.id, ref.chapter, ref.verseStart ?? 0);
      refs[current] = ref;
      tokens[current] = [];
    }
    if (current == null) continue;
    final before = '${c[hdgCol]}${c[crossCol]}${c[parCol]}${c[spaceCol]}';
    if (before.contains(_paragraphOpen)) redParagraph = before.contains(_redParagraph);
    if ('$before${c[begCol]}'.contains(_redOpen)) red = true;

    final note = c[noteCol].replaceAll(_tag, '').trim();
    var inBrackets = false;
    final cell = c[englishCol];
    final pieces = [
      for (final m in RegExp(r'\[|\]|[^\[\]]+').allMatches(cell)) m[0]!,
    ];
    final words = <(String, bool)>[];
    for (final p in pieces) {
      if (p == '[') {
        inBrackets = true;
      } else if (p == ']') {
        inBrackets = false;
      } else {
        for (final w in _words(p)) {
          words.add((w, inBrackets));
        }
      }
    }
    for (var i = 0; i < words.length; i++) {
      final lastWord = i == words.length - 1;
      tokens[current]!.add(
        _Token(
          words[i].$1,
          red || redParagraph,
          words[i].$2,
          lastWord && note.isNotEmpty ? note : null,
        ),
      );
    }
    // A footnote on a row with no English still belongs to the word before it.
    if (words.isEmpty && note.isNotEmpty && tokens[current]!.isNotEmpty) {
      final last = tokens[current]!.removeLast();
      tokens[current]!.add(
        _Token(last.word, last.red, last.supplied, last.footnote ?? note),
      );
    }
    final after = '${c[pncCol]}${c[endQCol]}${c[noteCol]}${c[endCol]}';
    if (red && after.contains(_spanClose)) red = false;
  }

  final verses = <VerseMarks>[];
  final unreconciled = <Ref>[];
  for (final v in bsb) {
    final key = _key(v.book.id, v.chapter, v.verse);
    final ref = refs[key] ?? Ref(v.book, v.chapter, v.verse);
    final toks = tokens[key];
    final found = _wordPattern.allMatches(v.text).toList();
    final same =
        toks != null &&
        toks.length == found.length &&
        [
          for (var i = 0; i < toks.length; i++)
            toks[i].word == found[i][0]!.toLowerCase(),
        ].every((e) => e);
    if (!same) {
      unreconciled.add(ref);
      continue;
    }
    verses.add(_marks(ref, v.text, toks, found));
  }
  return MarksResult(verses, unreconciled);
}

String _key(int book, int chapter, int verse) => '$book:$chapter:$verse';

const _openQuotes = '“‘';

VerseMarks _marks(
  Ref ref,
  String text,
  List<_Token> toks,
  List<RegExpMatch> found,
) {
  final spans = <MarkSpan>[];
  final notes = <BsbFootnote>[];
  for (final kind in MarkKind.values) {
    var i = 0;
    while (i < toks.length) {
      final on = kind == MarkKind.red ? toks[i].red : toks[i].supplied;
      if (!on) {
        i++;
        continue;
      }
      var j = i;
      while (j + 1 < toks.length &&
          (kind == MarkKind.red ? toks[j + 1].red : toks[j + 1].supplied)) {
        j++;
      }
      var start = found[i].start;
      var end = found[j].end;
      if (kind == MarkKind.red) {
        while (start > 0 && _openQuotes.contains(text[start - 1])) {
          start--;
        }
        while (end < text.length &&
            !_isSpace(text[end]) &&
            !_wordPattern.hasMatch(text[end])) {
          end++;
        }
      }
      spans.add((kind: kind, start: start, end: end));
      i = j + 1;
    }
  }
  for (var i = 0; i < toks.length; i++) {
    if (toks[i].footnote case final n?) notes.add((at: found[i].end, text: n));
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  return VerseMarks(ref, spans, notes);
}

bool _isSpace(String c) => c.trim().isEmpty;
