import 'dart:math';

import 'bible_db.dart';
import 'books.dart';
import 'ref_parser.dart';
import 'retriever.dart';
import 'sources.dart';

class GuardResult {
  final String text;
  final List<Ref> verified;
  final List<Ref> unverified;
  final List<String> unverifiedQuotes;

  /// Citations whose book name is not in the Bible at all, like "2 Hezekiah 4:1".
  final List<String> unknownBooks;

  /// Misquotes replaced with the verbatim words of the one verse they clearly came from.
  final List<String> correctedQuotes;

  /// Real references that sit one slip away from a verse the model was shown. They stay verified
  /// and are surfaced for review, since a GPU decoder that corrupts digits produces exactly these.
  final List<NearMiss> nearMisses;

  /// Notebook answers only: the shown chunks the answer cites, each once.
  final List<ShownSource> sources;

  /// Notebook answers only: source tags naming a source, page or section that was not shown.
  final List<String> unverifiedSources;
  const GuardResult(
    this.text,
    this.verified,
    this.unverified,
    this.unverifiedQuotes, {
    this.unknownBooks = const [],
    this.correctedQuotes = const [],
    this.nearMisses = const [],
    this.sources = const [],
    this.unverifiedSources = const [],
  });

  int get inventedCount => unverified.length + unknownBooks.length;
}

class NearMiss {
  final Ref cited;
  final Ref shown;
  const NearMiss(this.cited, this.shown);

  String get label => '${cited.label} (shown ${shown.label})';

  @override
  String toString() => label;
}

/// The review line shown under an answer or study page, or null when there is nothing to check.
String? nearMissNotice(List<NearMiss> misses) =>
    misses.isEmpty ? null : 'Check the verse number: ${misses.map((m) => m.label).join(', ')}';

/// Verses either side of a shown verse that count as a near miss. A decoder that drifts on one
/// digit lands within this, and a wider window would catch ordinary neighbouring citations.
const nearMissVerseDrift = 2;

/// True when [a] and [b] differ only by two adjacent digits swapped, as in 16 and 61.
bool _isTransposed(int a, int b) {
  final x = '$a', y = '$b';
  if (a == b || x.length != y.length) return false;
  final diff = [
    for (var i = 0; i < x.length; i++)
      if (x[i] != y[i]) i,
  ];
  return diff.length == 2 &&
      diff[1] == diff[0] + 1 &&
      x[diff[0]] == y[diff[1]] &&
      x[diff[1]] == y[diff[0]];
}

/// Verses between the cited range and [verse]; zero when the range contains it.
int _verseGap(Ref cited, int verse) {
  final start = cited.verseStart!, end = cited.verseEnd ?? start;
  if (verse < start) return start - verse;
  return verse > end ? verse - end : 0;
}

/// Rank of a transposition match: below any drift, since a swap is the more specific evidence.
const _transposedRank = 0;

/// How close [v] is to [cited] as a near miss, lower is closer; null when it is not one.
int? _nearMissRank(Ref cited, Verse v) {
  if (cited.book.id != v.book.id) return null;
  final start = cited.verseStart!;
  final single = cited.verseEnd == null || cited.verseEnd == start;
  final sameChapter = cited.chapter == v.chapter;
  if (single && sameChapter && _isTransposed(start, v.verse)) return _transposedRank;
  if (single && start == v.verse && _isTransposed(cited.chapter, v.chapter)) return _transposedRank;
  if (!sameChapter) return null;
  final gap = _verseGap(cited, v.verse);
  return gap <= nearMissVerseDrift ? gap : null;
}

