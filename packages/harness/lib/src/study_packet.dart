import 'dart:convert';
import 'dart:math';

import 'bible_db.dart';
import 'commentary.dart';
import 'ref_parser.dart';
import 'sources.dart';
import 'sword.dart';
import 'word_study.dart';

/// The packet reads the BSB, whose headings mark its sections.
const packetTranslation = 'BSB';

/// Key words studied per packet.
const packetKeyWords = 6;

/// Other uses of each key word shown beside it.
const keyWordUses = 3;

/// Cross references kept per section.
const sectionCrossReferences = 4;

/// Verses from the other testament kept as witnesses.
const packetWitnesses = 6;

/// Cross references read per verse when looking for witnesses.
const _witnessCandidates = 8;

/// Cross references read per section, so some remain once those inside the reading are dropped.
const _crossReferenceCandidates = 8;

/// Heading kinds that start a section; "ms" divides a book (Psalms) and opens none.
const _sectionKinds = {'s1', 's2', 'qa'};

/// One section of a reading: its verses, the BSB headings over it, and what comments on it.
class PacketSection {
  final Ref ref;

  /// The headings printed at the section's start, or those of the section it begins inside.
  final List<Heading> headings;

  /// True when the reading starts inside the section its [headings] open.
  final bool inherited;
  final List<Verse> verses;
  final List<SourceChunk> commentary;
  final List<Verse> crossReferences;

  /// The first verse of each parallel passage its headings list, outside the readings.
  final List<Verse> parallelVerses;
  const PacketSection({
    required this.ref,
    required this.headings,
    required this.inherited,
    required this.verses,
    required this.commentary,
    required this.crossReferences,
    required this.parallelVerses,
  });

  String get title => headings.isEmpty ? ref.label : headings.map((h) => h.text).join(', ');
}

/// A word worth studying in the reading, with where it first appears and other uses.
class KeyWord {
  final LexEntry entry;
  final int count;
  final Ref firstUse;
  final List<Verse> uses;
  const KeyWord(this.entry, this.count, this.firstUse, this.uses);
}

/// A verse elsewhere in Scripture that a verse of the reading points to.
typedef Witness = ({Verse from, Verse to});

/// What a packet was built from, so a cached script or recording knows when it is stale.
class PacketInputs {
  final String translation;

  /// The Bible database's build stamp.
  final String bible;
  final List<String> packs;
  final List<Ref> readings;
  const PacketInputs(this.translation, this.bible, this.packs, this.readings);

  Map<String, Object> toJson() => {
    'translation': translation,
    'bible': bible,
    'packs': packs,
    'readings': [for (final r in readings) r.label],
  };

  String get fingerprint => jsonEncode(toJson());
}

/// Everything a deep dive on a notebook's readings may say, gathered without a model: the BSB
/// sections with their headings and parallels, cross references, key words and commentary.
class StudyPacket {
  final PacketInputs inputs;
  final List<PacketSection> sections;
  final List<KeyWord> keyWords;
  final List<SourceChunk> introductions;
  final List<Witness> witnesses;
  const StudyPacket({
    required this.inputs,
    required this.sections,
    required this.keyWords,
    required this.introductions,
    required this.witnesses,
  });

  bool get isEmpty => sections.isEmpty;

  List<Verse> get verses => [for (final s in sections) ...s.verses];

  /// One line per section, its headings and verses, for every beat.
  List<String> get outline => [
    for (final s in sections) '${s.ref.label}: ${s.title}${s.inherited ? ' (continued)' : ''}',
  ];
}

/// The packet for [readings], in the order given, each verse once; commentary comes from
/// [commentary] when packs are installed.
StudyPacket buildStudyPacket(BibleDb db, List<Ref> readings, {CommentaryLibrary? commentary}) {
  final refs = _merged(readings);
  final library = commentary ?? CommentaryLibrary();
  // A comment on verses two readings share goes to the first.
  final claimed = <String>{};
  final sections = [for (final r in refs) ..._sections(db, r, library, claimed)];
  return StudyPacket(
    inputs: PacketInputs(packetTranslation, db.built, library.installed.toList()..sort(), refs),
    sections: sections,
    keyWords: _keyWords(db, sections),
    introductions: _distinctChunks([for (final r in refs) ...commentaryIntroductions(library, r)]),
    witnesses: _witnesses(db, sections),
  );
}

