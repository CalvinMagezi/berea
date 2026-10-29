import 'package:berea/prayer_store.dart';
import 'package:berea/prayer_verse.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final content = PrayerContent(
    topics: [
      const PrayerTopic(
        'job-search',
        'Daily life',
        'Looking for work',
        ['interview', 'hired'],
        [
          PrayerPoint('Ask.', 'Matthew 7:7'),
          PrayerPoint('Trust.', 'Proverbs 3:5'),
          PrayerPoint('Acknowledge.', 'Proverbs 3:6'),
          PrayerPoint('Commit.', 'Psalm 37:5'),
          PrayerPoint('Supply.', 'Philippians 4:19'),
        ],
      ),
    ],
  );

  test('a prayer about an interview is offered Looking for work verses, neighbours joined', () {
    final s = suggestVerses(content, "Daniel's interview on Thursday");
    expect(s.topic!.id, 'job-search');
    expect([for (final r in s.verses) r.label], ['Matthew 7:7', 'Proverbs 3:5-6', 'Psalms 37:5']);
  });

  test('with no match, the verses many people stand on', () {
    final s = suggestVerses(content, 'my sister');
    expect(s.topic, isNull);
    expect(s.verses.length, 5);
    expect(s.verses.first.label, 'Philippians 4:6-7');
  });

  test('a testimony carries the verse, and leaves out who it was for unless asked', () {
    final p = Prayer(
      id: 1,
      title: 'Job interview at the bank',
      forWhom: 'Sam',
      verse: 'Proverbs 3:5-6',
      created: DateTime(2026, 10, 1),
      answered: DateTime(2026, 10, 28),
      answer: 'I got the job. I start on 3 November.',
    );
    expect(
      testimonyShareText(p, verseText: 'Trust in the LORD.'),
      'Answered prayer: Job interview at the bank\nI got the job. I start on 3 November.\n'
      'I stood on Proverbs 3:5-6: “Trust in the LORD.”',
    );
    expect(
      testimonyShareText(p, includeVerse: false, includeWho: true),
      'Answered prayer: Job interview at the bank\nFor Sam\nI got the job. I start on 3 November.',
    );
  });
}
