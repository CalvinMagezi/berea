import 'books.dart';
import 'ref_parser.dart';

final _booksByName = {for (final b in books) b.name: b};

/// The reference in a canonical label such as "Psalms 37:5" or "1 John 4:4-6". Labels in the
/// compiled file are always canonical, so this avoids the regex a typed reference needs; anything
/// else falls back to [RefParser].
Ref parseLabel(String label) {
  final space = label.lastIndexOf(' ');
  final book = space < 0 ? null : _booksByName[label.substring(0, space)];
  if (book != null) {
    final rest = label.substring(space + 1);
    final colon = rest.indexOf(':');
    final chapter = int.tryParse(colon < 0 ? rest : rest.substring(0, colon));
    if (chapter != null) {
      if (colon < 0) return Ref(book, chapter);
      final dash = rest.indexOf('-', colon);
      final start = int.tryParse(rest.substring(colon + 1, dash < 0 ? null : dash));
      final end = dash < 0 ? null : int.tryParse(rest.substring(dash + 1));
      if (start != null && (dash < 0 || end != null)) return Ref(book, chapter, start, end);
    }
  }
  return RefParser.parse(label).first;
}

/// One prayer point: a line in the first person that stands on [ref], a canonical label such as
/// "Philippians 4:6-7".
class PrayerPoint {
  final String text;
  final String ref;
  const PrayerPoint(this.text, this.ref);

  Ref get verse => parseLabel(ref);

  Map<String, Object?> toJson() => {'text': text, 'ref': ref};
  factory PrayerPoint.fromJson(Map<String, Object?> j) =>
      PrayerPoint(j['text'] as String, j['ref'] as String);
}

/// A need people bring to prayer, such as "Farming, rain and harvest". [words] are what people
/// type for it, matched on the device to offer a topic or a verse.
class PrayerTopic {
  final String id;
  final String group;
  final String title;
  final List<String> words;
  final List<PrayerPoint> points;
  const PrayerTopic(this.id, this.group, this.title, this.words, this.points);

  Map<String, Object?> toJson() => {
    'id': id,
    'group': group,
    'title': title,
    'words': words,
    'points': [for (final p in points) p.toJson()],
  };
  factory PrayerTopic.fromJson(Map<String, Object?> j) => PrayerTopic(
    j['id'] as String,
    j['group'] as String,
    j['title'] as String,
    _strings(j['words']),
    _points(j['points']),
  );
}

/// A prayer that is in the Bible itself, prayed a verse at a time from the installed text.
class BiblePrayer {
  final String id;
  final String title;
  final String ref;
  const BiblePrayer(this.id, this.title, this.ref);

  Ref get passage => parseLabel(ref);

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'ref': ref};
  factory BiblePrayer.fromJson(Map<String, Object?> j) =>
      BiblePrayer(j['id'] as String, j['title'] as String, j['ref'] as String);
}

/// One day of a prayer plan. A day without [points] is the passage prayed a verse at a time.
class PlanDay {
  final String title;
  final String ref;
  final List<PrayerPoint> points;
  const PlanDay(this.title, this.ref, this.points);

  Ref get passage => parseLabel(ref);

  Map<String, Object?> toJson() => {
    'title': title,
    'ref': ref,
    'points': [for (final p in points) p.toJson()],
  };
  factory PlanDay.fromJson(Map<String, Object?> j) =>
      PlanDay(j['title'] as String, j['ref'] as String, _points(j['points']));
}

/// A prayer plan by day. [fasting] says whether the plan offers an optional fast.
class PrayerPlan {
  final String id;
  final String title;
  final String summary;
  final bool fasting;
  final List<PlanDay> days;
  const PrayerPlan(this.id, this.title, this.summary, this.fasting, this.days);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'fasting': fasting,
    'days': [for (final d in days) d.toJson()],
  };
  factory PrayerPlan.fromJson(Map<String, Object?> j) => PrayerPlan(
    j['id'] as String,
    j['title'] as String,
    j['summary'] as String,
    j['fasting'] as bool,
    [for (final d in j['days'] as List) PlanDay.fromJson((d as Map).cast())],
  );
}

/// The health note shown whenever a fast is on. Never a fast without water.
const prayerFastingNote =
    'If you fast, skip food, never water. Pregnant, diabetic, on medicine or unwell? '
    'Talk to a health worker first.';

/// Everything the prayer places read, compiled from content/prayers by bin/build_prayers.dart.
class PrayerContent {
  static const formatVersion = 1;

  final List<PrayerTopic> topics;
  final List<BiblePrayer> biblePrayers;

  /// Chapter prayers keyed by "book.chapter", for example "40.7" for Matthew 7.
  final Map<String, List<PrayerPoint>> chapters;

  /// The verse of the day line, keyed by the verse's canonical label.
  final Map<String, String> daily;
  final List<PrayerPlan> plans;
  PrayerContent({
    this.topics = const [],
    this.biblePrayers = const [],
    this.chapters = const {},
    this.daily = const {},
    this.plans = const [],
  });

  static final empty = PrayerContent();

  static String chapterKey(Book book, int chapter) => '${book.id}.$chapter';