/// [readings] with the ranges of one chapter that overlap or touch merged into one, in the order
/// first seen: "John 3:1-10" and "John 3:8-21" become "John 3:1-21".
List<Ref> _merged(List<Ref> readings) {
  var out = <Ref>[];
  for (final r in readings) {
    var joined = r;
    int? at;
    final kept = <Ref>[];
    for (final o in out) {
      if (!_joins(o, joined)) {
        kept.add(o);
        continue;
      }
      joined = _union(o, joined);
      at ??= kept.length;
    }
    out = kept..insert(at ?? kept.length, joined);
  }
  return out;
}

bool _joins(Ref a, Ref b) {
  if (a.book.id != b.book.id || a.chapter != b.chapter) return false;
  if (a.verseStart == null || b.verseStart == null) return true;
  return a.verseStart! <= _end(b) + 1 && b.verseStart! <= _end(a) + 1;
}

int _end(Ref r) => r.verseEnd ?? r.verseStart!;

Ref _union(Ref a, Ref b) => a.verseStart == null || b.verseStart == null
    ? Ref(a.book, a.chapter)
    : Ref(a.book, a.chapter, min(a.verseStart!, b.verseStart!), max(_end(a), _end(b)));

List<SourceChunk> _distinctChunks(List<SourceChunk> chunks) {
  final seen = <String>{};
  return [
    for (final c in chunks)
      if (seen.add(c.key)) c,
  ];
}

/// [reading] cut at the BSB section headings inside it. Comments already in [claimed] are left
/// to the section that has them.
List<PacketSection> _sections(
  BibleDb db,
  Ref reading,
  CommentaryLibrary library,
  Set<String> claimed,
) {
  final verses = db.verses(reading, translation: packetTranslation);
  if (verses.isEmpty) return const [];
  final headings = db.headings(reading.book, reading.chapter, translation: packetTranslation);
  final starts = {
    for (final h in headings)
      if (_sectionKinds.contains(h.kind)) h.verse,
  };
  final runs = <List<Verse>>[];
  for (final v in verses) {
    if (runs.isEmpty || starts.contains(v.verse)) runs.add([]);
    runs.last.add(v);
  }
  final comments = [for (final _ in runs) <SourceChunk>[]];
  for (final c in commentaryPieces(library, reading)) {
    if (!claimed.add(c.key)) continue;
    // The last section starting at or before the comment, so one on a verse the BSB omits
    // (Matthew 17:21) still has a home.
    final from = max(c.ref!.verseStart ?? 1, verses.first.verse);
    comments[max(0, runs.lastIndexWhere((run) => run.first.verse <= from))].add(c);
  }
  return [
    for (var i = 0; i < runs.length; i++)
      _section(
        db,
        reading,
        runs[i],
        headings,
        comments[i],
        inherited: !starts.contains(runs[i].first.verse),
      ),
  ];
}

PacketSection _section(
  BibleDb db,
  Ref reading,
  List<Verse> run,
  List<Heading> headings,
  List<SourceChunk> commentary, {
  required bool inherited,
}) {
  final start = run.first.verse;
  final ref = Ref(reading.book, reading.chapter, start, run.last.verse);
  final opening = headings.where((h) => h.verse <= start && h.kind != 'ms').toList();
  final at = opening.isEmpty ? null : opening.last.verse;
  final shown = [
    for (final h in opening)
      if (h.verse == at) h,
  ];
  return PacketSection(
    ref: ref,
    headings: shown,
    inherited: inherited && at != null,
    verses: run,
    commentary: commentary,
    crossReferences: _crossReferences(db, ref, reading),
    parallelVerses: _firstVerses(db, [
      for (final h in shown)
        for (final r in RefParser.parse(h.refs))
          if (!r.overlaps(reading)) r,
    ]),
  );
}

