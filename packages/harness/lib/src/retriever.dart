import 'bible_db.dart';
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

  /// Notebook and commentary passages for a notebook answer, best first.
  final List<SourceChunk> sources;
  const StudyContext({
    required this.refs,
    required this.passages,
    required this.words,
    required this.lexicon,
    required this.xrefVerses,
    required this.searchHits,
    this.sources = const [],
  });

  /// Every verse in this context. For what the model was shown, use the context PromptBuilder
  /// returns: the budget may cut some of what was retrieved.
  Iterable<Verse> get allVerses => [...passages, ...xrefVerses, ...searchHits];
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
          if (e != null) lexicon[s] = e;
        }
      }
      for (final x in db.xrefs(primary, k: tier.xrefK)) {
        final target = Ref(x.to.book, x.to.chapter, x.to.verseStart, x.to.verseStart);
        for (final v in db.passage(target, translation: translation)) {
          if (seen.add(v.label)) xrefVerses.add(v);
        }
      }
    }

    final hits = uses.isNotEmpty
        ? uses
        : db.search(userText, translation: translation, k: tier.searchK);
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
      sources: sources,
    );
  }
}
