import 'bible_db.dart';
import 'books.dart';
import 'ref_parser.dart';
import 'retriever.dart';

class GuardResult {
  final String text;
  final List<Ref> verified;
  final List<Ref> unverified;
  final List<String> unverifiedQuotes;

  /// Citations whose book name is not in the Bible at all, like "2 Hezekiah 4:1".
  final List<String> unknownBooks;

  /// Misquotes replaced with the verbatim words of the one verse they clearly came from.
  final List<String> correctedQuotes;
  const GuardResult(
    this.text,
    this.verified,
    this.unverified,
    this.unverifiedQuotes, [
    this.unknownBooks = const [],
    this.correctedQuotes = const [],
  ]);

  int get inventedCount => unverified.length + unknownBooks.length;
}

const minQuoteChars = 30;

/// Share of a misquote's words that must appear in the matching verse span.
const minQuoteOverlap = 0.7;

/// How far ahead of the runner-up verse the best one must be, so a quote that could belong to
/// either is flagged rather than rewritten.
const minQuoteMargin = 0.15;

/// The verbatim span of the one shown verse a misquote clearly came from, or null.
String? correctQuote(String quote, Iterable<Verse> shown) {
  final q = CitationGuard.normalize(quote).split(' ').where((w) => w.isNotEmpty).toList();
  if (q.isEmpty) return null;
  final qSet = q.toSet();
  var best = 0.0, second = 0.0;
  String? bestSpan;
  for (final v in shown) {
    final words = v.text.split(RegExp(r'\s+'));
    final norm = [for (final w in words) CitationGuard.normalize(w)];
    var verseBest = 0.0;
    String? verseSpan;
    for (var len = q.length - 2; len <= q.length + 3; len++) {
      if (len < 1 || len > words.length) continue;
      for (var i = 0; i + len <= words.length; i++) {
        final window = norm.sublist(i, i + len).toSet();
        final score = qSet.intersection(window).length / qSet.length;
        if (score > verseBest) {
          verseBest = score;
          verseSpan = words.sublist(i, i + len).join(' ');
        }
      }
    }
    if (verseBest > best) {
      second = best;
      best = verseBest;
      bestSpan = verseSpan;
    } else if (verseBest > second) {
      second = verseBest;
    }
  }
  if (best < minQuoteOverlap || best - second < minQuoteMargin) return null;
  return bestSpan?.replaceAll(RegExp(r'^[^\w\u2018\u201c]+|[,;:]+$'), '');
}

class CitationGuard {
  final BibleDb db;
  final String translation;
  CitationGuard(this.db, {this.translation = defaultTranslation});

  /// Anything shaped like a citation: optional numeral, capitalised name, chapter:verse.
  static final _citationShape = RegExp(
    r'\b((?:[1-3]|I{1,3})\s?)?([A-Z][a-z]+(?:\s+(?:of\s+)?[A-Z][a-z]+)?)\.?\s+(\d{1,3})\s*:\s*(\d{1,3})',
  );

  /// Capitalised words that precede numbers in ordinary prose: "Verse 3:16", "At 3:30".
  static const _notBooks = {
    'Verse',
    'Verses',
    'Chapter',
    'Chapters',
    'Section',
    'Part',
    'Page',
    'At',
    'By',
    'In',
    'On',
    'Around',
    'About',
    'Until',
    'Before',
    'After',
    'From',
    'To',
    'And',
    'Or',
    'The',
    'See',
    'Cf',
    'Compare',
    'Also',
    'Read',
  };
  static final _spaces = RegExp(r'\s+');

  /// The citation text when no trailing run of its words names a book, else null.
  static String? _unknownBook(Match m) {
    final words = m[2]!.split(_spaces);
    final numeral = m[1] ?? '';
    for (var i = 0; i < words.length; i++) {
      final tail = words.sublist(i).join(' ');
      if (bookFor(tail) != null || bookFor('$numeral$tail') != null) return null;
    }
    if (words.length == 1 && _notBooks.contains(words.first)) return null;
    return m[0];
  }

  static const _open = '\u201c';
  static const _close = '\u201d';

  /// Pairs quote marks left to right within a line, so a short quote's closing mark never
  /// becomes the opening of a bogus long one.
  static List<(int, int)> quoteSpans(String s) {
    final spans = <(int, int)>[];
    int? open;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '\n') {
        open = null;
      } else if (ch == _open || (ch == '"' && open == null)) {
        open = i + 1;
      } else if ((ch == _close || ch == '"') && open != null) {
        spans.add((open, i));
        open = null;
      }
    }
    return spans;
  }

  static final _nonWord = RegExp(r'[^a-z0-9 ]');

  static String normalize(String s) =>
      s.toLowerCase().replaceAll(_nonWord, ' ').replaceAll(_spaces, ' ').trim();

  GuardResult apply(String output, StudyContext ctx) {
    final verified = <Ref>{};
    final unverified = <Ref>{};
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in RefParser.matches(output)) {
      buf.write(output.substring(cursor, m.start));
      if (db.exists(m.ref, translation: translation)) {
        verified.add(m.ref);
        buf.write(output.substring(m.start, m.end));
      } else {
        unverified.add(m.ref);
        buf.write('[unverified: ${m.ref.label}]');
      }
      cursor = m.end;
    }
    buf.write(output.substring(cursor));

    final unknown = <String>[];
    final withBooks = buf.toString().replaceAllMapped(_citationShape, (m) {
      final bad = _unknownBook(m);
      if (bad == null) return m[0]!;
      unknown.add(bad.trim());
      return '[unverified: ${bad.trim()}]';
    });

    final shown = normalize(ctx.allVerses.map((v) => v.text).join(' '));
    final badQuotes = <String>[];
    final corrected = <String>[];
    final withRefs = withBooks;
    final out = StringBuffer();
    cursor = 0;
    for (final (start, end) in quoteSpans(withRefs)) {
      final quoted = withRefs.substring(start, end);
      if (quoted.length < minQuoteChars || shown.contains(normalize(quoted))) continue;
      final fix = correctQuote(quoted, ctx.allVerses);
      if (fix != null) {
        corrected.add(quoted);
        out.write(withRefs.substring(cursor, start));
        out.write(fix);
        out.write(withRefs[end]);
        out.write(' [quote corrected]');
        cursor = end + 1;
        continue;
      }
      badQuotes.add(quoted);
      out.write(withRefs.substring(cursor, end + 1));
      out.write(' [unverified quote]');
      cursor = end + 1;
    }
    out.write(withRefs.substring(cursor));
    final text = out.toString();

    return GuardResult(text, verified.toList(), unverified.toList(), badQuotes, unknown, corrected);
  }
}