/// The first verse of each passage [ref] points to most, outside [reading].
List<Verse> _crossReferences(BibleDb db, Ref ref, Ref reading) => _firstVerses(db, [
  for (final x in db.xrefs(ref, k: _crossReferenceCandidates))
    if (!x.to.overlaps(reading)) x.to,
]).take(sectionCrossReferences).toList();

/// The first verse of each of [refs], each verse once: "Romans 5:8" and "Romans 5:8-9" are one.
List<Verse> _firstVerses(BibleDb db, List<Ref> refs) {
  final seen = <String>{};
  return [
    for (final r in refs)
      for (final v in db.passage(_firstVerse(r), translation: packetTranslation))
        if (seen.add(v.label)) v,
  ];
}

Ref _firstVerse(Ref r) => Ref(r.book, r.chapter, r.verseStart, r.verseStart);

Ref _verseRef(Verse v) => Ref(v.book, v.chapter, v.verse, v.verse);

/// Words of the reading ranked by how often it uses them, weighted by how rare they are in the
/// Bible: "born" in John 3 before "to be". Names and function words are left out.
List<KeyWord> _keyWords(BibleDb db, List<PacketSection> sections) {
  final (counts, firstUse) = _wordCounts(db, sections);
  if (counts.isEmpty) return const [];
  final total = db.verseCount(translation: packetTranslation);
  final scored = <(double, KeyWord)>[];
  for (final MapEntry(key: code, value: n) in counts.entries) {
    final entry = db.lexicon(code);
    if (entry == null || !_studied(entry)) continue;
    final idf = log(total / max(1, db.wordVerseCount(code)));
    scored.add((n * idf * idf, KeyWord(entry, n, firstUse[code]!, const [])));
  }
  scored.sort(
    (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.entry.key.compareTo(b.$2.entry.key),
  );
  return [
    for (final (_, k) in scored.take(packetKeyWords))
      KeyWord(
        k.entry,
        k.count,
        k.firstUse,
        db.wordSample(
          k.entry.key,
          k: keyWordUses,
          exclude: k.firstUse,
          translation: packetTranslation,
        ),
      ),
  ];
}

/// How often the reading uses each studied code, and the verse it first does.
(Map<String, int>, Map<String, Ref>) _wordCounts(BibleDb db, List<PacketSection> sections) {
  final counts = <String, int>{};
  final firstUse = <String, Ref>{};
  for (final v in [for (final s in sections) ...s.verses]) {
    final ref = _verseRef(v);
    for (final code in db.words(ref).map(studyCode).nonNulls) {
      counts[code] = (counts[code] ?? 0) + 1;
      firstUse.putIfAbsent(code, () => ref);
    }
  }
  return (counts, firstUse);
}

/// Verbs, nouns, adjectives and adverbs; not names.
bool _studied(LexEntry e) {
  if (e.pos.startsWith('N:')) return false;
  final pos = partOfSpeech(e.pos);
  return pos == 'verb' || pos.startsWith('noun') || pos == 'adjective' || pos == 'adverb';
}

/// Verses in the other testament the reading's verses point to, most voted first, each once and
/// beside the verse that points to it most.
List<Witness> _witnesses(BibleDb db, List<PacketSection> sections) {
  final best = <String, (int, Witness)>{};
  final order = <String>[];
  for (final v in [for (final s in sections) ...s.verses]) {
    final other = v.book.id <= otBookCount;
    for (final x in db.xrefs(_verseRef(v), k: _witnessCandidates, toNewTestament: other)) {
      final to = db.passage(_firstVerse(x.to), translation: packetTranslation).firstOrNull;
      if (to == null || (best[to.label]?.$1 ?? -1) >= x.votes) continue;
      if (!best.containsKey(to.label)) order.add(to.label);
      best[to.label] = (x.votes, (from: v, to: to));
    }
  }
  // Stable: equal votes keep reading order.
  final ranked = [for (var i = 0; i < order.length; i++) (i, best[order[i]]!)]
    ..sort((a, b) => a.$2.$1 != b.$2.$1 ? b.$2.$1.compareTo(a.$2.$1) : a.$1.compareTo(b.$1));
  return [for (final r in ranked.take(packetWitnesses)) r.$2.$2];
}
