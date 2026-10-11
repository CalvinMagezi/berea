import 'dart:math';

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

/// Share of a misquote's content words that must appear in the matching verse span.
const minQuoteOverlap = 0.7;

/// A correction needs at least this many shared content words, so a quote made mostly of small
/// words ("and the Lord said to them") never matches by accident.
const minQuoteContentWords = 4;

/// How far ahead of the runner-up verse the best one must be, so a quote that could belong to
/// either is flagged rather than rewritten.
const minQuoteMargin = 0.15;

/// How far after a quote to look for the reference it is attributed to.
const quoteCitationWindow = 48;

const _functionWords = {
  'a',
  'an',
  'and',
  'as',
  'at',
  'be',
  'but',
  'by',
  'for',
  'from',
  'he',
  'her',
  'him',
  'his',
  'i',
  'in',
  'is',
  'it',
  'me',
  'my',
  'not',
  'of',
  'on',
  'or',
  'our',
  'shall',
  'she',
  'so',
  'that',
  'the',
  'their',
  'them',
  'they',
  'this',
  'to',
  'us',
  'was',
  'we',
  'were',
  'who',
  'will',
  'with',
  'you',
  'your',
  'said',
  'all',
  'are',
  'have',
  'has',
  'had',
  'do',
  'did',
  'no',
  'one',
  'which',
};

Set<String> _contentWords(String s) => {
  for (final w in CitationGuard.normalize(s).split(' '))
    if (w.isNotEmpty && !_functionWords.contains(w)) w,
};

/// The verbatim span of the one shown verse a misquote clearly came from, or null. When the quote
/// is attributed to a reference, only that passage's verses are candidates, so a correction never
/// confirms a wrong attribution.
String? correctQuote(String quote, Iterable<Verse> shown, {Ref? citedAs}) {
  final q = CitationGuard.normalize(quote).split(' ').where((w) => w.isNotEmpty).toList();
  final qContent = _contentWords(quote);
  if (q.isEmpty || qContent.length < minQuoteContentWords) return null;
  final candidates = citedAs == null
      ? shown
      : shown.where((v) => citedAs.overlaps(Ref(v.book, v.chapter, v.verse, v.verse)));
  var best = 0.0, second = 0.0;
  String? bestSpan;
  for (final v in candidates) {
    final words = v.text.split(RegExp(r'\s+'));
    var verseBest = 0.0;
    var bestAllShared = -1;
    String? verseSpan;
    final qAll = q.toSet();
    for (var len = q.length - 2; len <= q.length + 3; len++) {
      if (len < 1 || len > words.length) continue;
      for (var i = 0; i + len <= words.length; i++) {
        final span = words.sublist(i, i + len).join(' ');
        final shared = qContent.intersection(_contentWords(span)).length;
        if (shared < minQuoteContentWords) continue;
        final score = shared / qContent.length;
        // Equal content scores prefer the window sharing the most words overall, so small words
        // the quote did include, such as a leading "For", are kept.
        final allShared = qAll
            .intersection(CitationGuard.normalize(span).split(' ').toSet())
            .length;
        if (score > verseBest || (score == verseBest && allShared > bestAllShared)) {
          verseBest = score;
          bestAllShared = allShared;
          verseSpan = span;
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

  /// Capitalised words that precede numbers in ordinary prose: "Verse 3:16", "At 3:30",
  /// "Monday 3:30". Any of them anywhere in the name means it is not a citation.
  static const _notBooks = {
    'Verse',
    'Verses',
    'Chapter',
    'Chapters',
    'Section',
    'Part',
    'Page',
    'Day',
    'Days',
    'Week',
    'At',
    'By',
    'In',
    'On',
    'Around',
    'About',
    'Until',
    'Since',
    'Between',
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
    'Ratio',
    'Score',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
    'Time',
    'Hour',
    'Minute',
    'Mr',
    'Mrs',
    'Dr',
    'Mark',
    'Room',
    'Gate',
  };
  static const _ordinals = {'First': '1', 'Second': '2', 'Third': '3'};
  static final _spaces = RegExp(r'\s+');

  /// Shortest name that can be judged: shorter ones ("Is", "Gn", "Am") are abbreviations or
  /// ordinary words, not inventions.
  static const _minJudgedName = 4;

  /// The citation text when its name cannot be any book, else null. Conservative on purpose: a
  /// real citation marked invented is worse than a missed invention, which the reference check
  /// and the eval still catch.
  static String? _unknownBook(Match m) {
    var words = m[2]!.split(_spaces);
    var numeral = m[1] ?? '';
    if (words.any(_notBooks.contains)) return null;
    final ordinal = _ordinals[words.first];
    if (ordinal != null && words.length > 1) {
      numeral = ordinal;
      words = words.sublist(1);
    }
    if (words.join().length < _minJudgedName) return null;
    for (var i = 0; i < words.length; i++) {
      final tail = words.sublist(i).join(' ');
      if (bookFor(tail) != null || bookFor('$numeral$tail') != null) return null;
      // A numbered book named without its number: "Peter 1:3", "Samuel 3:10".
      if (bookFor('1 $tail') != null) return null;
    }
    // A book name followed by another word: "John Smith 3:30".
    if (words.any((w) => bookFor(w) != null || bookFor('1 $w') != null)) return null;
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
      final after = withRefs.substring(end, min(withRefs.length, end + quoteCitationWindow));
      final citedAs = RefParser.matches(after).firstOrNull?.ref;
      final fix = correctQuote(quoted, ctx.allVerses, citedAs: citedAs);
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
