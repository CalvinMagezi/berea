import 'package:berea_harness/berea_harness.dart';

import 'prayer_store.dart';

/// Verses many people stand on, offered when nothing in a prayer's words matches a topic.
final commonVerses = [
  for (final r in const [
    'Philippians 4:6-7',
    'Psalm 23:1',
    'Isaiah 41:10',
    'Proverbs 3:5-6',
    'Romans 8:28',
  ])
    RefParser.parse(r).first,
];

const maxSuggestions = 3;

/// A topic matched to a prayer's own words, and the verses it offers to stand on.
class VerseSuggestion {
  final PrayerTopic? topic;
  final List<Ref> verses;
  const VerseSuggestion(this.topic, this.verses);
}

/// Matches [text] against the topics' search words on the device and offers the best topic's
/// verses, neighbouring verses of one chapter joined into a range. With no match, the verses
/// many people stand on.
VerseSuggestion suggestVerses(PrayerContent content, String text) {
  final topic = content.topicsFor(text).firstOrNull;
  if (topic == null) return VerseSuggestion(null, commonVerses);
  final refs = <Ref>[];
  for (final p in topic.points) {
    final r = p.verse;
    final last = refs.lastOrNull;
    if (last != null && _adjacent(last, r)) {
      refs[refs.length - 1] = Ref(
        last.book,
        last.chapter,
        last.verseStart,
        r.verseEnd ?? r.verseStart,
      );
    } else if (!refs.contains(r)) {
      refs.add(r);
    }
  }
  return VerseSuggestion(topic, refs.take(maxSuggestions).toList());
}

bool _adjacent(Ref a, Ref b) =>
    a.book.id == b.book.id &&
    a.chapter == b.chapter &&
    a.verseStart != null &&
    b.verseStart == (a.verseEnd ?? a.verseStart!) + 1;

/// An answered prayer shared as a testimony: the request, who it was for unless left out, the
/// person's own line, the day, and the verse they stood on with its words when asked.
String testimonyShareText(
  Prayer p, {
  String? verseText,
  bool includeVerse = true,
  bool includeWho = false,
}) {
  final b = StringBuffer('Answered prayer: ${p.title}');
  if (includeWho && p.forWhom.isNotEmpty) b.write('\nFor ${p.forWhom}');
  if (p.answer != null) b.write('\n${p.answer}');
  if (includeVerse && p.verse != null) {
    b.write('\nI stood on ${p.verse}');
    if (verseText != null && verseText.isNotEmpty) b.write(': “$verseText”');
  }
  return b.toString();
}

const _listTopicCount = 4;

/// The topics Prayer offers first: those the reader's prayers are prayed with or match by their
/// words, then the usual needs, up to four.
List<PrayerTopic> topicsForList(PrayerContent content, List<Prayer> praying) {
  final out = <PrayerTopic>[];
  void add(PrayerTopic? t) {
    if (t != null && !out.contains(t)) out.add(t);
  }

  for (final p in praying) {
    add(content.topic(p.topic));
  }
  for (final p in praying) {
    add(content.topicsFor('${p.title} ${p.note}').firstOrNull);
  }
  for (final id in const ['fear', 'guidance', 'healing', 'thanksgiving']) {
    add(content.topic(id));
  }
  content.topics.forEach(add);
  return out.take(_listTopicCount).toList();
}
