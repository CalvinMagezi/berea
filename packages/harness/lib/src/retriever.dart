import 'bible_db.dart';
import 'books.dart';
import 'ref_parser.dart';
import 'sources.dart';
import 'tier.dart';
import 'word_study.dart';

class StudyContext {
  final List<Ref> refs;
  final List<Verse> passages;
  final List<WordTag> words;
  final Map<String, LexEntry> lexicon;
  final List<Verse> xrefVerses;
  final List<Verse> searchHits;

  /// The verses around a short passage, within its section.
  final List<Verse> surrounding;

  /// Notebook and commentary passages for a notebook answer, best first.
  final List<SourceChunk> sources;
  const StudyContext({
    required this.refs,
    required this.passages,
    required this.words,
    required this.lexicon,
    required this.xrefVerses,
    required this.searchHits,
    this.surrounding = const [],
    this.sources = const [],
  });

  /// Every verse in this context. For what the model was shown, use the context PromptBuilder
  /// returns: the budget may cut some of what was retrieved.
  Iterable<Verse> get allVerses => [...passages, ...surrounding, ...xrefVerses, ...searchHits];
}

/// Names shorter than this are skipped as aliases: "is", "am" and "re" are ordinary words.
const _minAliasLength = 4;

/// Longer passages carry their own context; only these get the verses around them.
const _maxContextualizedVerses = 3;