/// References in [cited] that touch no verse in [shown] but are a near miss of one: same book and
/// chapter within [nearMissVerseDrift] verses, or adjacent digits of the chapter or verse swapped.
/// Whole-chapter citations and anything overlapping a shown verse are never reported. The shown
/// verse reported is the closest one, a transposition before any drift.
List<NearMiss> findNearMisses(Iterable<Ref> cited, Iterable<Verse> shown) {
  final verses = shown.toList();
  final asRefs = [for (final v in verses) Ref(v.book, v.chapter, v.verse, v.verse)];
  final out = <NearMiss>[];
  for (final r in cited) {
    if (r.verseStart == null || asRefs.any(r.overlaps)) continue;
    int? best, bestRank;
    for (var i = 0; i < verses.length; i++) {
      final rank = _nearMissRank(r, verses[i]);
      if (rank == null || (bestRank != null && rank >= bestRank)) continue;
      best = i;
      bestRank = rank;
    }
    if (best != null) out.add(NearMiss(r, asRefs[best]));
  }
  return out;
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
  static const _leadingProse = {
    'See',
    'Cf',
    'Compare',
    'Also',
    'Read',
    'In',
    'From',
    'And',
    'Or',
    'The',
    'By',
    'On',
    'At',
    'To',
    'About',
    'Before',
    'After',
    'Since',
    'Until',
  };
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
    // Leading prose words ("See Jasher 3:2") are dropped and the rest judged; a name made of
    // prose words, or with one anywhere after that, is not a citation.
    while (words.length > 1 && _leadingProse.contains(words.first)) {
      words = words.sublist(1);
    }
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

  /// Checks [output] against [shown], the context PromptBuilder says the model was shown. With
  /// [checkSources] (notebook answers), source tags are checked too, and a quote may come from a
  /// shown source chunk: from the cited source when it names one, never when it names a verse.
  GuardResult apply(String output, StudyContext shown, {bool checkSources = false}) {
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

    final tagged = checkSources ? tagSources(shown.sources) : const <ShownSource>[];
    final sourceCheck = checkSources ? checkSourceCitations(withBooks, tagged) : null;
    final quotes = _checkQuotes(
      sourceCheck?.text ?? withBooks,
      shown,
      checkSources ? tagged : null,
    );

    return GuardResult(
      quotes.text,
      verified.toList(),
      unverified.toList(),
      quotes.bad,
      unknownBooks: unknown,
      correctedQuotes: quotes.corrected,
      nearMisses: findNearMisses(verified, shown.allVerses),
      sources: sourceCheck?.cited ?? const [],
      unverifiedSources: sourceCheck?.unverified ?? const [],
    );
  }

  /// Flags quotes found in no shown text and replaces clear misquotes of one verse. [sources] is
  /// null outside notebook answers, which keeps the Study check identical to the site's copy.
  ({String text, List<String> bad, List<String> corrected}) _checkQuotes(
    String text,
    StudyContext shown,
    List<ShownSource>? sources,
  ) {
    final verses = normalize(shown.allVerses.map((v) => v.text).join(' '));
    final bad = <String>[];
    final corrected = <String>[];
    final out = StringBuffer();
    var cursor = 0;
    for (final (start, end) in quoteSpans(text)) {
      final quoted = text.substring(start, end);
      final q = normalize(quoted);
      if (quoted.length < minQuoteChars || verses.contains(q)) continue;
      final (citedAs, citedSources) = _attribution(text, start, end, sources);
      final pool = citedSources ?? (citedAs == null ? sources : null);
      if (pool != null && _inAny(q, pool.map((s) => s.chunk.text))) continue;
      // Words attributed to a source are not offered as Scripture, so no verse corrects them.
      final fix = citedSources != null
          ? null
          : correctQuote(quoted, shown.allVerses, citedAs: citedAs);
      if (fix != null) {
        corrected.add(quoted);
        out.write(text.substring(cursor, start));
        out.write(fix);
        out.write(text[end]);
        out.write(' [quote corrected]');
        cursor = end + 1;
        continue;
      }
      bad.add(quoted);
      out.write(text.substring(cursor, end + 1));
      out.write(' [unverified quote]');
      cursor = end + 1;
    }
    out.write(text.substring(cursor));
    return (text: out.toString(), bad: bad, corrected: corrected);
  }

  /// Each chunk separately, so a quote never matches across the join of two chunks.
  static bool _inAny(String normalizedQuote, Iterable<String> texts) =>
      texts.any((t) => normalize(t).contains(normalizedQuote));

  /// What a quote is attributed to: the nearest reference or source tag after it, else the
  /// nearest before it. Source tags count only when [sources] is given; a tag naming nothing
  /// shown (the source check has already marked it) attributes the quote to no source.
  static (Ref?, List<ShownSource>?) _attribution(
    String text,
    int start,
    int end,
    List<ShownSource>? sources,
  ) {
    final after = text.substring(end, min(text.length, end + quoteCitationWindow));
    final beforeStart = max(0, start - 1 - quoteCitationWindow);
    final before = text.substring(beforeStart, max(beforeStart, start - 1));
    final refAfter = RefParser.matches(after).firstOrNull;
    final refBefore = RefParser.matches(before).lastOrNull;
    if (sources == null) return (refAfter?.ref ?? refBefore?.ref, null);
    final tagAfter = sourceCitationGroup.allMatches(after).firstOrNull;
    final tagBefore = sourceCitationGroup.allMatches(before).lastOrNull;
    if (tagAfter != null && (refAfter == null || tagAfter.start < refAfter.start)) {
      return (null, citedChunks(tagAfter, sources));
    }
    if (refAfter != null) return (refAfter.ref, null);
    if (tagBefore != null && (refBefore == null || tagBefore.end > refBefore.end)) {
      return (null, citedChunks(tagBefore, sources));
    }
    return (refBefore?.ref, null);
  }
}