  PrayerTopic? topic(String? id) => topics.where((t) => t.id == id).firstOrNull;
  PrayerPlan? plan(String? id) => plans.where((p) => p.id == id).firstOrNull;
  BiblePrayer? biblePrayer(String? id) => biblePrayers.where((p) => p.id == id).firstOrNull;

  List<PrayerPoint> chapterPoints(Ref chapter) =>
      chapters[chapterKey(chapter.book, chapter.chapter)] ?? const [];

  /// The verse of the day line for [verse], or null when it has none.
  String? dailyLine(Ref verse) => daily[Ref(verse.book, verse.chapter, verse.verseStart).label];

  Map<String, Object?> toJson() => {
    'v': formatVersion,
    'topics': [for (final t in topics) t.toJson()],
    'bible': [for (final b in biblePrayers) b.toJson()],
    'chapters': {
      for (final e in chapters.entries) e.key: [for (final p in e.value) p.toJson()],
    },
    'daily': daily,
    'plans': [for (final p in plans) p.toJson()],
  };

  factory PrayerContent.fromJson(Map<String, Object?> j) => PrayerContent(
    topics: [for (final t in j['topics'] as List) PrayerTopic.fromJson((t as Map).cast())],
    biblePrayers: [for (final b in j['bible'] as List) BiblePrayer.fromJson((b as Map).cast())],
    chapters: {for (final e in (j['chapters'] as Map).entries) e.key as String: _points(e.value)},
    daily: (j['daily'] as Map).cast<String, String>(),
    plans: [for (final p in j['plans'] as List) PrayerPlan.fromJson((p as Map).cast())],
  );

  /// Every authored point by chapter key and verse number, built once: the reader asks for it for
  /// each chapter it opens.
  late final Map<String, Map<int, List<PrayerPoint>>> _byChapter = _indexPoints();

  Map<String, Map<int, List<PrayerPoint>>> _indexPoints() {
    final out = <String, Map<int, List<PrayerPoint>>>{};
    void add(PrayerPoint p) {
      final r = p.verse;
      final start = r.verseStart;
      if (start == null) return;
      final verses = out.putIfAbsent(chapterKey(r.book, r.chapter), () => {});
      for (var v = start; v <= (r.verseEnd ?? start); v++) {
        (verses[v] ??= []).add(p);
      }
    }

    for (final t in topics) {
      t.points.forEach(add);
    }
    chapters.values.expand((l) => l).forEach(add);
    for (final plan in plans) {
      plan.days.expand((d) => d.points).forEach(add);
    }
    daily.forEach((ref, text) => add(PrayerPoint(text, ref)));
    return out;
  }

  /// The authored points standing on each verse of [chapter], by verse number. Marks the verses
  /// that have words to pray.
  Map<int, List<PrayerPoint>> pointsInChapter(Ref chapter) =>
      _byChapter[chapterKey(chapter.book, chapter.chapter)] ?? const {};

  /// The points to pray for [verse]: those whose reference includes it, topic points first.
  List<PrayerPoint> pointsForVerse(Ref verse) {
    final start = verse.verseStart;
    if (start == null) return const [];
    final byVerse = pointsInChapter(verse);
    final out = <PrayerPoint>[];
    final seen = <String>{};
    for (var v = start; v <= (verse.verseEnd ?? start); v++) {
      for (final p in byVerse[v] ?? const <PrayerPoint>[]) {
        if (seen.add(p.text)) out.add(p);
      }
    }
    return out;
  }

  /// Topics ranked by how many of [text]'s words they list, best first, none when nothing
  /// matches. Matching is on the device, by whole words or a shared stem.
  List<PrayerTopic> topicsFor(String text) {
    final typed = _stems(text);
    if (typed.isEmpty) return const [];
    final scored = <PrayerTopic, int>{};
    for (final t in topics) {
      final listed = _stems('${t.title} ${t.words.join(' ')}');
      final hits = typed.where((w) => listed.any((l) => _sameStem(w, l))).length;
      if (hits > 0) scored[t] = hits;
    }
    final ranked = scored.keys.toList()..sort((a, b) => scored[b]!.compareTo(scored[a]!));
    return ranked;
  }
}

const _minStem = 3;

bool _sameStem(String a, String b) {
  final short = a.length <= b.length ? a : b;
  final long = identical(short, a) ? b : a;
  return short.length >= _minStem && long.startsWith(short);
}

final _suffixes = RegExp(r'(ing|ed|es|s)$');

List<String> _stems(String text) => [
  for (final w in text.toLowerCase().split(RegExp(r"[^a-z']+")))
    if (w.length >= _minStem && !_stopWords.contains(w)) w.replaceFirst(_suffixes, ''),
];

const _stopWords = {
  'the', 'and', 'for', 'with', 'from', 'that', 'this', 'not', 'are', 'was', 'has', 'have', //
  'who', 'what', 'when', 'will', 'his', 'her', 'our', 'your', 'you', 'but', 'all', 'about',
};

List<String> _strings(Object? v) => [for (final s in v as List) s as String];

List<PrayerPoint> _points(Object? v) => [
  for (final p in v as List) PrayerPoint.fromJson((p as Map).cast()),
];