/// Every book name and long alias, longest first, with flexible spacing ("1 Corinthians").
final _bookName = () {
  final names = <String>{
    for (final b in books) ...[b.name, ...b.aliases.where((a) => a.length >= _minAliasLength)],
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  final alt = names.map((n) => RegExp.escape(n).replaceAll(' ', r'\s+')).join('|');
  return RegExp('\\b(?:$alt)\\b', caseSensitive: false);
}();

/// Book names that are also everyday words ("my job", "acts of kindness"): only a capital makes
/// them a book.
const _everydayWords = {'job', 'mark', 'acts', 'numbers', 'judges', 'song', 'revelation'};

/// The book names written in [text], skipping everyday words written in lower case.
Iterable<Match> _bookMentions(String text) => _bookName.allMatches(text).where((m) {
  final w = m[0]!;
  return !_everydayWords.contains(w.toLowerCase()) || w[0] != w[0].toLowerCase();
});

/// Words before a book name that make it the place to look: "in Romans", "the book of Job".
final _scopeBefore = RegExp(
  r'\b(in|book of|gospel of|letter to|epistle to|epistle of)(\s+the)?\s*$',
  caseSensitive: false,
);

/// Words after a book name that make it the speaker: "Romans teach", "James says".
final _scopeAfter = RegExp(r'^\s+(teach|teaches|say|says|tell|tells)\b', caseSensitive: false);

/// The book a topical question asks to search within, with the span of the name and its cue
/// ("in Romans", "James says"), or null. A bare name is not enough: "James and John" are people
/// and "Who was Daniel?" wants every verse about him.
({Match name, int start, int end})? _bookScope(String text) {
  for (final m in _bookMentions(text)) {
    final before = _scopeBefore.firstMatch(text.substring(0, m.start));
    final after = _scopeAfter.firstMatch(text.substring(m.end));
    if (before == null && after == null) continue;
    return (
      name: m,
      start: before?.start ?? m.start,
      end: after == null ? m.end : m.end + after.end,
    );
  }
  return null;
}

class Retriever {
  final BibleDb db;
  final String translation;
  Retriever(this.db, {this.translation = defaultTranslation});

  StudyContext retrieve(String userText, Tier tier, {List<SourceChunk> sources = const []}) {
    final refs = RefParser.parse(userText);
    final passages = [for (final r in refs) ...db.passage(r, translation: translation)];
    final seen = {for (final v in passages) v.label};

    var words = const <WordTag>[];
    final lexicon = <String, LexEntry>{};
    final xrefVerses = <Verse>[];

    // A word study names its Strong's number: that entry leads the lexicon, and the word's other
    // uses take the place of search hits, which would only match the question's English.
    final focus = strongsIn(userText);
    final focusEntry = focus == null ? null : db.lexicon(focus);
    if (focusEntry != null) lexicon[focusEntry.key] = focusEntry;
    final uses = focusEntry == null
        ? const <Verse>[]
        : db.wordSample(
            focus!,
            k: tier.searchK,
            exclude: refs.firstOrNull,
            translation: translation,
          );

    if (refs.isNotEmpty) {
      final primary = refs.first;
      words = db.words(primary);
      for (final w in words) {
        for (final s in w.strongs.split(' ')) {
          if (s.isEmpty || lexicon.containsKey(s) || lexicon.length >= tier.lexiconWords) continue;
          final e = db.lexicon(s);
          if (e != null && !isFunctionWord(e)) lexicon[s] = e;
        }
      }
      for (final x in db.xrefs(primary, k: tier.xrefK)) {
        final target = Ref(x.to.book, x.to.chapter, x.to.verseStart, x.to.verseStart);
        for (final v in db.passage(target, translation: translation)) {
          if (seen.add(v.label)) xrefVerses.add(v);
        }
      }
    }

    final surrounding = refs.length == 1 ? _surrounding(refs.single, tier, seen) : const <Verse>[];

    final hits = uses.isNotEmpty
        ? uses
        : passages.isNotEmpty
        ? _passageSearch(userText, tier)
        : _topicSearch(userText, tier);
    final searchHits = [
      for (final v in hits)
        if (seen.add(v.label)) v,
    ];

    // With no reference to anchor on, follow the cross-reference graph from the search hits: the
    // passages most of them point to are usually the canonical ones on the topic.
    if (refs.isEmpty && hits.isNotEmpty && uses.isEmpty) {
      final hubs = db.crossReferenceHubs([
        for (final v in hits) Ref(v.book, v.chapter, v.verse, v.verse),
      ], k: tier.xrefK);
      for (final r in hubs) {
        for (final v in db.passage(r, translation: translation)) {
          if (seen.add(v.label)) xrefVerses.add(v);
        }
      }
    }

    return StudyContext(
      refs: refs,
      passages: passages,
      words: words,
      lexicon: lexicon,
      xrefVerses: xrefVerses,
      searchHits: searchHits,
      surrounding: surrounding,
      sources: sources,
    );
  }

  /// Up to [Tier.contextVerses] on each side of a passage of a few verses, kept inside the BSB
  /// section that holds it so the window never runs into the next story.
  List<Verse> _surrounding(Ref ref, Tier tier, Set<String> seen) {
    final start = ref.verseStart;
    if (start == null || tier.contextVerses == 0) return const [];
    final end = ref.verseEnd ?? start;
    if (end - start + 1 > _maxContextualizedVerses) return const [];
    final breaks = {for (final h in db.headings(ref.book, ref.chapter)) h.verse};
    var from = start;
    while (from > 1 && start - from < tier.contextVerses && !breaks.contains(from)) {
      from--;
    }
    var to = end;
    while (to - end < tier.contextVerses && !breaks.contains(to + 1)) {
      to++;
    }
    final window = Ref(ref.book, ref.chapter, from, to);
    return [
      for (final v in db.passage(window, translation: translation))
        if (seen.add(v.label)) v,
    ];
  }

  /// Verses on what a passage question asks beside its reference ("the parable of the rich
  /// fool"). References and book names are cut first: "Luke" would match Colossians 4:14.
  List<Verse> _passageSearch(String userText, Tier tier) {
    if (tier.passageSearchK == 0) return const [];
    // Blanked rather than removed, so overlapping spans (a reference holds its book) keep offsets.
    final chars = userText.split('');
    for (final (start, end) in [
      for (final m in RefParser.matches(userText)) (m.start, m.end),
      for (final m in _bookMentions(userText)) (m.start, m.end),
    ]) {
      chars.fillRange(start, end, ' ');
    }
    final text = chars.join();
    return db.search(text, translation: translation, k: tier.passageSearchK);
  }

  /// A book named as the place to look scopes the search to it, falling back to the whole Bible.
  List<Verse> _topicSearch(String userText, Tier tier) {
    final scope = _bookScope(userText);
    final book = scope == null ? null : bookFor(scope.name[0]!.replaceAll(RegExp(r'\s+'), ' '));
    if (book != null) {
      // The name and its cue are dropped: every verse of the book is already in scope, and "gospel"
      // or "tells" would only rank verses that happen to use the word.
      final text = userText.replaceRange(scope!.start, scope.end, ' ');
      final scoped = db.search(text, translation: translation, k: tier.searchK, book: book);
      if (scoped.isNotEmpty) return scoped;
    }
    return db.search(userText, translation: translation, k: tier.searchK);
  }
}
